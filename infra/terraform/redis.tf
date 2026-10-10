# =============================================================================
# TicoTax SaaS — ElastiCache Redis 7
# Épica TICOTAX-100 | Sprint 2 | Historia TICOTAX-104
#
# [D] Plan Maestro PARTE 2.2: "Redis 7 | r7g.large" (prod), cache.t3.micro (dev)
# [D] Plan Maestro PARTE 2.2: Arquitectura — Redis en subred privada
# [D] Plan Maestro k8s ConfigMap: REDIS_URL = "redis://ticotax-redis-svc:6379"
#
# Uso en TicoTax:
#   - Caché de tipo de cambio BCCR (Decision 8: circuit breaker)
#   - Rate limiting por IP (Factor IV: backing service)
#   - Invalidación de caché de proyecciones fiscales
# =============================================================================

# =============================================================================
# SECURITY GROUP — Redis ElastiCache
# Zero Trust: INGRESS solo desde el SG de EKS. Puerto 6379 cerrado al mundo.
# =============================================================================

resource "aws_security_group" "redis" {
  name        = "${var.project}-${var.environment}-redis-sg"
  description = "Zero Trust: Solo EKS worker nodes pueden conectarse a Redis en :6379"
  vpc_id      = aws_vpc.main.id

  # INGRESS: SOLO desde EKS worker nodes — Zero Trust
  ingress {
    description     = "Redis desde EKS worker nodes únicamente (Zero Trust)"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
    # SIN cidr_blocks — ninguna IP directa puede conectarse
  }

  # Sin egress desde Redis
  egress {
    description = "Sin egress necesario desde Redis"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-redis-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# SUBNET GROUP — Redis en subredes privadas únicamente
# =============================================================================

resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.project}-${var.environment}-redis-subnet-group"
  description = "Subredes privadas para ElastiCache Redis de TicoTax"
  subnet_ids  = aws_subnet.private[*].id

  tags = {
    Name = "${var.project}-${var.environment}-redis-subnet-group"
  }
}

# =============================================================================
# PARAMETER GROUP — Redis 7 con configuraciones de producción
# =============================================================================

resource "aws_elasticache_parameter_group" "redis7" {
  name        = "${var.project}-${var.environment}-redis7"
  family      = "redis7"
  description = "Parameter group Redis 7 para TicoTax"

  # Deshabilitar comandos peligrosos (FLUSHALL puede borrar todo el caché)
  # [D] PARTE 4: Seguridad OWASP
  parameter {
    name  = "rename-commands"
    value = "FLUSHDB=\"\" FLUSHALL=\"\" KEYS=\"\" CONFIG=\"\""
    # Renombrar a string vacío deshabilita el comando completamente
  }

  # Política de eviction: LRU (Least Recently Used) — elimina lo menos usado
  # cuando el caché está lleno. Ideal para caché de BCCR y proyecciones.
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  tags = {
    Name = "${var.project}-${var.environment}-redis7-params"
  }
}

# =============================================================================
# CLUSTER REDIS — ElastiCache
# [D] PARTE 2.2: "Redis 7" para caché y pub/sub
# FinOps: cache.t3.micro en dev, cache.r7g.large en prod
# =============================================================================

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.project}-${var.environment}-redis"
  engine               = "redis"
  engine_version       = var.redis_engine_version  # "7.1"
  node_type            = var.redis_node_type        # cache.t3.micro en dev
  num_cache_nodes      = var.redis_num_nodes        # 1 en dev
  parameter_group_name = aws_elasticache_parameter_group.redis7.name
  port                 = 6379

  # Red y seguridad
  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  # Encriptación en tránsito (TLS) y en reposo
  # at_rest_encryption_enabled = true
  # transit_encryption_enabled aplica en replication group (prod), no en cluster simple (dev)

  # Ventana de mantenimiento (off-peak CR)
  maintenance_window       = "sun:07:00-sun:08:00"  # Domingo 7 AM UTC = 1 AM CR

  # Snapshots automáticos (backups de Redis)
  snapshot_retention_limit = 3   # 3 días de snapshots
  snapshot_window          = "05:00-06:00"  # 5 AM UTC = 11 PM CR

  # Logs a CloudWatch
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"  # Loguear comandos lentos (> 10ms)
  }

  tags = {
    Name        = "${var.project}-${var.environment}-redis"
    Engine      = "redis-7"
    FinOpsClass = var.environment == "prod" ? "cache.r7g.large" : "cache.t3.micro"
  }
}

# =============================================================================
# CLOUDWATCH LOG GROUP — Redis Slow Log
# [D] PARTE 7: "Observabilidad | CloudWatch"
# =============================================================================

resource "aws_cloudwatch_log_group" "redis_slow" {
  name              = "/aws/elasticache/${var.project}-${var.environment}/slow-log"
  retention_in_days = 7  # FinOps: 7 días de logs de Redis

  tags = {
    Name = "${var.project}-${var.environment}-redis-slow-log"
  }
}

# =============================================================================
# AWS SECRETS MANAGER — URL de Redis para External Secrets Operator
# [D] PARTE 8 k8s ConfigMap: REDIS_URL = "redis://ticotax-redis-svc:6379"
# =============================================================================

resource "aws_secretsmanager_secret" "redis" {
  name        = "ticotax/${var.environment}/redis"
  description = "URL de conexión a ElastiCache Redis para TicoTax"

  recovery_window_in_days = 7

  tags = {
    Name = "${var.project}-${var.environment}-redis-secret"
  }
}

resource "aws_secretsmanager_secret_version" "redis" {
  secret_id = aws_secretsmanager_secret.redis.id

  secret_string = jsonencode({
    url  = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379"
    host = aws_elasticache_cluster.redis.cache_nodes[0].address
    port = 6379
  })
}
