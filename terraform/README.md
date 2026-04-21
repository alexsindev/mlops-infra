# IoT Data Pipeline - Terraform Infrastructure

This Terraform configuration provisions the complete IoT data pipeline infrastructure on AWS.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  AWS Cloud (ap-southeast-2)                                     │
│                                                                 │
│  ┌──────────────────┐           ┌──────────────────┐            │
│  │ Ingestor EC2     │           │ Processor EC2    │            │
│  │ (t3.small)       │           │ (t3.medium)      │            │
│  │                  │           │                  │            │
│  │ • Kafka          │──────────▶│ • s3-writer      │            │
│  │ • Node Exporter  │           │ • api-fetcher    │            │
│  └──────────────────┘           │ • consumer-      │            │
│                                  │   anomaly        │            │
│                                  │ • websocket-     │            │
│  ┌──────────────────┐           │   server         │            │
│  │ S3 Buckets       │◀──────────│ • Redis          │            │
│  │                  │           │ • Node Exporter  │            │
│  │ • sensor-raw     │           │ • Prometheus     │            │
│  │ • api-raw        │           │ • Grafana        │            │
│  │ • merge-actuals  │           └──────────────────┘            │
│  └──────────────────┘                                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **Terraform** >= 1.0
2. **AWS CLI** configured with credentials
3. **EC2 Key Pair** created in your AWS region
4. **Your IP address** for security group SSH access

## Quick Start

### 1. Clone and Configure

```bash
cd terraform-iot-pipeline
cp terraform.tfvars.example terraform.tfvars
```

### 2. Edit terraform.tfvars

```hcl
aws_region        = "ap-southeast-2"
project_name      = "iot-pipeline"
key_name          = "your-ec2-key-name"
allowed_ssh_cidrs = ["YOUR.IP.ADDRESS/32"]
aqicn_token       = "your-aqicn-token"  # Optional
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Plan

```bash
terraform plan
```

### 5. Apply

```bash
terraform apply
```

This will create:
- VPC with public subnet
- 2 EC2 instances (Ingestor, Processor)
- 3 S3 buckets
- Security groups
- IAM roles and policies
- Elastic IPs

### 6. Get Outputs

```bash
terraform output
```

You'll see:
- Grafana URL: http://<processor-ip>:3000
- Prometheus URL: http://<processor-ip>:9090
- SSH commands
- S3 bucket names

## Post-Deployment Setup

### Initial Configuration

The user_data scripts handle basic setup, but for full functionality:

**On Ingestor EC2:**
```bash
ssh -i your-key.pem ubuntu@<ingestor-ip>
# Verify Kafka is running
sudo systemctl status kafka
sudo systemctl status node_exporter
```

**On Processor EC2:**
```bash
ssh -i your-key.pem ubuntu@<processor-ip>
# For complete setup, run the full script
bash setup_ec2_2_updated.sh <ingestor-private-ip>
```

### Access Monitoring

1. **Grafana**: http://<processor-ip>:3000
   - Default login: admin/admin
   - Add Prometheus data source: http://localhost:9090
   - Import Node Exporter dashboard (ID: 1860)

2. **Prometheus**: http://<processor-ip>:9090
   - View targets: /targets
   - View alerts: /alerts

## Configuration

### Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | ap-southeast-2 |
| `project_name` | Project name prefix | iot-pipeline |
| `key_name` | EC2 key pair name | **Required** |
| `allowed_ssh_cidrs` | IP addresses for SSH | 0.0.0.0/0 |
| `ingestor_instance_type` | Ingestor instance type | t3.small |
| `processor_instance_type` | Processor instance type | t3.medium |
| `bucket_prefix` | S3 bucket prefix | fxa |
| `aqicn_token` | Air Quality API token | "" |

### Resource Sizing

**Ingestor (t3.small):**
- 2 vCPUs, 2 GB RAM
- 20 GB root volume
- Runs: Kafka, Node Exporter

**Processor (t3.medium):**
- 2 vCPUs, 4 GB RAM
- 20 GB root volume
- Runs: 4 Python services, Redis, Prometheus, Grafana

## Cost Estimation

Monthly AWS costs (ap-southeast-2):
- 2x EC2 instances: ~$40-50
- 3x S3 buckets: ~$5-10 (depends on usage)
- Data transfer: ~$5
- **Total: ~$50-65/month**

## Security

- All S3 buckets have encryption enabled
- Public access blocked on S3
- Security groups restrict access by IP
- IAM roles follow least-privilege principle
- SSH limited to allowed_ssh_cidrs

## Secrets Management (Optional)

To use AWS Secrets Manager instead of hardcoded values:

```bash
# Create secret
aws secretsmanager create-secret \
    --name mlops/services \
    --secret-string '{
        "AQICN_TOKEN": "your-token",
        "KAFKA_BROKER": "<ingestor-private-ip>:9092",
        "TOPIC": "sensor.raw",
        "BUCKET_SENSOR_RAW": "fxa-sensor-raw",
        "BUCKET_API_RAW": "fxa-api-raw",
        "BUCKET_ACTUALS": "fxa-merge-actuals"
    }'
```

The Processor IAM role already has GetSecretValue permission.

## Monitoring

### Metrics Collected

- **System**: CPU, memory, disk, network
- **Services**: Kafka, s3-writer, api-fetcher, consumer-anomaly, websocket-server, Redis
- **Retention**: 30 days

### Alerts Configured

1. ServiceDown (critical): Any service inactive > 1m
2. DiskSpaceCritical (warning): Disk > 80% for 5m
3. DiskSpaceDangerous (critical): Disk > 95% for 1m
4. HighCPU (warning): CPU > 90% for 5m
5. HighMemory (warning): Memory > 90% for 5m
6. NodeExporterDown (critical): Exporter unreachable > 1m

## Troubleshooting

### Kafka not starting

```bash
ssh ubuntu@<ingestor-ip>
sudo journalctl -u kafka -f
# Check disk space
df -h
```

### Services not running on Processor

```bash
ssh ubuntu@<processor-ip>
sudo systemctl status s3-writer
sudo systemctl status api-fetcher
sudo systemctl status consumer-anomaly
sudo systemctl status websocket-server
```

### Prometheus not scraping

```bash
# Check network connectivity
nc -zv <ingestor-ip> 9100
# Check Prometheus logs
sudo journalctl -u prometheus -f
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete all EC2 instances and data. S3 buckets with versioning may require manual cleanup.

## Files

| File | Purpose |
|------|---------|
| `main.tf` | Provider and data sources |
| `variables.tf` | Input variables |
| `outputs.tf` | Output values |
| `vpc.tf` | VPC and networking |
| `security_groups.tf` | Security group rules |
| `s3.tf` | S3 bucket configuration |
| `iam.tf` | IAM roles and policies |
| `ec2_ingestor.tf` | Ingestor EC2 instance |
| `ec2_processor.tf` | Processor EC2 instance |
| `user_data_ingestor.sh` | Bootstrap script for Ingestor |

## Support

For issues or questions, refer to the main project documentation or check:
- Terraform logs: `terraform apply` output
- EC2 user-data logs: `/var/log/user-data.log`
- Service logs: `journalctl -u <service-name>`
