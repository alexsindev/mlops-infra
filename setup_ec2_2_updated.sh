#!/bin/bash
# EC2 #2 Setup Script - Processor Instance
# Installs: Redis, Python services, Node Exporter, Prometheus, Grafana
# Run as: bash setup_ec2_2_updated.sh <KAFKA_BROKER_IP>
# Example: bash setup_ec2_2_updated.sh 172.31.19.83

set -e

# ── Required argument ──────────────────────────────
if [ -z "$1" ]; then
    echo "Usage: bash setup_ec2_2_updated.sh <KAFKA_BROKER_IP>"
    echo "Example: bash setup_ec2_2_updated.sh 172.31.19.83"
    exit 1
fi

KAFKA_BROKER="$1"
PRIVATE_IP=$(hostname -I | awk '{print $1}')

# Bucket names (update these to match your actual buckets)
BUCKET_SENSOR_RAW="fxa-sensor-raw"
BUCKET_API_RAW="fxa-api-raw"
BUCKET_ACTUALS="fxa-merge-actuals"

# API tokens (update with your actual token or use Secrets Manager)
AQICN_TOKEN="your_aqicn_token_here"

NODE_EXPORTER_VERSION="1.10.2"
PROMETHEUS_VERSION="3.4.0"

echo "=============================="
echo " Processor EC2 Setup Starting"
echo " Kafka Broker: $KAFKA_BROKER"
echo " Private IP: $PRIVATE_IP"
echo "=============================="

# ── Step 1: System update ──────────────────────────
echo "[1/10] Updating system..."
sudo apt update && sudo apt upgrade -y

# ── Step 2: Add swap ───────────────────────────────
echo "[2/10] Adding 2GB swap..."
if [ ! -f /swapfile ]; then
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi
free -h

# ── Step 3: Install dependencies ───────────────────
echo "[3/10] Installing system packages..."
sudo apt install -y python3-pip python3-dev redis-server

echo "[3/10] Installing Python packages..."
pip3 install kafka-python redis websockets boto3 requests --break-system-packages

# ── Step 4: Redis ──────────────────────────────────
echo "[4/10] Configuring Redis..."
sudo systemctl enable redis-server
sudo systemctl start redis-server
echo "[OK] Redis running"

# ── Step 5: Write Python scripts ───────────────────
echo "[5/10] Writing Python scripts..."

# (Same Python scripts as before - s3_writer.py, api_fetcher.py, consumer_anomaly.py, websocket_server.py)
# ... [I'll include the full Python scripts here]

cat > $HOME/s3_writer.py <<PYEOF
import json
import boto3
import redis
import time
from datetime import datetime, timezone
from kafka import KafkaConsumer
from collections import defaultdict

KAFKA_BROKER      = "${KAFKA_BROKER}:9092"
TOPIC             = "sensor.raw"
BUCKET_SENSOR_RAW = "${BUCKET_SENSOR_RAW}"
BUCKET_API_RAW    = "${BUCKET_API_RAW}"
BUCKET_ACTUALS    = "${BUCKET_ACTUALS}"
BATCH_INTERVAL    = 600
HOURLY_INTERVAL   = 3600

s3 = boto3.client("s3")
r  = redis.Redis(host="localhost", port=6379, decode_responses=True)

def s3_key(prefix, suffix=""):
    now = datetime.now(timezone.utc)
    return f"{prefix}/{now.strftime('%Y/%m/%d/%H%M%S')}{suffix}.json"

def write_to_s3(bucket, key, data):
    try:
        s3.put_object(Bucket=bucket, Key=key, Body=json.dumps(data), ContentType="application/json")
        print(f"[S3] Written to s3://{bucket}/{key}")
    except Exception as e:
        print(f"[S3] Error: {e}")

def fetch_api_snapshot():
    return r.hgetall("latest:aqicn"), r.hgetall("latest:openmeteo")

def aggregate(readings):
    if not readings:
        return {}
    fields = defaultdict(list)
    for reading in readings:
        for k, v in reading.items():
            if k == "topic":
                continue
            try:
                fields[k].append(float(v))
            except (ValueError, TypeError):
                pass
    return {k: round(sum(v) / len(v), 2) for k, v in fields.items()}

