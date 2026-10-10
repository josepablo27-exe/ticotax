# =============================================================================
# TicoTax SaaS — S3 + KMS + SQS
# Épica TICOTAX-100 | Sprint 2 | Historia TICOTAX-104
#
# [D] Plan Maestro PARTE 2.1: "AWS S3 + Glacier | Object Lock, KMS nativo,
#     lifecycle automático"
# [D] Plan Maestro PARTE 2.2: "AWS S3 + Glacier + KMS" y "AWS SES + SQS"
# [D] Plan Maestro PARTE 5.3: "aws s3 cp - s3://ticotax-backups/$BACKUP_FILE
#     --sse aws:kms --sse-kms-key-id $KMS_KEY_ID"
# [D] Plan Maestro Decisión 6: "debeArchivar = differenceInMonths >= 12"
#     → Implementado como Lifecycle Policy: STANDARD_IA a 365 días, GLACIER a 1460 días
# =============================================================================

# =============================================================================
# KMS — LLAVE DE ENCRIPTACIÓN MAESTRA
# [D] PARTE 5.3: "--sse aws:kms --sse-kms-key-id $KMS_KEY_ID"
# Usada por: S3, EKS secrets, worker node EBS, RDS storage
# =============================================================================

resource "aws_kms_key" "main" {
  description             = "Llave KMS maestra de TicoTax ${var.environment} — S3, EKS, RDS"
  deletion_window_in_days = 30  # 30 días para recuperación antes de eliminación permanente
  enable_key_rotation     = true  # Rotación automática anual (best practice)
  multi_region            = false  # Una sola región para dev

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Dar acceso total a la cuenta de AWS (delegando a IAM)
        Sid    = "EnableRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # EKS puede usar la llave para encriptar secrets
        Sid    = "AllowEKSEncryption"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        # CloudWatch Logs puede usar la llave para encriptar logs
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name    = "${var.project}-${var.environment}-kms-main"
    Purpose = "encryption-master-key"
  }
}

# Alias legible para la KMS key
resource "aws_kms_alias" "main" {
  name          = "alias/${var.project}-${var.environment}-main"
  target_key_id = aws_kms_key.main.key_id
}

# Data source para obtener el account ID actual
data "aws_caller_identity" "current" {}

# =============================================================================
# S3 BUCKET — Almacenamiento de XMLs de facturas
# [D] PARTE 2.1: "AWS S3 + Glacier | Object Lock, KMS nativo, lifecycle automático"
# =============================================================================

resource "random_id" "bucket_suffix" {
  byte_length = 4
  # S3 bucket names son globales → sufijo aleatorio para unicidad
}

resource "aws_s3_bucket" "facturas" {
  bucket = "${var.project}-${var.environment}-facturas-${random_id.bucket_suffix.hex}"

  tags = {
    Name    = "${var.project}-${var.environment}-facturas"
    Purpose = "xml-facturas-hacienda"
  }
}

# =============================================================================
# S3 — Bloquear acceso público (OWASP A01)
# Nunca debe ser un bucket público
# =============================================================================

resource "aws_s3_bucket_public_access_block" "facturas" {
  bucket = aws_s3_bucket.facturas.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# S3 — Encriptación con KMS
# [D] PARTE 5.3: "--sse aws:kms --sse-kms-key-id $KMS_KEY_ID"
# =============================================================================

resource "aws_s3_bucket_server_side_encryption_configuration" "facturas" {
  bucket = aws_s3_bucket.facturas.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true  # Reduce el costo de llamadas KMS hasta un 99%
  }
}

# =============================================================================
# S3 — Versionamiento (para recuperación de XMLs)
# =============================================================================

resource "aws_s3_bucket_versioning" "facturas" {
  bucket = aws_s3_bucket.facturas.id

  versioning_configuration {
    status = "Enabled"
  }
}

# =============================================================================
# S3 — LIFECYCLE POLICY (FinOps)
# [D] Plan Maestro PARTE 2.1: "lifecycle automático"
# [D] Plan Maestro Decisión 6: debeArchivar = differenceInMonths >= 12
#
# NIVELES DE STORAGE:
#   STANDARD     → Acceso frecuente (últimos 12 meses)
#   STANDARD_IA  → Acceso infrecuente (1-4 años). ~60% más barato que STANDARD
#   GLACIER      → Archivo (4+ años). ~80% más barato que STANDARD_IA
#
# IMPORTANTE: Los días se calculan desde la creación del objeto, NO la versión.
# =============================================================================

