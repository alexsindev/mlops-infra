# IAM Role for Processor EC2 instance
resource "aws_iam_role" "processor" {
  name = "${var.project_name}-processor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-processor-role"
      Environment = var.environment
    }
  )
}

# IAM Policy for S3 access
resource "aws_iam_role_policy" "processor_s3" {
  name = "${var.project_name}-processor-s3-policy"
  role = aws_iam_role.processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.sensor_raw.arn,
          "${aws_s3_bucket.sensor_raw.arn}/*",
          aws_s3_bucket.api_raw.arn,
          "${aws_s3_bucket.api_raw.arn}/*",
          aws_s3_bucket.merge_actuals.arn,
          "${aws_s3_bucket.merge_actuals.arn}/*"
        ]
      }
    ]
  })
}

# IAM Policy for Secrets Manager access (optional)
resource "aws_iam_role_policy" "processor_secrets" {
  name = "${var.project_name}-processor-secrets-policy"
  role = aws_iam_role.processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:mlops/services-*"
      }
    ]
  })
}

# Instance profile for Processor
resource "aws_iam_instance_profile" "processor" {
  name = "${var.project_name}-processor-profile"
  role = aws_iam_role.processor.name

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-processor-profile"
      Environment = var.environment
    }
  )
}

# IAM Role for Ingestor EC2 instance (minimal permissions)
resource "aws_iam_role" "ingestor" {
  name = "${var.project_name}-ingestor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-ingestor-role"
      Environment = var.environment
    }
  )
}

# Instance profile for Ingestor
resource "aws_iam_instance_profile" "ingestor" {
  name = "${var.project_name}-ingestor-profile"
  role = aws_iam_role.ingestor.name

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-ingestor-profile"
      Environment = var.environment
    }
  )
}