consumer = KafkaConsumer(
    TOPIC,
    bootstrap_servers=KAFKA_BROKER,
    value_deserializer=lambda m: json.loads(m.decode("utf-8")),
    auto_offset_reset="latest",
    group_id="s3-writer-v2",
    consumer_timeout_ms=1000
)

print("S3 writer started...")
batch          = []
hourly_climate = []
hourly_air     = []
last_batch     = time.time()
last_hourly    = time.time()

while True:
    for message in consumer:
        data = message.value
        batch.append(data)
        topic = data.get("topic", "")
        if "climate" in topic:
            hourly_climate.append(data)
        elif "airquality" in topic:
            hourly_air.append(data)
    now = time.time()
    if now - last_batch >= BATCH_INTERVAL:
        if batch:
            print(f"[BATCH] Writing {len(batch)} messages to S3")
            write_to_s3(BUCKET_SENSOR_RAW, s3_key("raw"), batch)
            batch = []
        last_batch = now
    if now - last_hourly >= HOURLY_INTERVAL:
        print("[HOURLY] Running 1h aggregation...")
        aqicn, openmeteo = fetch_api_snapshot()
        if aqicn or openmeteo:
            write_to_s3(BUCKET_API_RAW, s3_key("hourly"), {"aqicn": aqicn, "openmeteo": openmeteo, "timestamp": datetime.now(timezone.utc).isoformat()})
        actuals = {
            "climate_avg":    aggregate(hourly_climate),
            "airquality_avg": aggregate(hourly_air),
            "aqicn":          aqicn,
            "openmeteo":      openmeteo,
            "sample_count":   len(hourly_climate),
            "timestamp":      datetime.now(timezone.utc).isoformat()
        }
        write_to_s3(BUCKET_ACTUALS, s3_key("actuals"), actuals)
        print(f"[HOURLY] Actuals written")
        hourly_climate = []
        hourly_air     = []
        last_hourly    = now
PYEOF

cat > $HOME/api_fetcher.py <<PYEOF
import json
import time
import requests
import redis
from datetime import datetime, timezone

AQICN_TOKEN    = "${AQICN_TOKEN}"
AQICN_CITY     = "here"
LAT            = 14.0208
LON            = 100.5250
FETCH_INTERVAL = 3600

r = redis.Redis(host="localhost", port=6379, decode_responses=True)

def fetch_aqicn():
    try:
        url = f"https://api.waqi.info/feed/{AQICN_CITY}/?token={AQICN_TOKEN}"
        res = requests.get(url, timeout=10)
        data = res.json()
        if data["status"] == "ok":
            iaqi = data["data"]["iaqi"]
            result = {
                "aqi":         data["data"]["aqi"],
                "pm2_5_aqi":   iaqi.get("pm25", {}).get("v"),
                "pm10_aqi":    iaqi.get("pm10", {}).get("v"),
                "temperature": iaqi.get("t", {}).get("v"),
                "humidity":    iaqi.get("h", {}).get("v"),
                "timestamp":   datetime.now(timezone.utc).isoformat()
            }
            r.hset("latest:aqicn", mapping={k: str(v) for k, v in result.items()})
            print(f"[AQICN] {result}")
            return result
        else:
            print(f"[AQICN] Error: {data}")
    except Exception as e:
        print(f"[AQICN] Exception: {e}")
    return None

def fetch_openmeteo():
    try:
        url = (
            f"https://api.open-meteo.com/v1/forecast"
            f"?latitude={LAT}&longitude={LON}"
            f"&current=temperature_2m,relative_humidity_2m,"
            f"apparent_temperature,precipitation,wind_speed_10m"
            f"&timezone=Asia/Bangkok"
        )
        res = requests.get(url, timeout=10)
        data = res.json()
        current = data["current"]
        result = {
            "temperature":   current["temperature_2m"],
            "humidity":      current["relative_humidity_2m"],
            "feels_like":    current["apparent_temperature"],
            "precipitation": current["precipitation"],
            "wind_speed":    current["wind_speed_10m"],
            "timestamp":     datetime.now(timezone.utc).isoformat()
        }
        r.hset("latest:openmeteo", mapping={k: str(v) for k, v in result.items()})
        print(f"[OpenMeteo] {result}")
        return result
    except Exception as e:
        print(f"[OpenMeteo] Exception: {e}")
    return None

