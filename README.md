# Infrastructure as Code

**Complete AWS infrastructure provisioning:**

```
terraform/
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
└── .gitignore                 # Git ignore rules
```

## Deployment Options

### Option A: Manual Deployment (Using Setup Scripts)

**Step 1: Launch EC2 Instances Manually**

- Ingestor: t3.small, Ubuntu 24.04, 20GB volume
- Processor: t3.medium, Ubuntu 24.04, 20GB volume

**Step 2: Configure Security Groups**

- Ingestor: Allow 22, 9100, 9092, 1883, 8088, 3000
- Processor: Allow 22, 3000, 6379, 8765, 80

**Step 3: Run Setup Scripts**

```bash
# On Ingestor
ssh ubuntu@<ingestor-ip>
bash setup_ingestor.sh

# On Processor
ssh ubuntu@<processor-ip>
bash setup_processor.sh <ingestor-private-ip>
```

### Option B: Automated Deployment (Using Terraform)

**Step 1: Extract Terraform Files**

```bash
cd terraform
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

## What You Get

### Infrastructure Components

| Component           | Details                                                |
| ------------------- | ------------------------------------------------------ |
| **VPC**             | 10.0.0.0/16 with public subnet                         |
| **Ingestor EC2**    | t3.small, Kafka, Node Exporter                         |
| **Processor EC2**   | t3.medium, all services + monitoring                   |
| **S3 Buckets**      | fxa-sensor-raw, fxa-api-raw, fxa-merge-actuals, etc... |
| **Security Groups** | Configured for all required ports                      |
| **IAM Roles**       | S3 and Secrets Manager access                          |
| **Elastic IPs**     | Static IPs for both instances                          |

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

## Support Resources

- AWS Documentation: https://docs.aws.amazon.com
- Terraform Docs: https://registry.terraform.io/providers/hashicorp/aws
- Prometheus Docs: https://prometheus.io/docs
- Grafana Docs: https://grafana.com/docs
- Kafka Docs: https://kafka.apache.org/documentation
