resource "aws_instance" "processor" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.processor_instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.processor.id]
  iam_instance_profile   = aws_iam_instance_profile.processor.name

  root_block_device {
    volume_size           = var.processor_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true

    tags = merge(
      var.tags,
      {
        Name        = "${var.project_name}-processor-root"
        Environment = var.environment
      }
    )
  }

  user_data = templatefile("${path.module}/user_data_processor.sh", {
    kafka_broker           = aws_instance.ingestor.private_ip
    bucket_sensor_raw      = aws_s3_bucket.sensor_raw.id
    bucket_api_raw         = aws_s3_bucket.api_raw.id
    bucket_actuals         = aws_s3_bucket.merge_actuals.id
    aqicn_token            = var.aqicn_token
    prometheus_retention   = var.prometheus_retention_days
  })

  monitoring = var.enable_monitoring

  depends_on = [aws_instance.ingestor]

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-processor"
      Environment = var.environment
      Role        = "data-processor"
    }
  )

  lifecycle {
    ignore_changes = [user_data]
  }
}

# Elastic IP for Processor
resource "aws_eip" "processor" {
  instance = aws_instance.processor.id
  domain   = "vpc"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-processor-eip"
      Environment = var.environment
    }
  )
}
