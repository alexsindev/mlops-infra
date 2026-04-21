# IoT Pipeline Infrastructure - Deployment Guide

## What Was Created

### 1. Updated Setup Scripts (Current State)

**setup_ec2_1_updated.sh** - Ingestor Instance
- Kafka 3.9.2 (KRaft mode)
- Node Exporter 1.10.2
- Topic: sensor.raw (7-day retention)
- Systemd services for automation

**setup_ec2_2_updated.sh** - Processor Instance
- Redis server
- 4 Python services (s3-writer, api-fetcher, consumer-anomaly, websocket-server)
- Node Exporter 1.10.2
- Prometheus 3.4.0
- Grafana (latest from apt)
- Complete monitoring stack with alert rules

### 2. Terraform Infrastructure as Code

**Complete AWS infrastructure provisioning:**

```
terraform-iot-pipeline/
├── main.tf                    # Provider and data sources
├── variables.tf               # Input variables
├── outputs.tf                 # Output values (IPs, URLs)
├── vpc.tf                     # VPC and networking
├── security_groups.tf         # Firewall rules
├── s3.tf                      # 3 S3 buckets with encryption
├── iam.tf                     # IAM roles and policies
├── ec2_ingestor.tf           # Ingestor EC2 instance
├── ec2_processor.tf          # Processor EC2 instance
├── user_data_ingestor.sh     # Bootstrap script
├── user_data_processor.sh    # Bootstrap script
├── terraform.tfvars.example  # Configuration template
├── README.md                  # Complete documentation
└── .gitignore                 # Git ignore rules
```

## Deployment Options

### Option A: Manual Deployment (Using Setup Scripts)

**Step 1: Launch EC2 Instances Manually**
- Ingestor: t3.small, Ubuntu 24.04, 20GB volume
- Processor: t3.medium, Ubuntu 24.04, 20GB volume

**Step 2: Configure Security Groups**
- Ingestor: Allow 22, 9092, 9100
- Processor: Allow 22, 3000, 8765, 9090, 9100

**Step 3: Run Setup Scripts**
```bash
# On Ingestor
ssh ubuntu@<ingestor-ip>
bash setup_ec2_1_updated.sh

# On Processor
ssh ubuntu@<processor-ip>
bash setup_ec2_2_updated.sh <ingestor-private-ip>
```

### Option B: Automated Deployment (Using Terraform)

**Step 1: Extract Terraform Files**
```bash
tar -xzf terraform-iot-pipeline.tar.gz
cd terraform-iot-pipeline
```

**Step 2: Configure Variables**
```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Edit these required values:
```hcl
key_name          = "your-ec2-key-name"
allowed_ssh_cidrs = ["YOUR_IP/32"]
aqicn_token       = "your-token"  # Optional
```

**Step 3: Deploy Infrastructure**
```bash
terraform init
terraform plan
terraform apply
```

**Step 4: Get Access Information**
```bash
terraform output
```

**Step 5: Complete Setup (Optional)**

The Terraform user_data scripts handle basic setup. For full functionality:
```bash
# SSH into Processor
ssh -i your-key.pem ubuntu@<processor-ip>

# Run full setup script
bash setup_ec2_2_updated.sh <ingestor-private-ip>
```

## What You Get

### Infrastructure Components

| Component | Details |
|-----------|---------|
| **VPC** | 10.0.0.0/16 with public subnet |
| **Ingestor EC2** | t3.small, Kafka, Node Exporter |
| **Processor EC2** | t3.medium, all services + monitoring |
| **S3 Buckets** | fxa-sensor-raw, fxa-api-raw, fxa-merge-actuals |
| **Security Groups** | Configured for all required ports |
| **IAM Roles** | S3 and Secrets Manager access |
| **Elastic IPs** | Static IPs for both instances |

### Services Running

**Ingestor (172.31.19.83):**
- Kafka broker on port 9092
- Node Exporter on port 9100

**Processor (172.31.30.184):**
- s3-writer service
- api-fetcher service
- consumer-anomaly service
- websocket-server on port 8765
- Redis on port 6379
- Node Exporter on port 9100
- Prometheus on port 9090
- Grafana on port 3000

### Monitoring Stack

**Prometheus Metrics:**
- System: CPU, memory, disk, network
- Services: all 6 services health status
- Retention: 30 days

**Alert Rules (6 total):**
1. ServiceDown (critical)
2. DiskSpaceCritical (warning, >80%)
3. DiskSpaceDangerous (critical, >95%)
4. HighCPU (warning, >90%)
5. HighMemory (warning, >90%)
6. NodeExporterDown (critical)

**Grafana Dashboards:**
- Node Exporter Full (importable, ID: 1860)
- Service Health (custom, shows UP/DOWN status)

## Access URLs

After deployment, access:

```
Grafana:     http://<processor-ip>:3000
             Login: admin/admin

