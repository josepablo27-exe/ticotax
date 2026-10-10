# =============================================================================
# TicoTax SaaS — Variables de Entrada
# Épica TICOTAX-100 | Sprint 2 | Historia TICOTAX-104
#
# Factor III (12-Factor App): Configuración por variables de entorno.
# Los valores sensibles se proveen via terraform.tfvars (en .gitignore)
# o via AWS Systems Manager Parameter Store en CI/CD.
#
# [D] Plan Maestro PARTE 4.3: "terraform.tfvars" en .gitignore
# =============================================================================

# =============================================================================
# GLOBALES
# =============================================================================

variable "aws_region" {
  description = "Región AWS donde se despliega toda la infraestructura de TicoTax."
  type        = string
  default     = "us-east-1"
  # [D] PARTE 2.2: "Kubernetes Cluster (AWS EKS) — us-east-1"
}

variable "environment" {
  description = "Nombre del entorno. Controla el tier de instancias y las políticas de retención."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "El entorno debe ser 'dev', 'staging' o 'prod'."
  }
}

variable "project" {
  description = "Nombre del proyecto. Se usa como prefijo en todos los recursos para evitar colisiones."
  type        = string
  default     = "ticotax"
}

# =============================================================================
# VPC Y REDES
# [D] PARTE 2.2: Arquitectura con subredes públicas y privadas
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block de la VPC principal de TicoTax."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Zonas de disponibilidad en us-east-1. Mínimo 2 para alta disponibilidad de RDS Multi-AZ."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs para subredes públicas (ALB / Ingress). Sin acceso directo a RDS o Redis."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs para subredes privadas (EKS worker nodes, RDS, ElastiCache). Sin acceso desde internet."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

# =============================================================================
# RDS — POSTGRESQL 15
# [D] PARTE 5.1: "PostgreSQL 15" con extensiones pgcrypto, pg_trgm
# [D] PARTE 2.1 FinOps: "db.t3.micro" para tier desarrollo
# =============================================================================

variable "rds_instance_class" {
  description = "Clase de instancia RDS. FinOps: db.t3.micro en dev, db.t3.medium en prod."
  type        = string
  default     = "db.t3.micro"
  # [D] Plan Maestro FinOps: tier desarrollo db.t3.micro
}

variable "rds_allocated_storage" {
  description = "Almacenamiento inicial de RDS en GB."
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Límite máximo para autoscaling de almacenamiento RDS (GB)."
  type        = number
  default     = 100
}

variable "rds_db_name" {
  description = "Nombre de la base de datos PostgreSQL."
  type        = string
  default     = "ticotax"
}

variable "rds_username" {
  description = "Usuario maestro de RDS. NO usar 'postgres' o 'admin' (reservados por AWS)."
  type        = string
  default     = "ticotax_admin"
  sensitive   = true
}

variable "rds_password" {
  description = "Contraseña maestra de RDS. Mínimo 16 caracteres. Proveer via terraform.tfvars o AWS SSM."
  type        = string
  sensitive   = true
  # Sin default — OBLIGATORIO proveer en terraform.tfvars o variable de entorno TF_VAR_rds_password
}

variable "rds_multi_az" {
  description = "Activar Multi-AZ para alta disponibilidad. True en prod, false en dev (costo)."
  type        = bool
  default     = false
  # FinOps: Multi-AZ duplica el costo, solo activar en prod
}

variable "rds_backup_retention_days" {
  description = "Días de retención de backups automáticos de RDS."
  type        = number
  default     = 7
}

# =============================================================================
# ELASTICACHE — REDIS 7
# [D] PARTE 2.2: "Redis 7 | r7g.large" (r7g.large en prod, cache.t3.micro en dev)
# =============================================================================

variable "redis_node_type" {
  description = "Tipo de nodo ElastiCache. FinOps: cache.t3.micro en dev, cache.r7g.large en prod."
  type        = string
  default     = "cache.t3.micro"
  # [D] Plan Maestro PARTE 2.2: "Redis 7 | r7g.large" (para producción)
}

variable "redis_num_nodes" {
  description = "Número de nodos en el cluster Redis. 1 en dev, 2+ en prod."
  type        = number
  default     = 1
}

variable "redis_engine_version" {
  description = "Versión del engine Redis."
  type        = string
  default     = "7.1"
  # [D] PARTE 2.1: "Redis 7"
}

# =============================================================================
# EKS — KUBERNETES
# [D] PARTE 2.1: "Kubernetes (AWS EKS) | 1.29+"
# =============================================================================

variable "eks_cluster_version" {
  description = "Versión de Kubernetes en EKS."
  type        = string
  default     = "1.29"
  # [D] PARTE 2.1: "1.29+"
}

variable "eks_node_instance_types" {
  description = "Tipos de instancia para los worker nodes del EKS."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_node_desired_size" {
  description = "Número deseado de worker nodes."
  type        = number
  default     = 2
}

variable "eks_node_min_size" {
  description = "Mínimo de worker nodes (para HPA y ahorro de costos)."
  type        = number
  default     = 1
}

variable "eks_node_max_size" {
  description = "Máximo de worker nodes (para autoscaling durante picos)."
  type        = number
  default     = 5
}

# =============================================================================
# S3 Y KMS
# [D] PARTE 5.3: "aws s3 cp - s3://ticotax-backups/$BACKUP_FILE --sse aws:kms"
# [D] PARTE 2.1: "AWS S3 + Glacier | Object Lock, KMS nativo, lifecycle automático"
# [D] PARTE 8 Decisión 6: "debeArchivar = differenceInMonths(today, factura.createdAt) >= 12"
# =============================================================================

variable "s3_lifecycle_standard_ia_days" {
  description = "Días hasta mover objetos a STANDARD_IA (costo menor, acceso ocasional)."
  type        = number
  default     = 365
  # FinOps: 1 año → STANDARD_IA
}

variable "s3_lifecycle_glacier_days" {
  description = "Días hasta mover objetos a GLACIER (costo mínimo, acceso raro)."
  type        = number
  default     = 1460
  # FinOps: 4 años → GLACIER | [D] PARTE 2.1: "S3 + Glacier"
}

# =============================================================================
# SQS
# [D] PARTE 2.2: "AWS SES + SQS" para procesamiento asíncrono
# =============================================================================

variable "sqs_message_retention_seconds" {
  description = "Tiempo máximo de retención de mensajes en SQS (segundos). Máximo: 14 días."
  type        = number
  default     = 86400
  # 86400 = 24 horas. Si falla el procesamiento, el mensaje se encola hasta 24h.
}

variable "sqs_visibility_timeout_seconds" {
  description = "Tiempo de invisibilidad de mensajes mientras se procesan."
  type        = number
  default     = 300
  # 5 minutos: tiempo máximo que puede tardar el parser en procesar un XML grande
}
