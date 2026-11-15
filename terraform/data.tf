# 프로젝트
locals {
  project = "danbi-airtech"
  domain  = "${local.account_id}.fitcloud.click"
}

# AWS 지역 정보 불러오기
data "aws_region" "current" {}

locals {
  aws_region = data.aws_region.current.region
}

# 현재 Terraform을 실행하는 IAM 객체
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# EKS 클러스터
data "aws_eks_cluster" "this" {
  name = "workshop"
}

# EKS 클러스터 인증 토큰
data "aws_eks_cluster_auth" "this" {
  name = data.aws_eks_cluster.this.name
}
