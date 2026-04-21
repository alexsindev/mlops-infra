# Ingestor Security Group
resource "aws_security_group" "ingestor" {
  name        = "${var.project_name}-ingestor-sg"
  description = "Security group for Kafka Ingestor instance"
  vpc_id      = aws_vpc.main.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "SSH access"
  }

  # Kafka
  ingress {
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [aws_security_group.processor.id]
    description     = "Kafka from Processor"
  }

  # Node Exporter
  ingress {
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.processor.id]
    description     = "Node Exporter from Prometheus"
  }

  # Outbound all
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-ingestor-sg"
      Environment = var.environment
    }
  )
}

# Processor Security Group
resource "aws_security_group" "processor" {
  name        = "${var.project_name}-processor-sg"
  description = "Security group for Processor instance"
  vpc_id      = aws_vpc.main.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "SSH access"
  }

  # Grafana
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "Grafana web UI"
  }

  # Prometheus
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "Prometheus web UI"
  }

  # WebSocket Server
  ingress {
    from_port   = 8765
    to_port     = 8765
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "WebSocket Server for dashboard"
  }

  # Node Exporter (self)
  ingress {
    from_port = 9100
    to_port   = 9100
    protocol  = "tcp"
    self      = true
    description = "Node Exporter self-scrape"
  }

  # Outbound all
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-processor-sg"
      Environment = var.environment
    }
  )
}
