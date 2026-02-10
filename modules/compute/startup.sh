#!/bin/bash
set -euo pipefail

if ! command -v docker &> /dev/null; then
  apt-get update -y
  apt-get install -y docker.io docker-compose-plugin
  systemctl enable docker
  systemctl start docker
fi

fetch_secret() {
  gcloud secrets versions access latest --secret="$1" --project="${project_id}"
}

mkdir -p /opt/codechroniclenet

cat > /opt/codechroniclenet/.env <<EOF
DATABASE_URL=$(fetch_secret "${secret_names["database_url"]}")
DJANGO_SECRET_KEY=$(fetch_secret "${secret_names["django_secret_key"]}")
EOF

fetch_secret "${secret_names["cf_origin_cert"]}" > /opt/codechroniclenet/origin.pem
fetch_secret "${secret_names["cf_origin_key"]}" > /opt/codechroniclenet/origin-key.pem
chmod 600 /opt/codechroniclenet/origin-key.pem

cat > /opt/codechroniclenet/docker-compose.yml <<'COMPOSE'
services:
  web:
    image: ${app_image}
    restart: unless-stopped
    env_file: .env
    ports:
      - "443:443"
    volumes:
      - ./origin.pem:/etc/ssl/certs/origin.pem:ro
      - ./origin-key.pem:/etc/ssl/private/origin-key.pem:ro
COMPOSE

cd /opt/codechroniclenet
docker compose pull
docker compose up -d
