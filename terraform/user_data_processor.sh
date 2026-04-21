#!/bin/bash
set -e

# NOTE: This is a minimal bootstrap script
# For full functionality, SSH into the instance and run setup_ec2_2_updated.sh

KAFKA_BROKER="${kafka_broker}"
BUCKET_SENSOR_RAW="${bucket_sensor_raw}"
BUCKET_API_RAW="${bucket_api_raw}"
BUCKET_ACTUALS="${bucket_actuals}"
AQICN_TOKEN="${aqicn_token}"

# Log output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting Processor setup at $(date)"

# System update
apt update && apt upgrade -y

# Add swap
if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Install dependencies
apt install -y python3-pip python3-dev redis-server

# Install Python packages
pip3 install kafka-python redis websockets boto3 requests --break-system-packages

# Enable and start Redis
systemctl enable redis-server
systemctl start redis-server

echo "Basic setup complete at $(date)"
echo "IMPORTANT: SSH into this instance and run setup_ec2_2_updated.sh $KAFKA_BROKER"
echo "This will complete the installation of all services, Prometheus, and Grafana"
