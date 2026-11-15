# Librechat
resource "kubernetes_namespace_v1" "librechat" {
  metadata {
    name = "librechat"
  }
}

# 자격 증명
resource "random_bytes" "creds_key" {
  length = 32
}

resource "random_bytes" "creds_iv" {
  length = 16
}

resource "random_bytes" "jwt_secret" {
  length = 32
}

resource "random_bytes" "jwt_refresh_secret" {
  length = 32
}

resource "kubernetes_secret_v1" "librechat_credentials" {
  metadata {
    name      = "librechat-credentials"
    namespace = kubernetes_namespace_v1.librechat.metadata[0].name
  }

  data = {
    CREDS_KEY          = random_bytes.creds_key.hex
    CREDS_IV           = random_bytes.creds_iv.hex
    JWT_SECRET         = random_bytes.jwt_secret.hex
    JWT_REFRESH_SECRET = random_bytes.jwt_refresh_secret.hex
  }
}

# IAM 권한
module "librechat_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.10.0"

  name = "${local.project}-librechat"

  policy_name_prefix = "${local.project}_"
  use_name_prefix    = false

  additional_policy_arns = {
    AmazonBedrockFullAccess = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
  }

  associations = {
    librechat = {
      cluster_name    = data.aws_eks_cluster.this.name
      namespace       = "librechat"
      service_account = "librechat"
      tags = {
        app = "librechat"
      }
    }
  }
}

resource "helm_release" "librechat" {
  name       = "librechat"
  repository = "oci://ghcr.io/librechat-ai/librechat-chart"
  chart      = "librechat"
  version    = "3.0.0"
  namespace  = kubernetes_namespace_v1.librechat.metadata[0].name

  values = [<<-EOT
    global:
      librechat:
        existingSecretName: ${kubernetes_secret_v1.librechat_credentials.metadata[0].name}
    librechat:
      configEnv:
        ALLOW_REGISTRATION: "true"
        ENDPOINTS: bedrock,agents
        BEDROCK_AWS_DEFAULT_REGION: ${local.aws_region}
      configYamlContent: |
        version: 1.3.17
        endpoints:
          bedrock:
            models:
            - global.anthropic.claude-sonnet-5-5
        mcpServers:
          knowledge-base:
            type: streamable-http
            url: http://kb-retrieval-mcp.mcp.svc.cluster.local/mcp
            title: 단비에어텍 사내 문서
            description: 승인원·ECN 통보서·회의록·관리대장·절차서·지침·메일·공지 등 사내 문서를 검색하는 지식 베이스
            timeout: 120000
            initTimeout: 60000
            serverInstructions: |
              KB 는 하나로 고정: QueryKnowledgeBases(knowledge_base_id="${aws_bedrockagent_knowledge_base.docs.id}", number_of_results=5).
              ListKnowledgeBases, AgenticQueryKnowledgeBases 는 부르지 않는다.
              이 KB 에는 사내 문서(승인원, ECN 통보서, 회의록, 승인원·공장 관리대장, 품질·영업·구매 절차서와 지침, 사내외 메일, 공장 공지, 안전 수칙, 당직표, 도장 표준)가 있다.
          redshift:
            type: streamable-http
            url: http://redshift-mcp.mcp.svc.cluster.local/mcp
            title: 단비에어텍 업무 시스템 데이터
            description: ERP·MES·PLM의 재고·발주·입고·생산계획·수주·로트·설계변경 등 건별 사실과 수치를 SQL로 조회하는 읽기 전용 데이터 웨어하우스
            timeout: 120000
            initTimeout: 60000
            serverInstructions: |
              대상은 하나로 고정: cluster_identifier="${aws_redshiftserverless_workgroup.this.workgroup_name}", cluster_type="serverless", database "dev".
              list_clusters, list_databases, review_cluster 는 부르지 않는다.
              스키마: erp_a, erp_b, mes, plm.
              순서: list_tables(dev, <스키마>) → list_columns(dev, <스키마>, <테이블>) → execute_query.
              SQL 은 <스키마>. 접두어, SELECT 한 문장. 결과가 많으면 집계나 LIMIT 을 쓴다.
        mcpSettings:
          allowedDomains:
          - http://kb-retrieval-mcp.mcp.svc.cluster.local
          - http://redshift-mcp.mcp.svc.cluster.local
    serviceAccount:
      name: librechat
    ingress:
      hosts:
      - host: chat.${local.domain}
        paths:
        - path: /
          pathType: Prefix
    meilisearch:
      enabled: false
  EOT
  ]

  depends_on = [
    module.librechat_pod_identity
  ]
}
