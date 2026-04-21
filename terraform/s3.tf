resource "aws_s3_bucket" "sensor_raw" {
  bucket = "${var.bucket_prefix}-sensor-raw"

  tags = merge(
    var.tags,
    {
      Name        = "${var.bucket_prefix}-sensor-raw"
      Environment = var.environment
      Purpose     = "Raw sensor data from IoT devices"
    }
  )
}

resource "aws_s3_bucket" "api_raw" {
  bucket = "${var.bucket_prefix}-api-raw"

  tags = merge(
    var.tags,
    {
      Name        = "${var.bucket_prefix}-api-raw"
      Environment = var.environment
      Purpose     = "Raw API data (AQICN, OpenMeteo)"
    }
  )
}

resource "aws_s3_bucket" "merge_actuals" {
  bucket = "${var.bucket_prefix}-merge-actuals"

  tags = merge(
    var.tags,
    {
      Name        = "${var.bucket_prefix}-merge-actuals"
      Environment = var.environment
      Purpose     = "Merged actuals for ML training"
    }
  )
}

# Versioning
resource "aws_s3_bucket_versioning" "sensor_raw" {
  bucket = aws_s3_bucket.sensor_raw.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "api_raw" {
  bucket = aws_s3_bucket.api_raw.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "merge_actuals" {
  bucket = aws_s3_bucket.merge_actuals.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle rules for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "sensor_raw" {
  bucket = aws_s3_bucket.sensor_raw.id

  rule {
    id     = "transition_to_glacier"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "api_raw" {
  bucket = aws_s3_bucket.api_raw.id

  rule {
    id     = "transition_to_glacier"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "sensor_raw" {
  bucket = aws_s3_bucket.sensor_raw.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "api_raw" {
  bucket = aws_s3_bucket.api_raw.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "merge_actuals" {
  bucket = aws_s3_bucket.merge_actuals.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "sensor_raw" {
  bucket = aws_s3_bucket.sensor_raw.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "api_raw" {
  bucket = aws_s3_bucket.api_raw.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "merge_actuals" {
  bucket = aws_s3_bucket.merge_actuals.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