print("API fetcher started...")
while True:
    fetch_aqicn()
    fetch_openmeteo()
    print(f"Sleeping for {FETCH_INTERVAL // 60} minutes...")
    time.sleep(FETCH_INTERVAL)
PYEOF

cat > $HOME/consumer_anomaly.py <<PYEOF
import json
import redis
import statistics
from kafka import KafkaConsumer, KafkaProducer
from datetime import datetime, timezone

KAFKA_BROKER = "${KAFKA_BROKER}:9092"
TOPIC        = "sensor.raw"
REDIS_HOST   = "localhost"
REDIS_PORT   = 6379
WINDOW_SIZE  = 10

THRESHOLDS = {
    "temperature_c": {"min": 10,  "max": 45},
    "humidity_pct":  {"min": 10,  "max": 95},
    "pressure_hpa":  {"min": 950, "max": 1050},
    "pm2_5":         {"min": 0,   "max": 75},
    "pm10":          {"min": 0,   "max": 150},
}

r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

producer = KafkaProducer(
    bootstrap_servers=KAFKA_BROKER,
    value_serializer=lambda v: json.dumps(v).encode("utf-8")
)

history = {}

def check_anomaly(field, value):
    if field in THRESHOLDS:
        t = THRESHOLDS[field]
        if value < t["min"] or value > t["max"]:
            return True, f"{field}={value} outside threshold {t}"
    if field not in history:
        history[field] = []
    history[field].append(value)
    if len(history[field]) > WINDOW_SIZE:
        history[field].pop(0)
    if len(history[field]) >= 5:
        mean = statistics.mean(history[field])
        stdev = statistics.stdev(history[field])
        if stdev > 0:
            z = abs((value - mean) / stdev)
            if z > 3:
                return True, f"{field}={value} z-score={z:.2f}"
    return False, None

def process_message(data):
    topic = data.get("topic", "")
    ts = datetime.now(timezone.utc).isoformat()
    anomalies = []
    for field, value in data.items():
        if field == "topic" or not isinstance(value, (int, float)):
            continue
        is_anomaly, reason = check_anomaly(field, value)
        if is_anomaly:
            anomalies.append(reason)
    if "climate" in topic:
        r.hset("latest:climate", mapping={
            "temperature_c": data.get("temperature_c"),
            "humidity_pct":  data.get("humidity_pct"),
            "pressure_hpa":  data.get("pressure_hpa"),
            "timestamp":     ts
        })
        r.lpush("history:climate", json.dumps(data))
        r.ltrim("history:climate", 0, 9)
    elif "airquality" in topic:
        r.hset("latest:airquality", mapping={
            "pm1_0":     data.get("pm1_0"),
            "pm2_5":     data.get("pm2_5"),
            "pm10":      data.get("pm10"),
            "timestamp": ts
        })
        r.lpush("history:airquality", json.dumps(data))
        r.ltrim("history:airquality", 0, 9)
    if anomalies:
        print(f"[ANOMALY] {ts}: {anomalies}")
        anomaly_event = {"timestamp": ts, "source": topic, "anomalies": anomalies, "data": data}
        r.publish("anomaly.events", json.dumps(anomaly_event))
        producer.flush()
    else:
        print(f"[OK] {ts} {topic}: {data}")

consumer = KafkaConsumer(
    TOPIC,
    bootstrap_servers=KAFKA_BROKER,
    value_deserializer=lambda m: json.loads(m.decode("utf-8")),
    auto_offset_reset="latest",
    group_id="anomaly-detector"
)

print("Consumer started, waiting for messages...")
for message in consumer:
    process_message(message.value)
PYEOF

cat > $HOME/websocket_server.py <<'PYEOF'
import json
import asyncio
import redis.asyncio as aioredis
import websockets
from datetime import datetime, timezone

WS_HOST   = "0.0.0.0"
WS_PORT   = 8765
connected = set()

async def broadcast(message):
    if connected:
        await asyncio.gather(*[client.send(message) for client in connected], return_exceptions=True)

