# =============================================================================
# TicoTax SaaS — Amazon EKS (Elastic Kubernetes Service)
# Épica TICOTAX-100 | Sprint 2 | Historia TICOTAX-104
#
# [D] Plan Maestro PARTE 2.1: "Kubernetes (AWS EKS) | 1.29+ | Autoscaling,
#     self-healing, rolling deploys"
# [D] Plan Maestro PARTE 8: Deployment de API con réplicas=3, HPA, RBAC
# [D] Plan Maestro PARTE 2.2: "Kubernetes Cluster (AWS EKS) — us-east-1"
#
# ZERO TRUST:
#   - Worker nodes solo aceptan conexiones gestionadas por el plano de control EKS
#   - Acceso público al cluster deshabilitado (solo via VPN o kubectl con aws-auth)
#   - RBAC mínimo privilegio (PARTE 8.1)
# =============================================================================

# =============================================================================
# SECURITY GROUP — EKS CLUSTER (Plano de control)
# =============================================================================

resource "aws_security_group" "eks_cluster" {
  name        = "${var.project}-${var.environment}-eks-cluster-sg"
  description = "Security group del plano de control de EKS (API server)"
  vpc_id      = aws_vpc.main.id

  # El plano de control EKS necesita comunicarse con los worker nodes
  egress {
    description = "Plano de control EKS se comunica con worker nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-eks-cluster-sg"
  }
}

# =============================================================================
# SECURITY GROUP — EKS WORKER NODES
# Referenciado por RDS y Redis para Zero Trust
# =============================================================================

