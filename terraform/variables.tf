variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-southeast-2" # Sydney
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "iot-pipeline"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

# EC2 Instance Configuration
variable "ingestor_instance_type" {
  description = "Instance type for Ingestor EC2"
  type        = string
  default     = "t3.small"
}

variable "processor_instance_type" {
  description = "Instance type for Processor EC2"
  type        = string
  default     = "t3.medium"
}

variable "ingestor_volume_size" {
  description = "Root volume size for Ingestor instance (GB)"
  type        = number
  default     = 20
}

variable "processor_volume_size" {
  description = "Root volume size for Processor instance (GB)"
  type        = number
  default     = 20
}

variable "key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH into instances"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Change this to your IP for security
}

# Application Configuration
variable "bucket_prefix" {
  description = "Prefix for S3 bucket names"
  type        = string
  default     = "fxa"
}

variable "aqicn_token" {
  description = "Air Quality API token (or use Secrets Manager)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "kafka_retention_ms" {
  description = "Kafka topic retention in milliseconds (7 days default)"
  type        = number
  default     = 604800000
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable detailed CloudWatch monitoring for EC2 instances"
  type        = bool
  default     = true
}

variable "prometheus_retention_days" {
  description = "Prometheus data retention in days"
  type        = number
  default     = 30
}

# Tagging
variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