async def handler(websocket):
    connected.add(websocket)
    print(f"[WS] Client connected: {websocket.remote_address} — total: {len(connected)}")
    try:
        r = aioredis.Redis(host="localhost", port=6379, decode_responses=True)
        snapshot = {
            "type":       "snapshot",
            "climate":    await r.hgetall("latest:climate"),
            "airquality": await r.hgetall("latest:airquality"),
            "aqicn":      await r.hgetall("latest:aqicn"),
            "openmeteo":  await r.hgetall("latest:openmeteo"),
            "timestamp":  datetime.now(timezone.utc).isoformat()
        }
        await websocket.send(json.dumps(snapshot))
        await r.aclose()
        async for message in websocket:
            pass
    except websockets.exceptions.ConnectionClosedOK:
        pass
    except Exception as e:
        print(f"[WS] Error: {e}")
    finally:
        connected.discard(websocket)
        print(f"[WS] Client disconnected — total: {len(connected)}")

async def redis_listener():
    r = aioredis.Redis(host="localhost", port=6379, decode_responses=True)
    pubsub = r.pubsub()
    await pubsub.subscribe("anomaly.events")
    print("[WS] Subscribed to Redis anomaly.events")
    async for message in pubsub.listen():
        if message["type"] == "message":
            payload = json.loads(message["data"])
            payload["type"] = "anomaly"
            await broadcast(json.dumps(payload))

async def live_sensor_pusher():
    r = aioredis.Redis(host="localhost", port=6379, decode_responses=True)
    while True:
        await asyncio.sleep(5)
        if connected:
            payload = {
                "type":       "live",
                "climate":    await r.hgetall("latest:climate"),
                "airquality": await r.hgetall("latest:airquality"),
                "timestamp":  datetime.now(timezone.utc).isoformat()
            }
            await broadcast(json.dumps(payload))

async def main():
    print(f"[WS] Server starting on ws://{WS_HOST}:{WS_PORT}")
    async with websockets.serve(handler, WS_HOST, WS_PORT):
        await asyncio.gather(asyncio.Future(), redis_listener(), live_sensor_pusher())

asyncio.run(main())
PYEOF

# ── Step 6: Systemd services for Python apps ──────
echo "[6/10] Setting up Python service systemd units..."

for SERVICE in consumer-anomaly api-fetcher s3-writer websocket-server; do
    case $SERVICE in
        consumer-anomaly)
            SCRIPT="consumer_anomaly.py"
            DESC="Kafka Consumer and Anomaly Detector"
            ;;
        api-fetcher)
            SCRIPT="api_fetcher.py"
            DESC="API Fetcher (aqicn + Open-Meteo)"
            ;;
        s3-writer)
            SCRIPT="s3_writer.py"
            DESC="Kafka to S3 Writer"
            ;;
        websocket-server)
            SCRIPT="websocket_server.py"
            DESC="WebSocket Server"
            ;;
    esac

    sudo tee /etc/systemd/system/$SERVICE.service > /dev/null <<EOF
[Unit]
Description=$DESC
After=network-online.target redis-server.service
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 -u $HOME/$SCRIPT
Restart=on-failure
RestartSec=10
User=ubuntu

[Install]
WantedBy=multi-user.target
EOF
done

sudo systemctl daemon-reload
for SERVICE in consumer-anomaly api-fetcher s3-writer websocket-server; do
    sudo systemctl enable $SERVICE
    sudo systemctl start $SERVICE
    echo "[OK] $SERVICE enabled"
done

# ── Step 7: Install Node Exporter ─────────────────
echo "[7/10] Installing Node Exporter..."
sudo useradd --no-create-home --shell /bin/false node_exporter

cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
sudo mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter
rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*

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
    --collector.systemd.unit-include=(s3-writer|api-fetcher|consumer-anomaly|websocket-server|redis-server).service
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
echo "[OK] Node Exporter running on port 9100"

# ── Step 8: Install Prometheus ────────────────────
echo "[8/10] Installing Prometheus..."
sudo useradd --no-create-home --shell /bin/false prometheus
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /var/lib/prometheus

cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
tar xzf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz

sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/
sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool /usr/local/bin/
sudo chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/consoles /etc/prometheus/
sudo mv prometheus-${PROMETHEUS_VERSION}.linux-amd64/console_libraries /etc/prometheus/
sudo chown -R prometheus:prometheus /etc/prometheus

rm -rf prometheus-${PROMETHEUS_VERSION}.linux-amd64*