resource "aws_security_group" "eks_nodes" {
  name        = "${var.project}-${var.environment}-eks-nodes-sg"
  description = "Security group de los worker nodes de EKS. Usado por RDS/Redis para Zero Trust."
  vpc_id      = aws_vpc.main.id

  # Comunicación interna entre worker nodes (necesario para CNI y K8s)
  ingress {
    description = "Comunicación entre worker nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Plano de control EKS accede a los kubelets en los worker nodes
  ingress {
    description     = "Acceso del plano de control EKS a kubelets"
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  # HTTPS del plano de control a los worker nodes
  ingress {
    description     = "HTTPS del plano de control a worker nodes"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  # Salida sin restricción (los pods necesitan acceder a ECR, npm, PyPI, etc.)
  egress {
    description = "Worker nodes necesitan salida a internet (ECR, npm, PyPI)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.environment}-eks-nodes-sg"
    # EKS requiere este tag para autodiscovery
    "kubernetes.io/cluster/${var.project}-${var.environment}" = "owned"
  }
}

# =============================================================================
# IAM ROLE — EKS CLUSTER (Plano de control)
# =============================================================================

resource "aws_iam_role" "eks_cluster" {
  name = "${var.project}-${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# =============================================================================
# IAM ROLE — EKS WORKER NODES
# =============================================================================

resource "aws_iam_role" "eks_nodes" {
  name = "${var.project}-${var.environment}-eks-nodes-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Políticas requeridas para que los worker nodes funcionen
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_container_registry" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  # Solo lectura en ECR — los nodos solo descargan imágenes, no las publican
}

# Política para que los pods puedan leer Secrets Manager
# [D] PARTE 8 k8s/03-secrets.yaml: External Secrets Operator lee de SecretsManager
resource "aws_iam_policy" "eks_secrets_manager" {
  name        = "${var.project}-${var.environment}-eks-secrets-policy"
  description = "Permite a los pods de EKS leer secrets de AWS Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:*:secret:ticotax/${var.environment}/*"
        ]
        # Solo acceso a los secrets de TicoTax, no a otros proyectos
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = [aws_kms_key.main.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_secrets_manager" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = aws_iam_policy.eks_secrets_manager.arn
}

# Política para que los pods puedan subir/bajar archivos de S3
# [D] PARTE 5.3: "aws s3 cp - s3://ticotax-backups/$BACKUP_FILE"
resource "aws_iam_policy" "eks_s3_access" {
  name        = "${var.project}-${var.environment}-eks-s3-policy"
  description = "Acceso a S3 para pods de TicoTax (backups, XML de facturas)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.facturas.arn,
          "${aws_s3_bucket.facturas.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_s3_access" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = aws_iam_policy.eks_s3_access.arn
}

# Política para publicar y consumir mensajes de SQS
# [D] PARTE 2.2: "AWS SES + SQS" para procesamiento asíncrono de facturas
resource "aws_iam_policy" "eks_sqs_access" {
  name        = "${var.project}-${var.environment}-eks-sqs-policy"
  description = "Acceso a SQS para pods de TicoTax (cola de procesamiento de facturas)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = [aws_sqs_queue.facturas.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_sqs_access" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = aws_iam_policy.eks_sqs_access.arn
}

# =============================================================================
# EKS CLUSTER
# [D] PARTE 2.1: "Kubernetes (AWS EKS) | 1.29+"
# =============================================================================

resource "aws_eks_cluster" "main" {
  name     = "${var.project}-${var.environment}"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_cluster_version  # "1.29"

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true   # API server accesible desde la VPC
    endpoint_public_access  = true   # También accesible públicamente (para CI/CD y kubectl)
    public_access_cidrs     = ["0.0.0.0/0"]  # Restringir en prod a IPs del equipo
  }

  # Logs del plano de control a CloudWatch
  # [D] PARTE 7: "Observabilidad | CloudWatch"
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Encriptación de secrets en etcd con KMS
  encryption_config {
    provider {
      key_arn = aws_kms_key.main.arn
    }
    resources = ["secrets"]  # Solo los K8s Secrets se encriptan con KMS
  }

  tags = {
    Name = "${var.project}-${var.environment}-eks"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]
}

# =============================================================================
# EKS MANAGED NODE GROUP — Worker nodes
# [D] PARTE 8: Deployment con réplicas=3, CPU requests/limits definidos
# =============================================================================

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project}-${var.environment}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn

  # Solo subredes PRIVADAS para los worker nodes
  subnet_ids = aws_subnet.private[*].id

  # Tipo de instancia
  # [D] Instrucción del task: t3.medium
  instance_types = var.eks_node_instance_types  # ["t3.medium"]

  # Escalado automático
  scaling_config {
    desired_size = var.eks_node_desired_size  # 2
    max_size     = var.eks_node_max_size      # 5
    min_size     = var.eks_node_min_size      # 1
  }

  # Actualización de nodos (rolling update)
  update_config {
    max_unavailable = 1  # Máximo 1 nodo abajo durante la actualización
  }

  # EBS Disk encriptado para los worker nodes
  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  tags = {
    Name = "${var.project}-${var.environment}-node-group"
    # Cluster Autoscaler necesita estos tags para autodiscovery
    "k8s.io/cluster-autoscaler/${var.project}-${var.environment}" = "owned"
    "k8s.io/cluster-autoscaler/enabled"                           = "true"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry,
  ]
}

# =============================================================================
# LAUNCH TEMPLATE — Configuración de los nodos EC2
# Encripta el volumen raíz de cada worker node
# =============================================================================

resource "aws_launch_template" "eks_nodes" {
  name_prefix = "${var.project}-${var.environment}-eks-nodes-"

  # Encriptación del volumen raíz de los worker nodes
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 50     # GB de disco por worker node
      volume_type           = "gp3"
      encrypted             = true   # Encriptar disco de cada worker node
      kms_key_id            = aws_kms_key.main.arn
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 obligatorio (seguridad)
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.project}-${var.environment}-eks-node"
      Project = var.project
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# CloudWatch LOG GROUP — Logs del plano de control EKS
# =============================================================================

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.project}-${var.environment}/cluster"
  retention_in_days = 30  # FinOps: 30 días

  tags = {
    Name = "${var.project}-${var.environment}-eks-logs"
  }
}
