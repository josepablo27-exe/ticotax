# =============================================================================
# TicoTax SaaS — Terraform Providers & Backend
# Épica TICOTAX-100 | Sprint 2 | Historia TICOTAX-104
#
# [D] Plan Maestro PARTE 2.1: "IaC | Terraform | 1.7+ | Toda la infra como
#     código, reproducible"
# [D] Plan Maestro PARTE 2.2: Arquitectura AWS us-east-1
# =============================================================================

terraform {
  # [D] PARTE 2.1: Terraform 1.7+
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend S3 para estado remoto (Factor VI: procesos stateless)
  # INSTRUCCIONES:
  #   1. Crear bucket S3 manualmente ANTES del primer terraform init:
  #      aws s3api create-bucket --bucket ticotax-terraform-state --region us-east-1
  #      aws s3api put-bucket-versioning \
  #        --bucket ticotax-terraform-state \
  #        --versioning-configuration Status=Enabled
  #   2. Crear tabla DynamoDB para state locking:
  #      aws dynamodb create-table \
  #        --table-name ticotax-terraform-lock \
  #        --attribute-definitions AttributeName=LockID,AttributeType=S \
  #        --key-schema AttributeName=LockID,KeyType=HASH \
  #        --billing-mode PAY_PER_REQUEST \
  #        --region us-east-1
  backend "s3" {
    bucket         = "ticotax-terraform-state"
    key            = "ticotax/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "ticotax-terraform-lock"
  }
}

# =============================================================================
# AWS Provider — Region us-east-1
# [D] PARTE 2.2: "Kubernetes Cluster (AWS EKS) — us-east-1"
# =============================================================================

provider "aws" {
  region = var.aws_region

  # Tags globales aplicados a todos los recursos (trazabilidad y FinOps)
  default_tags {
    tags = {
      Project     = "ticotax"
      Environment = var.environment
      ManagedBy   = "terraform"
      CostCenter  = "ticotax-saas"
      Owner       = "ulacit-16-0550"
    }
  }
}
