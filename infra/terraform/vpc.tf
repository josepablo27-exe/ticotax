# =============================================================================
# TicoTax SaaS — VPC y Redes
# Épica TICOTAX-100 | Sprint 2 | Historia TICOTAX-104
#
# [D] Plan Maestro PARTE 2.2: Arquitectura con subredes públicas (ALB/Ingress)
#     y privadas (EKS worker nodes, RDS, ElastiCache). Internet nunca accede
#     directamente a los servicios internos.
#
# Zero Trust: los grupos de seguridad específicos de cada servicio están en
# sus archivos respectivos (rds.tf, redis.tf, eks.tf). Aquí solo la red.
# =============================================================================

# =============================================================================
# VPC PRINCIPAL
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true  # Necesario para EKS y RDS endpoints
  enable_dns_support   = true

  tags = {
    Name = "${var.project}-${var.environment}-vpc"
    # EKS requiere este tag para autodiscovery del balanceador
    "kubernetes.io/cluster/${var.project}-${var.environment}" = "shared"
  }
}

# =============================================================================
# SUBREDES PÚBLICAS — ALB, NAT Gateway, Ingress Controller
# Sin acceso directo a BD o Redis. Solo balanceadores.
# =============================================================================

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true  # Las instancias en subredes públicas reciben IP pública

  tags = {
    Name = "${var.project}-${var.environment}-public-${var.availability_zones[count.index]}"
    Tier = "public"
    # EKS ALB Ingress Controller autodiscovery
    "kubernetes.io/role/elb"                                         = "1"
    "kubernetes.io/cluster/${var.project}-${var.environment}"        = "shared"
  }
}

# =============================================================================
# SUBREDES PRIVADAS — EKS worker nodes, RDS, ElastiCache Redis
# Sin acceso directo desde Internet. Salen via NAT Gateway.
# =============================================================================

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false  # NUNCA IP pública en subredes privadas

  tags = {
    Name = "${var.project}-${var.environment}-private-${var.availability_zones[count.index]}"
    Tier = "private"
    # EKS Internal Load Balancer autodiscovery (para servicios internos)
    "kubernetes.io/role/internal-elb"                                = "1"
    "kubernetes.io/cluster/${var.project}-${var.environment}"        = "shared"
  }
}

# =============================================================================
# INTERNET GATEWAY — Salida a internet para subredes públicas
# =============================================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-${var.environment}-igw"
  }
}

# =============================================================================
# ELASTIC IPs para NAT Gateways (una por AZ para alta disponibilidad)
# FinOps: En dev, se puede usar 1 solo NAT Gateway para reducir costo.
# En prod, usar una por AZ para eliminar el SPOF.
# =============================================================================

resource "aws_eip" "nat" {
  count  = length(var.public_subnet_cidrs)
  domain = "vpc"

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.project}-${var.environment}-nat-eip-${count.index + 1}"
  }
}

# =============================================================================
# NAT GATEWAYS — Permiten a subredes privadas acceder a internet
# (para descargar imágenes Docker, actualizar dependencias, etc.)
# Sin NAT Gateway, los pods en subredes privadas no pueden acceder a ECR o npm.
# =============================================================================

resource "aws_nat_gateway" "main" {
  count = length(var.public_subnet_cidrs)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id  # NAT Gateway SIEMPRE en subred pública

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.project}-${var.environment}-nat-${var.availability_zones[count.index]}"
  }
}

# =============================================================================
# TABLAS DE RUTAS — Públicas
# Tráfico a internet → Internet Gateway
# =============================================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project}-${var.environment}-rt-public"
  }
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# =============================================================================
# TABLAS DE RUTAS — Privadas
# Tráfico a internet → NAT Gateway de la misma AZ (mayor resiliencia)
# =============================================================================

resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${var.project}-${var.environment}-rt-private-${var.availability_zones[count.index]}"
  }
}

resource "aws_route_table_association" "private" {
  count = length(var.private_subnet_cidrs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# =============================================================================
# VPC FLOW LOGS — Auditoría de tráfico de red (OWASP A09: Logging)
# Cada paquete que entra/sale de la VPC queda registrado en CloudWatch.
# =============================================================================

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/ticotax-${var.environment}-flow-logs"
  retention_in_days = 30  # FinOps: 30 días de logs de red

  tags = {
    Name = "${var.project}-${var.environment}-vpc-flow-logs"
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${var.project}-${var.environment}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "${var.project}-${var.environment}-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"  # Captura ACCEPT y REJECT
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn

  tags = {
    Name = "${var.project}-${var.environment}-flow-log"
  }
}