# Prometheus config
sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alert_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'ingestor'
    static_configs:
      - targets: ['${KAFKA_BROKER}:9100']
        labels:
          instance_role: 'ingestor'

  - job_name: 'processor'
    static_configs:
      - targets: ['localhost:9100']
        labels:
          instance_role: 'processor'
EOF

# Alert rules
sudo tee /etc/prometheus/alert_rules.yml > /dev/null <<'EOF'
groups:
  - name: service_health
    rules:
      - alert: ServiceDown
        expr: node_systemd_unit_state{state="active", name=~"s3-writer.service|api-fetcher.service|consumer-anomaly.service|websocket-server.service|redis-server.service|kafka.service"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.name }} is DOWN on {{ $labels.instance }}"
          description: "{{ $labels.name }} has been down for more than 1 minute."

  - name: disk_alerts
    rules:
      - alert: DiskSpaceCritical
        expr: (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk usage above 80% on {{ $labels.instance }}"
          description: "Disk usage is {{ $value | printf \"%.1f\" }}%."

      - alert: DiskSpaceDangerous
        expr: (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 > 95
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Disk usage above 95% on {{ $labels.instance }}"
          description: "Disk usage is {{ $value | printf \"%.1f\" }}%. Immediate action required."

  - name: system_alerts
    rules:
      - alert: HighCPU
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "CPU usage above 90% on {{ $labels.instance }}"
          description: "CPU usage is {{ $value | printf \"%.1f\" }}%."

      - alert: HighMemory
        expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 90
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Memory usage above 90% on {{ $labels.instance }}"
          description: "Memory usage is {{ $value | printf \"%.1f\" }}%."

      - alert: NodeExporterDown
        expr: up{job=~"ingestor|processor"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Node Exporter down on {{ $labels.instance }}"
          description: "Prometheus cannot reach {{ $labels.instance }}."
EOF

sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml /etc/prometheus/alert_rules.yml

# Prometheus systemd service
sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \\
    --config.file=/etc/prometheus/prometheus.yml \\
    --storage.tsdb.path=/var/lib/prometheus/ \\
    --storage.tsdb.retention.time=30d \\
    --web.console.templates=/etc/prometheus/consoles \\
    --web.console.libraries=/etc/prometheus/console_libraries
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now prometheus
echo "[OK] Prometheus running on port 9090"

# ── Step 9: Install Grafana ───────────────────────
echo "[9/10] Installing Grafana..."
sudo apt-get install -y apt-transport-https software-properties-common
sudo mkdir -p /etc/apt/keyrings
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana

sudo systemctl daemon-reload
sudo systemctl enable --now grafana-server
echo "[OK] Grafana running on port 3000"

# ── Step 10: Verify all services ───────────────────
echo "[10/10] Verifying all services..."
sleep 5
for SERVICE in redis-server consumer-anomaly api-fetcher s3-writer websocket-server node_exporter prometheus grafana-server; do
    STATUS=$(sudo systemctl is-active $SERVICE)
    echo "  $SERVICE: $STATUS"
done

echo ""
echo "=============================="
echo " Processor EC2 Setup Complete"
echo "=============================="
echo " Services:"
echo "   Redis           : active on port 6379"
echo "   consumer-anomaly: active"
echo "   api-fetcher     : active"
echo "   s3-writer       : active"
echo "   websocket-server: active on port 8765"
echo "   Node Exporter   : active on port 9100"
echo "   Prometheus      : active on port 9090"
echo "   Grafana         : active on port 3000"
echo ""
echo " S3 Buckets:"
echo "   - $BUCKET_SENSOR_RAW"
echo "   - $BUCKET_API_RAW"
echo "   - $BUCKET_ACTUALS"
echo ""
echo " Access URLs (use public IP):"
echo "   Grafana    : http://<PUBLIC_IP>:3000 (admin/admin)"
echo "   Prometheus : http://<PUBLIC_IP>:9090"
echo "   WebSocket  : ws://<PUBLIC_IP>:8765"
echo ""
echo " Next steps:"
echo "   1. Open ports in security group: 3000, 9090, 8765"
echo "   2. Configure Grafana data source: http://localhost:9090"
echo "   3. Import Node Exporter dashboard (ID: 1860)"
echo "   4. Update AQICN_TOKEN in api_fetcher.py or use Secrets Manager"
echo "=============================="
