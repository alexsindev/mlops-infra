#!/bin/bash
# EC2 #1 Setup Script - Ingestor Instance
# Installs: Kafka (KRaft mode), Node Exporter
# Optional: Mosquitto MQTT broker, MQTT-Kafka Bridge
# Run as: bash setup_ec2_1_updated.sh

set -e

PRIVATE_IP=$(hostname -I | awk '{print $1}')
KAFKA_VERSION="3.9.2"
KAFKA_DIR="$HOME/kafka"
NODE_EXPORTER_VERSION="1.10.2"

# Optional MQTT settings (uncomment if using ESP32 sensors)
# MQTT_USER="esp32_client"
# MQTT_PASS="your_mqtt_password"

echo "=============================="
echo " Ingestor EC2 Setup Starting"
echo " Private IP: $PRIVATE_IP"
echo "=============================="

# ── Step 1: System update ──────────────────────────
echo "[1/7] Updating system..."
sudo apt update && sudo apt upgrade -y

# ── Step 2: Add swap ───────────────────────────────
echo "[2/7] Adding 2GB swap..."
if [ ! -f /swapfile ]; then
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi
free -h

# ── Step 3: Install Java ───────────────────────────
echo "[3/7] Installing Java..."
sudo apt install -y openjdk-17-jdk
java -version

# ── Step 4: Install Kafka ──────────────────────────
echo "[4/7] Installing Kafka $KAFKA_VERSION..."
if [ ! -d "$KAFKA_DIR" ]; then
    cd ~
    wget https://downloads.apache.org/kafka/$KAFKA_VERSION/kafka_2.13-$KAFKA_VERSION.tgz
    tar -xzf kafka_2.13-$KAFKA_VERSION.tgz
    mv kafka_2.13-$KAFKA_VERSION kafka
    rm kafka_2.13-$KAFKA_VERSION.tgz
    
    # Configure Kafka KRaft
    KAFKA_CLUSTER_ID="$(kafka/bin/kafka-storage.sh random-uuid)"
    kafka/bin/kafka-storage.sh format -t $KAFKA_CLUSTER_ID -c kafka/config/kraft/server.properties
    
    # Update listeners
    sed -i "s|^listeners=.*|listeners=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093|" kafka/config/kraft/server.properties
    sed -i "s|^#advertised.listeners=.*|advertised.listeners=PLAINTEXT://$PRIVATE_IP:9092|" kafka/config/kraft/server.properties
    sed -i "s|^advertised.listeners=PLAINTEXT://.*|advertised.listeners=PLAINTEXT://$PRIVATE_IP:9092|" kafka/config/kraft/server.properties
fi

# ── Step 5: Kafka systemd service ─────────────────
echo "[5/7] Setting up Kafka systemd service..."
sudo tee /etc/systemd/system/kafka.service > /dev/null <<EOF
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

sudo systemctl daemon-reload
sudo systemctl enable kafka
sudo systemctl start kafka
echo "Waiting for Kafka to start..."
sleep 20

# Create topic
export KAFKA_HEAP_OPTS="-Xmx512m -Xms256m"
kafka/bin/kafka-topics.sh --create --bootstrap-server $PRIVATE_IP:9092 --replication-factor 1 --partitions 1 --topic sensor.raw --if-not-exists

# Set retention to 7 days
kafka/bin/kafka-configs.sh --bootstrap-server $PRIVATE_IP:9092 --alter --entity-type topics --entity-name sensor.raw --add-config retention.ms=604800000

echo "[OK] Kafka running with topic: sensor.raw"

# ── Step 6: Install Node Exporter ──────────────────
echo "[6/7] Installing Node Exporter..."
sudo useradd --no-create-home --shell /bin/false node_exporter

cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
sudo mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter
rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*

# Create Node Exporter systemd service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF'
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

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
echo "[OK] Node Exporter running on port 9100"

# ── Step 7: Verify services ────────────────────────
echo "[7/7] Verifying services..."
sleep 3
for SERVICE in kafka node_exporter; do
    STATUS=$(sudo systemctl is-active $SERVICE)
    echo "  $SERVICE: $STATUS"
done

echo ""
echo "=============================="
echo " Ingestor EC2 Setup Complete"
echo "=============================="
echo " Kafka          : active on port 9092"
echo " Node Exporter  : active on port 9100"
echo " Private IP     : $PRIVATE_IP"
echo ""
echo " Topics created:"
echo "   - sensor.raw (7 day retention)"
echo ""
echo " Next steps:"
echo " 1. Open port 9092 in security group for Processor EC2"
echo " 2. Open port 9100 in security group for Prometheus"
echo " 3. Run setup_ec2_2_updated.sh on Processor EC2"
echo "    with KAFKA_BROKER=$PRIVATE_IP"
echo "=============================="
