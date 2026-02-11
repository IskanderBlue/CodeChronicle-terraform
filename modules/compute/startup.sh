#!/bin/bash
set -euo pipefail

# COS can boot with a restrictive host firewall (INPUT DROP). Ensure HTTPS ingress is allowed.
iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT

systemctl start docker

METADATA="http://metadata.google.internal/computeMetadata/v1"

for i in $(seq 1 10); do
  TOKEN=$(curl -sf -H "Metadata-Flavor: Google" "$METADATA/instance/service-accounts/default/token" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null) && break
  echo "Waiting for metadata service... (attempt $i)"
  sleep 3
done

if [ -z "$TOKEN" ]; then
  echo "Failed to get access token from metadata service"
  exit 1
fi

fetch_secret() {
  curl -sf \
    -H "Authorization: Bearer $TOKEN" \
    "https://secretmanager.googleapis.com/v1/$1/versions/latest:access" \
    | python3 -c "import sys,json,base64; print(base64.b64decode(json.load(sys.stdin)['payload']['data']).decode(), end='')"
}

mkdir -p /home/codechroniclenet

cat > /home/codechroniclenet/.env <<EOF
GCP_PROJECT_ID=${project_id}
DJANGO_SETTINGS_MODULE=code_chronicle.settings.production
ALLOWED_HOSTS=${domain},app.${domain},localhost
EOF

fetch_secret "${secret_names["cf_origin_cert"]}" > /home/codechroniclenet/origin.pem
fetch_secret "${secret_names["cf_origin_key"]}" > /home/codechroniclenet/origin-key.pem
chmod 600 /home/codechroniclenet/origin-key.pem

cd /home/codechroniclenet

cat > nginx.conf <<'NGINX'
events {}
http {
    upstream django_app {
        server 127.0.0.1:8000;
    }
    server {
        listen 80;
        server_name _;
        return 301 https://$host$request_uri;
    }
    server {
        listen 443 ssl;
        server_name _;
        ssl_certificate /etc/nginx/certs/origin.pem;
        ssl_certificate_key /etc/nginx/certs/origin-key.pem;
        location /static/ {
            alias /staticfiles/;
            access_log off;
            expires 30d;
        }
        location / {
            proxy_pass http://django_app;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_redirect off;
        }
    }
}
NGINX

docker pull ${app_image}

docker rm -f codechroniclenet-web codechroniclenet-nginx 2>/dev/null || true

docker volume create staticfiles 2>/dev/null || true

docker run -d \
  --name codechroniclenet-web \
  --restart unless-stopped \
  --env-file .env \
  --network host \
  -v staticfiles:/app/staticfiles \
  ${app_image}

docker run -d \
  --name codechroniclenet-nginx \
  --restart unless-stopped \
  --network host \
  -v ./nginx.conf:/etc/nginx/nginx.conf:ro \
  -v ./origin.pem:/etc/nginx/certs/origin.pem:ro \
  -v ./origin-key.pem:/etc/nginx/certs/origin-key.pem:ro \
  -v staticfiles:/staticfiles:ro \
  nginx:1.27-alpine