Prometheus:  http://<processor-ip>:9090
             Targets: /targets
             Alerts: /alerts

WebSocket:   ws://<processor-ip>:8765
             For real-time dashboard
```

## Cost Estimate

Monthly AWS costs (ap-southeast-2):
- 2x EC2 instances: ~$40-50
- 3x S3 buckets: ~$5-10
- Data transfer: ~$5
- **Total: ~$50-65/month**

## Next Steps After Deployment

1. **Configure Grafana**
   - Add Prometheus data source: http://localhost:9090
   - Import Node Exporter dashboard (ID: 1860)
   - Create service health dashboard with your custom query

2. **Test the Pipeline**
   - Send test data to Kafka topic
   - Verify data appears in S3
   - Check Grafana for service health

3. **Configure Alerts (Optional)**
   - Set up email notifications in Grafana
   - Configure SMTP in /etc/grafana/grafana.ini

4. **Use Secrets Manager (Optional)**
   - Create mlops/services secret in AWS
   - Update Python scripts to use boto3 to fetch secrets
   - Remove hardcoded credentials

## Files Structure Summary

```
Deliverables:
├── setup_ec2_1_updated.sh          # Manual setup for Ingestor
├── setup_ec2_2_updated.sh          # Manual setup for Processor
└── terraform-iot-pipeline.tar.gz   # Complete IaC package
    ├── Terraform configs (*.tf)
    ├── Bootstrap scripts (user_data_*.sh)
    ├── README.md (full documentation)
    └── terraform.tfvars.example
```

## Key Differences from Old Scripts

### Old Version
- No monitoring stack
- No Node Exporter
- No Prometheus/Grafana
- Manual security group setup
- No IAM roles
- Hardcoded IPs

### New Version
- ✅ Complete monitoring with Prometheus + Grafana
- ✅ Node Exporter on both instances
- ✅ 6 alert rules configured
- ✅ Infrastructure as Code with Terraform
- ✅ Automated security group configuration
- ✅ IAM roles for S3 and Secrets Manager
- ✅ Parameterized configuration
- ✅ Production-ready with encryption, versioning
- ✅ Cost optimization with S3 lifecycle policies

## Troubleshooting

**Terraform fails to apply:**
- Check AWS credentials: `aws sts get-caller-identity`
- Verify key_name exists in AWS
- Ensure allowed_ssh_cidrs is your actual IP

**Services not starting:**
```bash
# Check logs
sudo journalctl -u <service-name> -f

# Restart service
sudo systemctl restart <service-name>
```

**Prometheus not scraping:**
```bash
# Test connectivity
nc -zv <ingestor-ip> 9100

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets
```

**Grafana login issues:**
- Default: admin/admin
- Reset: `sudo grafana-cli admin reset-admin-password newpassword`

## Support Resources

- AWS Documentation: https://docs.aws.amazon.com
- Terraform Docs: https://registry.terraform.io/providers/hashicorp/aws
- Prometheus Docs: https://prometheus.io/docs
- Grafana Docs: https://grafana.com/docs
- Kafka Docs: https://kafka.apache.org/documentation

## Quick Reference Commands

```bash
# Terraform
terraform init                  # Initialize
terraform plan                  # Preview changes
terraform apply                 # Deploy
terraform destroy               # Tear down
terraform output                # Show outputs

# Service Management
sudo systemctl status <service>
sudo systemctl restart <service>
sudo journalctl -u <service> -f

# Kafka
~/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092
~/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic sensor.raw

# Monitoring
curl http://localhost:9090/api/v1/targets     # Prometheus targets
curl http://localhost:9100/metrics | grep kafka  # Node Exporter
```

---

**You now have:**
1. ✅ Updated setup scripts matching current architecture
2. ✅ Complete Terraform IaC for automated deployment
3. ✅ Production-ready infrastructure with monitoring
4. ✅ Full documentation and troubleshooting guides
