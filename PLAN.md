# CodeChronicle Deployment Plan (GCP + Cloudflare + Neon)

## Summary
Provision a minimal, low-cost GCP deployment with a single Compute Engine VM running Dockerized Django, Cloudflare managing DNS + TLS (proxy + Origin CA), and Neon as managed Postgres via the `kislerdm/neon` Terraform provider. This plan avoids load balancers initially and explicitly accepts brief deployment windows while the product is in testing.

## Assumptions & Defaults
- Cloud: GCP, region `us-central1`, prod only.
- Compute: Single VM (no load balancer).
- Domain: Cloudflare DNS + proxy, Origin CA cert, Full (strict) mode.
- DB: Neon, managed via `kislerdm/neon` Terraform provider.
- Map data storage: Postgres (not S3).
- Secrets: GCP Secret Manager.

## Architecture Overview
- Cloudflare: DNS zone + proxied `A` record for `app.<domain>` to GCE static IP; SSL/TLS set to Full (strict) using Origin CA cert installed on VM.
- GCP:
  - VPC + subnet.
  - Firewall: allow `443` from Cloudflare IP ranges only, `22` from admin IPs.
  - Static external IP.
  - Compute Engine VM (start with `e2-micro`).
  - Service account with Secret Manager access.
- Neon: project + database + role created in Terraform; connection string stored in Secret Manager.

## Terraform Structure (CodeChronicle-terraform)
- `modules/network/` VPC + subnet + firewall rules.
- `modules/compute/` VM, static IP, service account, startup script.
- `modules/secrets/` Secret Manager secrets.
- `modules/neon/` Neon project/db/role + outputs.
- `modules/cloudflare/` Zone lookup + DNS record + SSL/TLS settings.
- `envs/prod/` wires modules together and defines variables.

## Public Interfaces / Outputs
- Terraform outputs:
  - `public_ip`
  - `domain_name`
  - `neon_connection_string` (sensitive)
  - `cloudflare_zone_id`
- New app-level interface:
  - New Django model `CodeMap` (name TBD) storing `code_name` (unique) and JSON payload.

## App Changes Required (CodeChronicle)
- added to CodeChronicle TODO.

## Deployment Flow
1. Terraform apply creates:
   - VPC/subnet/firewall
   - Secret Manager secrets (DB URL, Django SECRET_KEY, CF origin cert/key)
   - VM + static IP
   - Cloudflare DNS record
   - Neon project/db/role (provider)
2. VM startup script:
   - Install Docker + Docker Compose.
   - Pull app repo or image.
   - Fetch secrets from Secret Manager.
   - Write `.env` for container.
   - Start services with `docker compose up -d`.
3. Post-deploy:
   - Run `python manage.py migrate`.
   - Run `python manage.py load_maps` to seed Postgres with code maps.
   - Smoke test `/<health>` (or create one if needed).

## Testing & Validation
- `terraform fmt`, `terraform validate`, `terraform plan`.
- Verify Cloudflare proxying and TLS mode (Full strict).
- Confirm firewall only allows Cloudflare IP ranges.
- Django: run migrations + smoke test endpoints.

## Risks & Mitigations
- No HA / deployment downtime: acceptable for testing; document expected brief downtime.
- Cloudflare origin cert misconfig: ensure Full (strict) and origin cert installed.
- Provider upgrades: pin provider versions and avoid `terraform init -upgrade` in CI for Neon.

## Next Steps (Implementation Order)
1. Scaffold Terraform repo layout + providers (GCP, Cloudflare, Neon).
2. Implement GCP network + VM + secrets.
3. Implement Cloudflare DNS + TLS settings.
4. Implement Neon resources + outputs.
5. Add Dockerized deployment for CodeChronicle.
6. Add DB-backed map storage + data loader.
7. End-to-end deploy + smoke test.
