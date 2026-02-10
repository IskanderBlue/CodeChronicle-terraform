# CodeChronicle Terraform Deployment Guide

## Architecture

```
envs/prod/main.tf
  ├── modules/network      → VPC + subnet + firewall (443 from Cloudflare, 22 from admin)
  ├── modules/neon          → Neon Postgres project + role + db
  ├── modules/secrets       → GCP Secret Manager (DB URL, Django key, CF origin cert/key)
  ├── modules/compute       → GCE VM (e2-micro) + static IP + service account + startup.sh
  └── modules/cloudflare    → Proxied A record + TLS strict
```

Data flow: `neon.connection_uri → secrets → compute.secret_names`, `network → compute`, `compute.public_ip → cloudflare`.

## Manual Setup Required

### Sign up / accounts needed

1. **GCP project** — create one (or use existing), note the project ID
2. **Neon account** — sign up at [neon.tech](https://neon.tech), generate an API key from Account Settings
3. **Cloudflare account** — add your domain, generate an API token with `Zone:DNS:Edit` and `Zone:SSL and Certificates:Edit` permissions
4. **Cloudflare Origin CA cert** — in Cloudflare dashboard → SSL/TLS → Origin Server → Create Certificate; save the cert and private key

### GCP APIs to enable

- Compute Engine API
- Secret Manager API

### Variables to provide

Non-sensitive values — safe to put in `prod.tfvars`:

| Variable | Source |
|---|---|
| `gcp_project_id` | Your GCP project ID |
| `gcp_region` | GCP region (default: `us-central1`) |
| `gcp_zone` | GCP zone (default: `us-central1-a`) |
| `domain` | Your domain on Cloudflare |
| `app_image` | Docker image for CodeChronicle |
| `machine_type` | VM size (default: `e2-micro`) |
| `admin_ssh_cidrs` | Your IP as `["x.x.x.x/32"]` |

### Pre-create secrets in GCP Secret Manager

Before the first deploy, create these secrets once:

```bash
DJANGO_KEY=$(python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())")

gcloud secrets create django-secret-key --project=YOUR_PROJECT_ID
echo -n "$DJANGO_KEY" | gcloud secrets versions add django-secret-key --data-file=- --project=YOUR_PROJECT_ID

gcloud secrets create cf-origin-cert --project=YOUR_PROJECT_ID
gcloud secrets versions add cf-origin-cert --data-file=origin.pem --project=YOUR_PROJECT_ID

gcloud secrets create cf-origin-key --project=YOUR_PROJECT_ID
gcloud secrets versions add cf-origin-key --data-file=origin-key.pem --project=YOUR_PROJECT_ID

gcloud secrets create cloudflare-api-token --project=YOUR_PROJECT_ID
echo -n "YOUR_TOKEN" | gcloud secrets versions add cloudflare-api-token --data-file=- --project=YOUR_PROJECT_ID

gcloud secrets create neon-api-key --project=YOUR_PROJECT_ID
echo -n "YOUR_KEY" | gcloud secrets versions add neon-api-key --data-file=- --project=YOUR_PROJECT_ID
```

All secrets are stored in GCP Secret Manager — nothing sensitive touches your local files.

## Deploying

1. Copy `envs/prod/prod.tfvars.example` to `envs/prod/prod.tfvars` and fill in non-sensitive values.

2. Run via the wrapper script (fetches provider credentials from Secret Manager automatically):

```bash
./scripts/tf.sh init
./scripts/tf.sh plan
./scripts/tf.sh apply
```

## Post-Deploy

1. SSH into the VM and run migrations:

```bash
docker exec -it <container> python manage.py migrate
```

2. Seed code maps:

```bash
docker exec -it <container> python manage.py load_maps
```

3. Smoke test your health endpoint at `https://app.<domain>/`.

## Loading Data from Your Laptop

`load_code_metadata` and `load_maps` are pure data-loading commands — they read local files and write to the database via Django ORM, with no VM or Docker dependencies. You can run them directly against the Neon database from your laptop.

1. Get the Neon connection string from the Neon dashboard or GCP Secret Manager (`database_url` secret).

2. Run from the CodeChronicle repo:

```bash
cd ../CodeChronicle
set DATABASE_URL=postgresql://codechroniclenet_app:<password>@<host>/codechroniclenet?sslmode=require
set DJANGO_SETTINGS_MODULE=code_chronicle.settings.production

python manage.py load_code_metadata --source config/metadata.json
python manage.py load_maps --source ../CodeChronicle-Mapping/maps
```

No SSH or Docker needed. Migrations (`manage.py migrate`) can also be run this way.

## Updating the App (without Terraform)

The Docker image tag (default: `latest`) is set once by Terraform. To deploy a new version:

```bash
gcloud compute ssh codechroniclenet-vm --zone=us-central1-a --command="cd /opt/codechroniclenet && docker compose pull && docker compose up -d"
```

No `terraform apply` needed unless you're changing infrastructure (VM size, firewall rules, secrets, etc.).
