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

gcloud secrets create django_secret_key --project=YOUR_PROJECT_ID
echo -n "$DJANGO_KEY" | gcloud secrets versions add django_secret_key --data-file=- --project=YOUR_PROJECT_ID

gcloud secrets create cf_origin_cert --project=YOUR_PROJECT_ID
gcloud secrets versions add cf_origin_cert --data-file=origin.pem --project=YOUR_PROJECT_ID

gcloud secrets create cf_origin_key --project=YOUR_PROJECT_ID
gcloud secrets versions add cf_origin_key --data-file=origin-key.pem --project=YOUR_PROJECT_ID
```

Set provider credentials as shell environment variables (not Secret Manager):

```bash
export TF_VAR_cloudflare_api_token="YOUR_TOKEN"
export TF_VAR_neon_api_key="YOUR_KEY"
```

App/runtime secrets remain in GCP Secret Manager.

## Deploying

1. Copy `envs/prod/prod.tfvars.example` to `envs/prod/prod.tfvars` and fill in non-sensitive values.

2. Run Terraform directly from `envs/prod`:

```bash
terraform -chdir=envs/prod init
terraform -chdir=envs/prod plan -var-file=prod.tfvars
terraform -chdir=envs/prod apply -var-file=prod.tfvars
```

### Important: COS host firewall behavior

Some Container-Optimized OS boots can have a restrictive host firewall (`iptables` `INPUT DROP`).  
This can cause Cloudflare `522` even when GCP VPC firewall rules are correct.

The compute startup script now applies an idempotent host-level allow for HTTPS:

```bash
iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT
```

If you update infrastructure and still see `522`, confirm this rule exists on the VM:

```bash
gcloud compute ssh codechroniclenet-vm --zone=us-central1-a --command="sudo iptables -S INPUT"
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

3. Smoke test your health endpoint at `https://app.<domain>/api/health`.

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

Normal app deploys should now happen from `../CodeChronicle/.github/workflows/publish.yml`.

The automated path is:

1. Push to `main` in `../CodeChronicle`.
2. GitHub Actions runs Django checks and tests.
3. GitHub Actions pushes `ghcr.io/iskanderblue/codechroniclenet:latest` and `ghcr.io/iskanderblue/codechroniclenet:<git-sha>`.
4. GitHub Actions authenticates to GCP with OIDC.
5. GitHub Actions connects to `codechroniclenet-vm` through IAP and runs the VM-local deploy script.
6. The new container starts, runs `migrate` and `collectstatic`, and serves traffic.
7. GitHub Actions smoke-tests `https://app.<domain>/api/health`.

No `terraform apply` is needed unless you're changing infrastructure (VM size, firewall rules, secrets, etc.).

### Manual fallback

If the workflow is unavailable, you can still trigger the same reset-less deploy path manually:

```bash
gcloud compute ssh codechroniclenet-vm --zone=us-central1-a --tunnel-through-iap --command="sudo bash /home/codechroniclenet/deploy-web.sh ghcr.io/iskanderblue/codechroniclenet:latest"
```

To roll back manually, pass a previously published SHA tag instead of `latest`.
