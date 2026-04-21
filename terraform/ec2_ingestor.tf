resource "aws_instance" "ingestor" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.ingestor_instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ingestor.id]
  iam_instance_profile   = aws_iam_instance_profile.ingestor.name

  root_block_device {
    volume_size           = var.ingestor_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true

    tags = merge(
      var.tags,
      {
        Name        = "${var.project_name}-ingestor-root"
        Environment = var.environment
      }
    )
  }

  user_data = templatefile("${path.module}/user_data_ingestor.sh", {
    kafka_retention_ms = var.kafka_retention_ms
  })

  monitoring = var.enable_monitoring

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-ingestor"
      Environment = var.environment
      Role        = "kafka-broker"
    }
  )

  lifecycle {
    ignore_changes = [user_data]
  }
}

# Elastic IP for Ingestor
resource "aws_eip" "ingestor" {
  instance = aws_instance.ingestor.id
  domain   = "vpc"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-ingestor-eip"
      Environment = var.environment
    }
  )
}
