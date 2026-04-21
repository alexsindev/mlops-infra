output "ingestor_public_ip" {
  description = "Public IP address of Ingestor instance"
  value       = aws_eip.ingestor.public_ip
}

output "ingestor_private_ip" {
  description = "Private IP address of Ingestor instance"
  value       = aws_instance.ingestor.private_ip
}

output "processor_public_ip" {
  description = "Public IP address of Processor instance"
  value       = aws_eip.processor.public_ip
}

output "processor_private_ip" {
  description = "Private IP address of Processor instance"
  value       = aws_instance.processor.private_ip
}

output "grafana_url" {
  description = "URL to access Grafana dashboard"
  value       = "http://${aws_eip.processor.public_ip}:3000"
}

output "prometheus_url" {
  description = "URL to access Prometheus"
  value       = "http://${aws_eip.processor.public_ip}:9090"
}

output "websocket_url" {
  description = "WebSocket URL for dashboard"
  value       = "ws://${aws_eip.processor.public_ip}:8765"
}

output "s3_bucket_sensor_raw" {
  description = "S3 bucket for raw sensor data"
  value       = aws_s3_bucket.sensor_raw.id
}

output "s3_bucket_api_raw" {
  description = "S3 bucket for API data"
  value       = aws_s3_bucket.api_raw.id
}

output "s3_bucket_merge_actuals" {
  description = "S3 bucket for merged actuals"
  value       = aws_s3_bucket.merge_actuals.id
}

output "ssh_command_ingestor" {
  description = "SSH command to connect to Ingestor"
  value       = "ssh -i <your-key.pem> ubuntu@${aws_eip.ingestor.public_ip}"
}

output "ssh_command_processor" {
  description = "SSH command to connect to Processor"
  value       = "ssh -i <your-key.pem> ubuntu@${aws_eip.processor.public_ip}"
}

output "kafka_broker_endpoint" {
  description = "Kafka broker endpoint (private IP)"
  value       = "${aws_instance.ingestor.private_ip}:9092"
}
