resource "kubernetes_namespace_v1" "mcp" {
  metadata {
    name = "mcp"
  }
}

# Amazon Bedrock Knowledge Base Retrieval MCP Server
resource "kubernetes_service_account_v1" "kb_retrieval_mcp" {
  metadata {
    name      = "kb-retrieval-mcp"
    namespace = kubernetes_namespace_v1.mcp.metadata[0].name
  }
}

module "kb_retrieval_mcp_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name = "${local.project}-${kubernetes_service_account_v1.kb_retrieval_mcp.metadata[0].name}"

  policy_name_prefix = "${local.project}_"
  use_name_prefix    = false

  additional_policy_arns = {
    AmazonBedrockFullAccess = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
  }

  associations = {
    kb-retrieval-mcp = {
      cluster_name    = data.aws_eks_cluster.this.name
      namespace       = kubernetes_namespace_v1.mcp.metadata[0].name
      service_account = kubernetes_service_account_v1.kb_retrieval_mcp.metadata[0].name
      tags = {
        app = kubernetes_service_account_v1.kb_retrieval_mcp.metadata[0].name
      }
    }
  }
}

resource "time_sleep" "wait_kb_retrieval_mcp_pod_identity" {
  create_duration = "30s"

  triggers = {
    association = jsonencode(module.kb_retrieval_mcp_pod_identity.associations)
  }

  depends_on = [module.kb_retrieval_mcp_pod_identity]
}

resource "kubernetes_deployment_v1" "kb_retrieval_mcp" {
  metadata {
    name      = "kb-retrieval-mcp"
    namespace = kubernetes_namespace_v1.mcp.metadata[0].name
  }

  spec {
    selector {
      match_labels = {
        app = "kb-retrieval-mcp"
      }
    }

    template {
      metadata {
        labels = {
          app = "kb-retrieval-mcp"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.kb_retrieval_mcp.metadata[0].name
        container {
          name  = "mcp-server"
          image = "public.ecr.aws/docker/library/python:3.15-slim"

          command = [
            "/bin/sh",
            "-c"
          ]
          args = [
            "pip install mcp-proxy==0.13.2 uv==0.13.7 && mcp-proxy --port 8000 --host 0.0.0.0 --pass-environment uvx awslabs.bedrock-kb-retrieval-mcp-server@1.1.2"
          ]

          env {
            name = "AWS_REGION"
            value_from {
              field_ref {
                field_path = "metadata.labels['topology.kubernetes.io/region']"
              }
            }
          }

          port {
            name           = "http"
            container_port = 8000
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "250Mi"
            }
          }

          readiness_probe {
            http_get {
              path = "/status"
              port = "http"
            }
          }
        }
      }
    }
  }

  depends_on = [
    time_sleep.wait_kb_retrieval_mcp_pod_identity
  ]
}

resource "kubernetes_service_v1" "kb_retrieval_mcp" {
  metadata {
    name      = "kb-retrieval-mcp"
    namespace = kubernetes_namespace_v1.mcp.metadata[0].name
  }
  spec {
    selector = {
      app = kubernetes_deployment_v1.kb_retrieval_mcp.spec[0].selector[0].match_labels.app
    }
    port {
      port        = 80
      target_port = kubernetes_deployment_v1.kb_retrieval_mcp.spec[0].template[0].spec[0].container[0].port[0].container_port
    }
  }
}

resource "kubernetes_ingress_v1" "kb_retrieval_mcp" {
  metadata {
    name      = "kb-retrieval-mcp"
    namespace = kubernetes_namespace_v1.mcp.metadata[0].name
  }

  spec {
    rule {
      host = "kb-retrieval-mcp.${local.domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.kb_retrieval_mcp.metadata[0].name
              port {
                number = kubernetes_service_v1.kb_retrieval_mcp.spec[0].port[0].port
              }
            }
          }
        }
      }
    }
  }
}
