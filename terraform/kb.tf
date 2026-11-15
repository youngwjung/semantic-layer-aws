# IAM
resource "aws_iam_role" "kb" {
  name = "${local.project}-kb-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "bedrock.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
        }
        ArnLike = {
          "AWS:SourceArn" = "arn:aws:bedrock:${local.aws_region}:${local.account_id}:knowledge-base/*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "kb" {
  name = "${local.project}-kb"
  role = aws_iam_role.kb.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = [
          "arn:aws:bedrock:${local.aws_region}::foundation-model/amazon.titan-embed-text-v2:0",
          "arn:aws:bedrock:${local.aws_region}::foundation-model/cohere.rerank-v3-5:0"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:Rerank"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:ListFoundationModels",
          "bedrock:ListCustomModels"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          module.docs_bucket.s3_bucket_arn
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = local.account_id
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${module.docs_bucket.s3_bucket_arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = local.account_id
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "aoss:APIAccessAll"
        ]
        Resource = [
          aws_opensearchserverless_collection.kb.arn
        ]
      }
    ]
  })
}

# --- 비정형 데이터 ---
# S3
module "docs_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.17.0"

  bucket_prefix = "${local.project}-docs-"
}

locals {
  docs_src_dir = "${path.module}/../docs"
  docs_files   = fileset(local.docs_src_dir, "**")
}

resource "aws_s3_object" "docs" {
  for_each = local.docs_files

  bucket = module.docs_bucket.s3_bucket_id
  key    = each.value
  source = "${local.docs_src_dir}/${each.value}"
  etag   = filemd5("${local.docs_src_dir}/${each.value}")
}

# OpenSearch
locals {
  vector_field   = "bedrock-knowledge-base-default-vector"
  text_field     = "AMAZON_BEDROCK_TEXT_CHUNK"
  metadata_field = "AMAZON_BEDROCK_METADATA"
}

resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "${local.project}-encryption"
  type = "encryption"
  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection",
        Resource = [
          "collection/${local.project}"
        ]
      }
    ]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name = "${local.project}-network"
  type = "network"
  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection",
        Resource = ["collection/${local.project}"
        ]
      }
    ]
    AllowFromPublic = true
  }])
}

resource "aws_opensearchserverless_access_policy" "data" {
  name = "${local.project}-data"
  type = "data"
  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection",
        Resource     = ["collection/${local.project}"],
        Permission   = ["aoss:*"]
      },
      {
        ResourceType = "index",
        Resource     = ["index/${local.project}/*"],
        Permission   = ["aoss:*"]
      }
    ]
    Principal = [
      data.aws_caller_identity.current.arn,
      aws_iam_role.kb.arn
    ]
  }])
}

resource "aws_opensearchserverless_collection" "kb" {
  name = local.project
  type = "VECTORSEARCH"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network
  ]
}

resource "opensearch_index" "kb" {
  name      = "bedrock-knowledge-base-default-index"
  index_knn = true
  mappings = jsonencode({
    properties = {
      (local.vector_field) = {
        type      = "knn_vector"
        dimension = 1024
        method = {
          name       = "hnsw",
          engine     = "faiss",
          space_type = "l2",
          parameters = {}
        }
      }
      (local.text_field) = {
        type = "text"
      }
      (local.metadata_field) = {
        type  = "text",
        index = false
      }
    }
  })

  force_destroy = true

  depends_on = [
    aws_opensearchserverless_access_policy.data
  ]

  lifecycle {
    ignore_changes = [mappings]
  }
}

# Bedrock KB
resource "aws_bedrockagent_knowledge_base" "docs" {
  name     = "${local.project}-docs"
  role_arn = aws_iam_role.kb.arn
  knowledge_base_configuration {
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${local.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
    }
    type = "VECTOR"
  }
  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.kb.arn
      vector_index_name = opensearch_index.kb.name
      field_mapping {
        vector_field   = local.vector_field
        text_field     = local.text_field
        metadata_field = local.metadata_field
      }
    }
  }

  tags = {
    "mcp-multirag-kb" = "true"
  }
}

resource "aws_bedrockagent_data_source" "docs" {
  knowledge_base_id    = aws_bedrockagent_knowledge_base.docs.id
  name                 = "${local.project}-docs-s3"
  data_deletion_policy = "RETAIN"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = module.docs_bucket.s3_bucket_arn
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "HIERARCHICAL"
      hierarchical_chunking_configuration {
        level_configuration {
          max_tokens = 1500
        }
        level_configuration {
          max_tokens = 300
        }
        overlap_tokens = 60
      }
    }
  }
}

resource "terraform_data" "kb_sync" {
  triggers_replace = {
    data_source_id = aws_bedrockagent_data_source.docs.data_source_id
    docs_hash      = sha1(join(",", [for k, v in aws_s3_object.docs : "${k}:${v.etag}"]))
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws bedrock-agent start-ingestion-job \
        --region ${local.aws_region} \
        --knowledge-base-id ${aws_bedrockagent_knowledge_base.docs.id} \
        --data-source-id ${aws_bedrockagent_data_source.docs.data_source_id}
    EOT
  }

  depends_on = [
    aws_s3_object.docs
  ]
}
