#!/bin/bash
set -euo pipefail

# COS can boot with a restrictive host firewall (INPUT DROP). Ensure required ingress is allowed.
iptables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT
iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT

systemctl start docker

METADATA="http://metadata.google.internal/computeMetadata/v1"
TOKEN=""

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
ALLOWED_HOSTS=${allowed_hosts}
EOF

fetch_secret "${secret_names["cf_origin_cert"]}" > /home/codechroniclenet/origin.pem
fetch_secret "${secret_names["cf_origin_key"]}" > /home/codechroniclenet/origin-key.pem
chmod 600 /home/codechroniclenet/origin-key.pem

cd /home/codechroniclenet

cat > deploy-web.sh <<'DEPLOY'
${deploy_script}
DEPLOY
chmod 755 /home/codechroniclenet/deploy-web.sh

cat > nginx.conf <<'NGINX'
events {}
http {
    include /etc/nginx/mime.types;
    # Two types blocks in the SAME context add to one map, so this extends
    # mime.types rather than replacing it.  A types block inside a location
    # replaces the map instead, which is how every .png under /static/ came to
    # be served as application/octet-stream, and why no social card drew.
    types {
        application/javascript mjs;
    }
    default_type application/octet-stream;

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
            try_files $uri =404;
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

docker rm -f codechroniclenet-nginx 2>/dev/null || true

docker volume create staticfiles 2>/dev/null || true

bash /home/codechroniclenet/deploy-web.sh ${app_image}

docker run -d \
  --name codechroniclenet-nginx \
  --restart unless-stopped \
  --network host \
  -v ./nginx.conf:/etc/nginx/nginx.conf:ro \
  -v ./origin.pem:/etc/nginx/certs/origin.pem:ro \
  -v ./origin-key.pem:/etc/nginx/certs/origin-key.pem:ro \
  -v staticfiles:/staticfiles:ro \
  nginx:1.27-alpine
