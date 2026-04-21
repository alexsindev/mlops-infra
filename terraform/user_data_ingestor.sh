#!/bin/bash
set -e

# This script runs on first boot via Terraform user_data
# For complete setup, SSH in and run the full setup_ec2_1_updated.sh script

PRIVATE_IP=$(hostname -I | awk '{print $1}')
KAFKA_VERSION="3.9.2"
KAFKA_DIR="/home/ubuntu/kafka"
NODE_EXPORTER_VERSION="1.10.2"

# Log output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting Ingestor setup at $(date)"

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

# Install Java
apt install -y openjdk-17-jdk

# Install Kafka
cd /home/ubuntu
wget -q https://downloads.apache.org/kafka/$KAFKA_VERSION/kafka_2.13-$KAFKA_VERSION.tgz
tar -xzf kafka_2.13-$KAFKA_VERSION.tgz
mv kafka_2.13-$KAFKA_VERSION kafka
chown -R ubuntu:ubuntu kafka
rm kafka_2.13-$KAFKA_VERSION.tgz

# Configure Kafka
cd kafka
KAFKA_CLUSTER_ID=$(./bin/kafka-storage.sh random-uuid)
./bin/kafka-storage.sh format -t $KAFKA_CLUSTER_ID -c config/kraft/server.properties

sed -i "s|^listeners=.*|listeners=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093|" config/kraft/server.properties
sed -i "s|^#advertised.listeners=.*|advertised.listeners=PLAINTEXT://$PRIVATE_IP:9092|" config/kraft/server.properties
sed -i "s|^advertised.listeners=PLAINTEXT://.*|advertised.listeners=PLAINTEXT://$PRIVATE_IP:9092|" config/kraft/server.properties

# Kafka systemd service
cat > /etc/systemd/system/kafka.service <<EOF
[Unit]
Description=Apache Kafka
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
Environment="KAFKA_HEAP_OPTS=-Xmx512m -Xms256m"
ExecStart=$KAFKA_DIR/bin/kafka-server-start.sh $KAFKA_DIR/config/kraft/server.properties
ExecStop=$KAFKA_DIR/bin/kafka-server-stop.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kafka
systemctl start kafka

# Wait for Kafka
sleep 20

# Create topic
export KAFKA_HEAP_OPTS="-Xmx512m -Xms256m"
cd $KAFKA_DIR
./bin/kafka-topics.sh --create --bootstrap-server $PRIVATE_IP:9092 --replication-factor 1 --partitions 1 --topic sensor.raw --if-not-exists

# Set retention
./bin/kafka-configs.sh --bootstrap-server $PRIVATE_IP:9092 --alter --entity-type topics --entity-name sensor.raw --add-config retention.ms=${kafka_retention_ms}

# Install Node Exporter
useradd --no-create-home --shell /bin/false node_exporter

cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v$NODE_EXPORTER_VERSION/node_exporter-$NODE_EXPORTER_VERSION.linux-amd64.tar.gz
tar xzf node_exporter-$NODE_EXPORTER_VERSION.linux-amd64.tar.gz
mv node_exporter-$NODE_EXPORTER_VERSION.linux-amd64/node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter
rm -rf node_exporter-$NODE_EXPORTER_VERSION.linux-amd64*

cat > /etc/systemd/system/node_exporter.service <<'EOF'
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
    --collector.systemd \
    --collector.systemd.unit-include=(kafka).service
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now node_exporter

echo "Ingestor setup complete at $(date)"
