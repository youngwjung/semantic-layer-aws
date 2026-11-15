# S3
module "tables_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.17.0"

  bucket_prefix = "${local.project}-tables-"
}

locals {
  tables_src_dir = "${path.module}/../sql/data"
  tables_files   = fileset(local.tables_src_dir, "*.csv")
  tables = {
    for f in local.tables_files : trimsuffix(f, ".csv") => f
  }
  ddl_statements = [
    for s in split(";", file("${path.module}/../sql/ddl.sql")) : trimspace(s)
    if trimspace(s) != ""
  ]
}

resource "aws_s3_object" "tables" {
  for_each = local.tables_files

  bucket = module.tables_bucket.s3_bucket_id
  key    = each.value
  source = "${local.tables_src_dir}/${each.value}"
  etag   = filemd5("${local.tables_src_dir}/${each.value}")
}

# IAM 역할
resource "aws_iam_role" "redshift" {
  name = "${local.project}-redshift-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = [
          "redshift.amazonaws.com", "redshift-serverless.amazonaws.com"
        ]
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "redshift_s3" {
  name = "${local.project}-redshift-s3"
  role = aws_iam_role.redshift.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject", "s3:ListBucket"
      ]
      Resource = [
        module.tables_bucket.s3_bucket_arn,
        "${module.tables_bucket.s3_bucket_arn}/*"
      ]
    }]
  })
}

resource "aws_redshiftserverless_namespace" "this" {
  namespace_name       = local.project
  db_name              = "dev"
  iam_roles            = [aws_iam_role.redshift.arn]
  default_iam_role_arn = aws_iam_role.redshift.arn
}

resource "aws_redshiftserverless_workgroup" "this" {
  namespace_name = aws_redshiftserverless_namespace.this.namespace_name
  workgroup_name = local.project
  base_capacity  = 4
}

locals {
  create_schema_statements = {
    for s in local.ddl_statements :
    regex("(?i)CREATE SCHEMA\\s+(?:IF NOT EXISTS\\s+)?(\\S+)", s)[0] => s
    if startswith(upper(s), "CREATE SCHEMA")
  }
}

resource "aws_redshiftdata_statement" "schema" {
  for_each = local.create_schema_statements

  workgroup_name = aws_redshiftserverless_workgroup.this.workgroup_name
  database       = aws_redshiftserverless_namespace.this.db_name
  secret_arn     = aws_redshiftserverless_namespace.this.admin_password_secret_arn
  sql            = each.value

  lifecycle {
    ignore_changes = all
  }
}

locals {
  create_table_statements = {
    for s in local.ddl_statements :
    regex("(?i)CREATE TABLE\\s+(?:IF NOT EXISTS\\s+)?(\\S+)", s)[0] => s
    if startswith(upper(s), "CREATE TABLE")
  }
}

resource "aws_redshiftdata_statement" "table" {
  for_each = local.create_table_statements

  workgroup_name = aws_redshiftserverless_workgroup.this.workgroup_name
  database       = aws_redshiftserverless_namespace.this.db_name
  secret_arn     = aws_redshiftserverless_namespace.this.admin_password_secret_arn
  sql            = each.value

  depends_on = [
    aws_redshiftdata_statement.schema
  ]

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_redshiftdata_statement" "copy" {
  for_each = local.tables

  workgroup_name = aws_redshiftserverless_workgroup.this.workgroup_name
  database       = aws_redshiftserverless_namespace.this.db_name
  secret_arn     = aws_redshiftserverless_namespace.this.admin_password_secret_arn
  sql            = "COPY ${each.key} FROM 's3://${module.tables_bucket.s3_bucket_id}/${each.key}.csv' IAM_ROLE default FORMAT AS CSV IGNOREHEADER 1 TIMEFORMAT 'auto' DATEFORMAT 'auto' EMPTYASNULL BLANKSASNULL"

  depends_on = [
    aws_s3_object.tables,
    aws_redshiftdata_statement.table
  ]

  lifecycle {
    ignore_changes = all
  }
}

locals {
  comment_statements = [
    for s in split(";", file("${path.module}/../sql/comments.sql")) : trimspace(s)
    if trimspace(s) != ""
  ]
}

resource "aws_redshiftdata_statement" "comment" {
  for_each = toset(local.comment_statements)

  workgroup_name = aws_redshiftserverless_workgroup.this.workgroup_name
  database       = aws_redshiftserverless_namespace.this.db_name
  secret_arn     = aws_redshiftserverless_namespace.this.admin_password_secret_arn
  sql            = each.value

  depends_on = [
    aws_redshiftdata_statement.copy
  ]

  lifecycle {
    ignore_changes = all
  }
}
