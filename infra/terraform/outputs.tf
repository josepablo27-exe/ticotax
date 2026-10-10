# =============================================================================
# TicoTax SaaS — Outputs de Terraform
# Épica TICOTAX-100 | Sprint 2 | Historia TICOTAX-104
#
# Estos outputs son los valores que se inyectan como secretos de Kubernetes
# usando External Secrets Operator (ESO).
# [D] Plan Maestro PARTE 8 k8s/03-secrets.yaml: ExternalSecret lee de SecretsManager
#
# Uso post-apply:
#   terraform output -json > infra/terraform/outputs.json
#   kubectl apply -f k8s/  (lee endpoints desde Secrets Manager automáticamente)
# =============================================================================

# =============================================================================
# VPC
# =============================================================================

output "vpc_id" {
  description = "ID de la VPC principal de TicoTax. Necesario para configurar Security Groups adicionales."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs de las subredes privadas. Usadas por EKS, RDS y ElastiCache."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs de las subredes públicas. Usadas por el ALB / Ingress Controller."
  value       = aws_subnet.public[*].id
}

# =============================================================================
# RDS — PostgreSQL 15
# [D] PARTE 8 k8s/03-secrets.yaml: property "url" → DATABASE_URL
# =============================================================================

output "rds_endpoint" {
  description = "Endpoint completo de RDS PostgreSQL (host:port). Inyectar en DATABASE_URL."
  value       = aws_db_instance.postgres.endpoint
}

output "rds_host" {
  description = "Hostname de RDS PostgreSQL (sin puerto)."
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "Puerto de RDS PostgreSQL. Siempre 5432."
  value       = aws_db_instance.postgres.port
}

output "rds_db_name" {
  description = "Nombre de la base de datos PostgreSQL."
  value       = aws_db_instance.postgres.db_name
}

output "rds_secret_arn" {
  description = "ARN del secret en AWS Secrets Manager con las credenciales de RDS. Usar en ExternalSecret de K8s."
  value       = aws_secretsmanager_secret.rds.arn
}

output "database_url" {
  description = "DATABASE_URL completa para PgBouncer o conexión directa. SENSIBLE — no loguear."
  value       = "postgresql://${var.rds_username}:${var.rds_password}@${aws_db_instance.postgres.endpoint}/${var.rds_db_name}?sslmode=require"
  sensitive   = true
  # Para obtener: terraform output -raw database_url
}

# =============================================================================
# ELASTICACHE — Redis 7
# [D] PARTE 8 k8s ConfigMap: REDIS_URL = "redis://ticotax-redis-svc:6379"
# =============================================================================

output "redis_endpoint" {
  description = "Endpoint de ElastiCache Redis (host). Inyectar en REDIS_URL."
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  description = "Puerto de Redis. Siempre 6379."
  value       = aws_elasticache_cluster.redis.cache_nodes[0].port
}

output "redis_url" {
  description = "REDIS_URL completa para la API y el rate limiter."
  value       = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379"
}

output "redis_secret_arn" {
  description = "ARN del secret en AWS Secrets Manager con la URL de Redis."
  value       = aws_secretsmanager_secret.redis.arn
}

# =============================================================================
# EKS — Kubernetes Cluster
# [D] PARTE 2.1: "Kubernetes (AWS EKS) | 1.29+"
# =============================================================================

output "eks_cluster_name" {
  description = "Nombre del cluster EKS. Usar en: aws eks update-kubeconfig --name <cluster_name>"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint del API server de EKS. Usado por kubectl y Helm."
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_ca_certificate" {
  description = "Certificado CA del cluster EKS (base64). Necesario para kubectl."
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "eks_cluster_version" {
  description = "Versión de Kubernetes activa en el cluster EKS."
  value       = aws_eks_cluster.main.version
}

output "eks_node_role_arn" {
  description = "ARN del IAM Role de los worker nodes. Agregar en aws-auth ConfigMap."
  value       = aws_iam_role.eks_nodes.arn
}

output "kubectl_config_command" {
  description = "Comando para configurar kubectl con el cluster de TicoTax."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.aws_region}"
}

# =============================================================================
# S3 + KMS
# [D] PARTE 5.3: "aws s3 cp - s3://ticotax-backups/$BACKUP_FILE --sse-kms-key-id $KMS_KEY_ID"
# =============================================================================

output "s3_bucket_name" {
  description = "Nombre del bucket S3 para XMLs de facturas y backups. Inyectar en AWS_S3_BUCKET."
  value       = aws_s3_bucket.facturas.bucket
}

output "s3_bucket_arn" {
  description = "ARN del bucket S3."
  value       = aws_s3_bucket.facturas.arn
}

output "kms_key_arn" {
  description = "ARN de la KMS Key maestra. Inyectar en AWS_KMS_KEY_ARN para K8s secret."
  value       = aws_kms_key.main.arn
}

output "kms_key_id" {
  description = "ID corto de la KMS Key. Usar en --sse-kms-key-id al subir backups."
  value       = aws_kms_key.main.key_id
}

# =============================================================================
# SQS
# [D] PARTE 2.2: "AWS SQS" para procesamiento asíncrono de facturas
# =============================================================================

output "sqs_queue_url" {
  description = "URL de la cola SQS principal. Inyectar en AWS_SQS_QUEUE_URL."
  value       = aws_sqs_queue.facturas.url
}

output "sqs_queue_arn" {
  description = "ARN de la cola SQS principal."
  value       = aws_sqs_queue.facturas.arn
}

output "sqs_dlq_url" {
  description = "URL de la Dead Letter Queue. Para monitoreo de mensajes fallidos."
  value       = aws_sqs_queue.facturas_dlq.url
}

# =============================================================================
# SECRETS MANAGER — ARNs para External Secrets Operator
# [D] PARTE 8 k8s/03-secrets.yaml: ExternalSecret con secretStoreRef
# =============================================================================

output "secrets_manager_arns" {
  description = "ARNs de todos los secrets en AWS Secrets Manager. Para configurar External Secrets Operator."
  value = {
    rds     = aws_secretsmanager_secret.rds.arn
    redis   = aws_secretsmanager_secret.redis.arn
    storage = aws_secretsmanager_secret.s3_sqs.arn
  }
}

# =============================================================================
# RESUMEN PARA KUBERNETES
# Imprimir después de terraform apply para guiar el siguiente paso (k8s/)
# =============================================================================

output "next_steps" {
  description = "Pasos a seguir después de terraform apply para conectar K8s con la infraestructura."
  value       = <<-EOT

    ============================================================
    ✅ TICOTAX-104 APLICADO EXITOSAMENTE
    ============================================================

    1. Configurar kubectl:
       ${local.kubectl_cmd}

    2. Verificar nodos del cluster:
       kubectl get nodes

    3. Aplicar manifiestos de Kubernetes:
       kubectl apply -f k8s/

    4. Verificar deployments:
       kubectl get pods -n ticotax-prod

    5. Variables de entorno para K8s Secrets:
       RDS Endpoint:  ${aws_db_instance.postgres.endpoint}
       Redis Endpoint: ${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379
       S3 Bucket:     ${aws_s3_bucket.facturas.bucket}
       SQS Queue:     ${aws_sqs_queue.facturas.url}
       KMS Key ID:    ${aws_kms_key.main.key_id}

    ============================================================
  EOT
}

locals {
  kubectl_cmd = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.aws_region}"
}