resource "aws_s3_bucket_lifecycle_configuration" "facturas" {
  bucket = aws_s3_bucket.facturas.id

  # REGLA 1: XMLs de facturas actuales
  rule {
    id     = "facturas-xml-lifecycle"
    status = "Enabled"

    filter {
      prefix = "facturas/"  # Solo aplica a XMLs en la carpeta "facturas/"
    }

    # Mover a STANDARD_IA después de 365 días
    # [D] var.s3_lifecycle_standard_ia_days = 365 (FinOps)
    transition {
      days          = var.s3_lifecycle_standard_ia_days  # 365 días
      storage_class = "STANDARD_IA"
    }

    # Mover a GLACIER después de 1460 días (4 años)
    # [D] var.s3_lifecycle_glacier_days = 1460 (FinOps)
    # [D] Plan Maestro PARTE 2.1: "S3 + Glacier"
    transition {
      days          = var.s3_lifecycle_glacier_days  # 1460 días
      storage_class = "GLACIER"
    }

    # Eliminar versiones antiguas de objetos (no la versión actual)
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365  # Eliminar versiones antiguas después de 1 año
    }
  }

  # REGLA 2: Backups de PostgreSQL (retención diferente a las facturas)
  # [D] PARTE 5.3: "K8s CronJob para backup automático diario"
  rule {
    id     = "backups-postgres-lifecycle"
    status = "Enabled"

    filter {
      prefix = "backups/"  # Solo aplica a dumps de PostgreSQL
    }

    # Backups recientes (0-90 días): STANDARD para recuperación rápida
    # Backups de 90-365 días: STANDARD_IA
    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    # Backups de 1+ año: GLACIER (recuperación de emergencia)
    transition {
      days          = 365
      storage_class = "GLACIER"
    }

    # Eliminar backups después de 5 años (cumplimiento fiscal CR)
    expiration {
      days = 1825  # 5 años en días
    }
  }

  # REGLA 3: Limpiar uploads incompletos (multipart)
  # FinOps: Los multipart uploads incompletos cobran igual que objetos completos
  rule {
    id     = "cleanup-incomplete-multipart"
    status = "Enabled"

    filter {}  # Aplica a todo el bucket

    abort_incomplete_multipart_upload {
      days_after_initiation = 7  # Eliminar uploads incompletos después de 7 días
    }
  }
}

# =============================================================================
# S3 — BUCKET POLICY: Solo EKS puede acceder
# Zero Trust: Solo los pods de EKS con el IAM role correcto pueden acceder
# =============================================================================

resource "aws_s3_bucket_policy" "facturas" {
  bucket = aws_s3_bucket.facturas.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyNonEKSAccess"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.facturas.arn,
          "${aws_s3_bucket.facturas.arn}/*"
        ]
        Condition = {
          StringNotLike = {
            "aws:PrincipalArn" = [
              aws_iam_role.eks_nodes.arn,
              # También permitir acceso desde el role del admin (para debugging)
              "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
            ]
          }
        }
      },
      {
        # Forzar encriptación en tránsito (HTTPS)
        Sid    = "DenyInsecureTransport"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.facturas.arn,
          "${aws_s3_bucket.facturas.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.facturas]
}

# =============================================================================
# SQS — Cola de procesamiento asíncrono de facturas
# [D] Plan Maestro PARTE 2.2: "AWS SES + SQS" para procesamiento asíncrono
# [D] Plan Maestro Grafana: "Profundidad SQS: aws_sqs_approximate_number_of_messages_visible"
# =============================================================================

# Dead Letter Queue — mensajes que fallan repetidamente van aquí para análisis
resource "aws_sqs_queue" "facturas_dlq" {
  name                      = "${var.project}-${var.environment}-facturas-dlq"
  message_retention_seconds = 1209600  # 14 días (máximo de SQS)
  kms_master_key_id         = aws_kms_key.main.arn  # Encriptación en reposo

  tags = {
    Name    = "${var.project}-${var.environment}-facturas-dlq"
    Purpose = "dead-letter-queue-facturas"
  }
}

# Cola principal de procesamiento de facturas
resource "aws_sqs_queue" "facturas" {
  name                       = "${var.project}-${var.environment}-facturas"
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds  # 300s (5 min)
  message_retention_seconds  = var.sqs_message_retention_seconds   # 86400s (24h)
  max_message_size           = 262144  # 256 KB máximo por mensaje
  delay_seconds              = 0       # Sin delay — procesar inmediatamente
  receive_wait_time_seconds  = 20      # Long polling (reduce costos de API calls)
  kms_master_key_id          = aws_kms_key.main.arn  # Encriptación KMS

  # Después de 3 intentos fallidos, mover a DLQ
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.facturas_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name    = "${var.project}-${var.environment}-facturas"
    Purpose = "procesamiento-asincrono-facturas"
  }
}

# =============================================================================
# SQS — POLICY: Solo EKS puede publicar y consumir mensajes
# =============================================================================

resource "aws_sqs_queue_policy" "facturas" {
  queue_url = aws_sqs_queue.facturas.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEKSAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.eks_nodes.arn
        }
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.facturas.arn
      }
    ]
  })
}

# =============================================================================
# AWS SECRETS MANAGER — Nombre del bucket y URL de SQS para K8s
# Para que los pods puedan leer estos valores sin hardcodearlos
# =============================================================================

resource "aws_secretsmanager_secret" "s3_sqs" {
  name        = "ticotax/${var.environment}/storage"
  description = "Configuración de S3 y SQS para los pods de TicoTax"

  recovery_window_in_days = 7

  tags = {
    Name = "${var.project}-${var.environment}-storage-secret"
  }
}

resource "aws_secretsmanager_secret_version" "s3_sqs" {
  secret_id = aws_secretsmanager_secret.s3_sqs.id

  secret_string = jsonencode({
    s3_bucket_name   = aws_s3_bucket.facturas.bucket
    s3_bucket_arn    = aws_s3_bucket.facturas.arn
    s3_region        = var.aws_region
    kms_key_arn      = aws_kms_key.main.arn
    sqs_queue_url    = aws_sqs_queue.facturas.url
    sqs_queue_arn    = aws_sqs_queue.facturas.arn
    sqs_dlq_url      = aws_sqs_queue.facturas_dlq.url
  })
}
