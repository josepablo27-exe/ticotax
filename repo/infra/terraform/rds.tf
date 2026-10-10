# =============================================================================
# TicoTax SaaS — RDS PostgreSQL 15
# Épica TICOTAX-100 | Sprint 2 | Historia TICOTAX-104
#
# [D] Plan Maestro PARTE 5.1: PostgreSQL 15 con extensiones
#     pgcrypto, pg_trgm, uuid-ossp, unaccent
# [D] Plan Maestro PARTE 2.2: "AWS RDS | PostgreSQL | Multi-AZ"
# [D] Plan Maestro PARTE 5.3: Backups automáticos diarios a S3
#
# ZERO TRUST: Solo el Security Group de EKS puede acceder al puerto 5432.
# Ninguna IP pública, ningún usuario humano directo.
# =============================================================================

# =============================================================================
# SECURITY GROUP — RDS PostgreSQL
# Zero Trust: INGRESS solo desde el SG de EKS (worker nodes)
# =============================================================================

resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.environment}-rds-sg"
  description = "Zero Trust: Solo EKS worker nodes pueden conectarse a RDS PostgreSQL en :5432"
  vpc_id      = aws_vpc.main.id

  # INGRESS: SOLO desde el SG de EKS. Ninguna otra fuente.
  ingress {
    description     = "PostgreSQL desde EKS worker nodes (Zero Trust)"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
    # SIN cidr_blocks = "0.0.0.0/0" — nunca acceso público
  }

  # EGRESS: Sin salida de red desde RDS (no necesita conectarse a ningún servicio)
  egress {
    description = "Sin egress desde RDS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    # AWS requiere al menos un egress rule. Los metadatos de RDS usan egress.
  }

  tags = {
    Name = "${var.project}-${var.environment}-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# SUBNET GROUP — RDS en subredes privadas únicamente
# RDS nunca debe estar en subredes públicas
# =============================================================================

resource "aws_db_subnet_group" "main" {
  name        = "${var.project}-${var.environment}-rds-subnet-group"
  description = "Subredes privadas para RDS PostgreSQL de TicoTax"
  subnet_ids  = aws_subnet.private[*].id

  tags = {
    Name = "${var.project}-${var.environment}-rds-subnet-group"
  }
}

# =============================================================================
# PARAMETER GROUP — PostgreSQL 15 con extensiones requeridas
# [D] PARTE 5.1: "CREATE EXTENSION pgcrypto; CREATE EXTENSION pg_trgm;"
# Las extensiones se habilitan en init.sql al primer startup, pero el
# parameter group debe permitirlas (shared_preload_libraries).
# =============================================================================

resource "aws_db_parameter_group" "postgres15" {
  name        = "${var.project}-${var.environment}-postgres15"
  family      = "postgres15"
  description = "Parameter group de TicoTax PostgreSQL 15 con pg_trgm habilitado"

  # pg_trgm requiere estar en shared_preload_libraries para índices GIN
  # [D] PARTE 5.1: "CREATE INDEX USING GIN (unaccent(emisor_nombre) gin_trgm_ops)"
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements,pg_trgm"
    # pg_stat_statements: monitoreo de queries lentas en producción
    # pg_trgm: búsqueda full-text por trigrams (emisor_nombre)
  }

  # Timezone de Costa Rica para consistencia con el código
  # [D] PARTE 3.2: "CR_TIMEZONE: America/Costa_Rica"
  parameter {
    name  = "timezone"
    value = "America/Costa_Rica"
  }

  # Logging de queries lentas (> 1000ms) para observabilidad
  # [D] PARTE 7: "Observabilidad | Pino + CloudWatch + Sentry"
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"  # Loguear queries que tarden más de 1 segundo
  }

  parameter {
    name  = "log_connections"
    value = "1"  # Auditoría: loguear cada conexión nueva
  }

  parameter {
    name  = "log_disconnections"
    value = "1"  # Auditoría: loguear cada desconexión
  }

  tags = {
    Name = "${var.project}-${var.environment}-postgres15-params"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# INSTANCIA RDS — PostgreSQL 15
# [D] PARTE 5.1: "PostgreSQL 15 con extensiones pgcrypto, pg_trgm, uuid-ossp"
# FinOps: db.t3.micro en dev (Tier Desarrollo según Plan Maestro)
# =============================================================================

resource "aws_db_instance" "postgres" {
  # Identificador único en AWS
  identifier = "${var.project}-${var.environment}-postgres"

  # Motor de base de datos
  # [D] PARTE 5.1: "PostgreSQL 15"
  engine               = "postgres"
  engine_version       = "15.6"
  instance_class       = var.rds_instance_class  # db.t3.micro en dev

  # Base de datos inicial
  db_name  = var.rds_db_name   # "ticotax"
  username = var.rds_username   # "ticotax_admin"
  password = var.rds_password   # Proveer via terraform.tfvars (NO commitear)

  # Almacenamiento con autoscaling
  allocated_storage     = var.rds_allocated_storage      # 20 GB inicial
  max_allocated_storage = var.rds_max_allocated_storage  # Hasta 100 GB automático
  storage_type          = "gp3"  # gp3: más barato y mejor performance que gp2
  storage_encrypted     = true   # Encriptación en reposo SIEMPRE habilitada

  # Red y seguridad
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false  # NUNCA pública — Zero Trust
  multi_az               = var.rds_multi_az  # false en dev, true en prod

  # Parámetros
  parameter_group_name = aws_db_parameter_group.postgres15.name

  # Backups automáticos
  # [D] PARTE 5.3: "K8s CronJob para backup automático diario"
  backup_retention_period = var.rds_backup_retention_days  # 7 días
  backup_window           = "04:00-05:00"    # 4 AM UTC = 10 PM CR (poca carga)
  maintenance_window      = "sun:06:00-sun:07:00"  # Domingo 6 AM UTC

  # Performance Insights para debugging de queries
  performance_insights_enabled          = true
  performance_insights_retention_period = 7  # 7 días free tier

  # Monitoreo mejorado (métricas del OS cada 60s)
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Logs a CloudWatch
  # [D] PARTE 7: Observabilidad con CloudWatch
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Protección contra borrado accidental
  deletion_protection = false  # Cambiar a true en prod

  # Actualización automática de versiones menores (parches de seguridad)
  auto_minor_version_upgrade = true
  apply_immediately          = false  # Solo aplica cambios en el próximo maintenance window

  tags = {
    Name        = "${var.project}-${var.environment}-postgres"
    Engine      = "postgresql-15"
    FinOpsClass = var.environment == "prod" ? "db.t3.medium" : "db.t3.micro"
  }
}

# =============================================================================
# IAM ROLE — Para Enhanced Monitoring de RDS
# =============================================================================

resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project}-${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# =============================================================================
# AWS SECRETS MANAGER — Almacenar credenciales de RDS de forma segura
# [D] PARTE 4.3: "Secrets Management — Zero secrets en código"
# [D] PARTE 8 (k8s/03-secrets.yaml): External Secrets Operator lee de SecretsManager
# =============================================================================

resource "aws_secretsmanager_secret" "rds" {
  name        = "ticotax/${var.environment}/database"
  description = "Credenciales de conexión a RDS PostgreSQL para TicoTax"

  # Esperar 7 días antes de eliminar el secret (recuperación de emergencia)
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project}-${var.environment}-rds-secret"
  }
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id

  secret_string = jsonencode({
    # [D] PARTE 8 k8s/03-secrets.yaml: property "url" del secret
    url      = "postgresql://${var.rds_username}:${var.rds_password}@${aws_db_instance.postgres.endpoint}/${var.rds_db_name}?sslmode=require"
    host     = aws_db_instance.postgres.address
    port     = aws_db_instance.postgres.port
    dbname   = var.rds_db_name
    username = var.rds_username
    password = var.rds_password
  })

  lifecycle {
    ignore_changes = [secret_string]
    # Ignorar cambios futuros al secret_string para no sobreescribir rotaciones manuales
  }
}
