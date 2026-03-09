# Fully Automated Luxury Deployments

This is the full plan to move CodeChronicle from:

- GitHub Actions only publishing `ghcr.io/iskanderblue/codechroniclenet:latest`
- manual or VM-reset deployment

to:

- GitHub Actions builds and publishes immutable images
- GitHub Actions authenticates to GCP without a JSON key
- GitHub Actions reaches the production VM through IAP + OS Login
- GitHub Actions performs a reset-less deploy by recreating only the app container
- migrations continue to run automatically on container startup
- production gets a post-deploy smoke test and an easy rollback path

This plan covers changes needed in both repos:

- this repo: `CodeChronicleTerraform`
- sibling app repo: `../CodeChronicle`

## Current State

### Terraform repo

- Production infra is one GCE VM, `codechroniclenet-vm`, in project `codechronicle-487104`, zone `us-central1-a`.
- The VM currently bootstraps Docker, writes `/home/codechroniclenet/.env`, fetches Cloudflare certs from Secret Manager, pulls the app image, and starts `codechroniclenet-web` and `codechroniclenet-nginx` in `modules/compute/startup.sh`.
- SSH is currently allowed only from `admin_ssh_cidrs` in `modules/network/main.tf`.

### App repo

- `../CodeChronicle/.github/workflows/publish.yml` only builds and pushes `ghcr.io/iskanderblue/codechroniclenet:latest`.
- `../CodeChronicle/scripts/entrypoint.sh` already runs:
  - `python manage.py migrate --noinput`
  - `python manage.py collectstatic --noinput`
- That means migrations are already automatic whenever a fresh app container starts.

## Target End State

After a push to `main` in `../CodeChronicle`:

1. GitHub Actions runs checks and builds the app image.
2. GitHub Actions pushes both:
   - `ghcr.io/iskanderblue/codechroniclenet:latest`
   - `ghcr.io/iskanderblue/codechroniclenet:<git-sha>`
3. GitHub Actions authenticates to GCP via OIDC and Workload Identity Federation.
4. GitHub Actions connects to `codechroniclenet-vm` over IAP.
5. GitHub Actions pulls the SHA-tagged image on the VM.
6. GitHub Actions recreates only `codechroniclenet-web`.
7. The container entrypoint runs migrations and `collectstatic` automatically.
8. GitHub Actions smoke-tests `https://app.codechronicle.ca/`.
9. If needed, GitHub Actions can redeploy a previous SHA tag as a rollback.

No VM reset. No long-lived GCP key in GitHub. No public SSH exposure.

## Repo 1: Changes Needed In `CodeChronicleTerraform`

### 1. Add IAP SSH firewall access

Why:

- GitHub-hosted runners will reach the VM through IAP.
- IAP still needs TCP 22 open from Google's IAP forwarding range.
- Current Terraform only allows port 22 from `admin_ssh_cidrs`.

Change:

- Update `modules/network/main.tf` to add a second SSH firewall rule:
  - allow `tcp:22`
  - source range `35.235.240.0/20`
  - target tag `codechroniclenet-web`

Suggested resource:

- `google_compute_firewall.allow-ssh-iap`

Result:

- SSH remains closed to the public internet.
- Only Google IAP can reach port 22.

### 2. Enable OS Login on the VM through Terraform

Why:

- Reset-less deploys should use IAM-controlled SSH access.
- OS Login is the cleanest way to let the GitHub deploy identity log in without managing SSH keys manually.

Change:

- Update `modules/compute/main.tf` metadata to include:
  - `enable-oslogin = "TRUE"`
  - `block-project-ssh-keys = "TRUE"`

Result:

- SSH access becomes IAM-governed.
- Project-wide legacy SSH keys are not relied on for this instance.

### 3. Stop relying on VM boot for normal app deploys

Why:

- Right now `modules/compute/startup.sh` both bootstraps the machine and performs a full app deploy.
- That is why `gcloud compute instances reset` works as a deploy mechanism.
- For cleaner deploys, boot-time bootstrap and release-time deployment should be separated.

Change:

- Keep `modules/compute/startup.sh` responsible for first-boot host setup only:
  - start Docker
  - write `/home/codechroniclenet/.env`
  - fetch `origin.pem` and `origin-key.pem`
  - write `nginx.conf`
  - create the `staticfiles` volume
  - start or ensure `codechroniclenet-nginx` exists
- Remove the normal-release assumption that startup script is what updates the app image.

Recommended approach:

- Add a VM-local deploy script path such as `/home/codechroniclenet/deploy-web.sh`
- Have Terraform create that script from a template
- GitHub Actions will call that script over IAP SSH

Result:

- Terraform owns machine bootstrap.
- The app repo owns app releases.

### 4. Add a VM-local deploy script template

Why:

- The GitHub workflow should not contain a giant fragile inline SSH command.
- A VM-local script is easier to review, repeat, and debug.

Change:

- Add a template in this repo, likely under `modules/compute/`, for a script that:
  - accepts an image tag or full image reference
  - runs `docker pull`
  - stops and removes `codechroniclenet-web`
  - starts a fresh `codechroniclenet-web`
  - uses `/home/codechroniclenet/.env`
  - mounts `staticfiles:/app/staticfiles`
  - keeps `--network host`

The script should use the same runtime contract already used in `modules/compute/startup.sh`, minus the nginx handling.

Recommended command shape inside the script:

```bash
docker pull "$IMAGE"
docker rm -f codechroniclenet-web 2>/dev/null || true
docker run -d \
  --name codechroniclenet-web \
  --restart unless-stopped \
  --env-file /home/codechroniclenet/.env \
  --network host \
  -v staticfiles:/app/staticfiles \
  "$IMAGE"
```

Result:

- Deploy logic is reusable and versionable.
- Actions only needs to call one script with one image tag.

### 5. Keep runtime secret loading as-is, but verify it explicitly

Why:

- The VM `.env` file only writes `GCP_PROJECT_ID`, `DJANGO_SETTINGS_MODULE`, and `ALLOWED_HOSTS`.
- The app resolves `database_url` and `django_secret_key` from Secret Manager at runtime.
- That is fine if the container can authenticate with the VM's service account from inside Docker.

Change:

- No required Terraform change if runtime secret loading is already working.
- But document this contract clearly in `DEPLOY.md` and/or module comments.

Verification:

- Confirm a freshly recreated app container can still read Secret Manager and boot without the VM reset path.

### 6. Update docs in this repo

Change:

- Update `DEPLOY.md` so the standard deploy path is no longer VM reset or manual SSH container replacement.
- Point it to the app repo's GitHub Actions workflow as the primary deploy path.
- Keep a manual fallback command documented for emergencies.

### 7. Optional but strongly recommended: pin `app_image` less centrally

Why:

- Terraform currently defaults `app_image` to `ghcr.io/iskanderblue/codechroniclenet:latest` in `envs/prod/variables.tf`.
- In the long term, app deploys should not depend on Terraform changing image tags.

Change:

- Keep Terraform responsible only for the image repository default.
- Let the runtime deploy script receive the exact SHA tag from GitHub Actions.

Clarification:

- `terraform apply` is not required for routine app deploys just because `latest` changes in GHCR.
- Today, `latest` gets picked up because a VM reset reruns `startup.sh`, which does `docker pull ${app_image}`.
- In the reset-less design, the workflow itself performs `docker pull` and then recreates the `web` container.
- That means `latest` can still be updated without Terraform, but the cleaner deploy path is to pull a specific SHA tag from the workflow.
- So this change is not about making `terraform apply` unnecessary; it already is unnecessary for app-only releases. This change is about making releases explicit, reproducible, and rollback-friendly.

Result:

- No `terraform apply` needed for each app release.
- No dependence on VM reboot behavior to consume a newly pushed image.

## Repo 2: Changes Needed In `../CodeChronicle`

### 1. Replace publish-only workflow with build-publish-deploy

Current file:

- `../CodeChronicle/.github/workflows/publish.yml`

Change:

- Expand this workflow from one job to a full release pipeline.

Recommended shape:

- Trigger:
  - `push` on `main`
  - optionally `workflow_dispatch` for manual redeploy / rollback
- Jobs:
  - `build-and-push`
  - `deploy-production`
  - optionally `smoke-test` as a separate dependent job

### 2. Add OIDC-based GCP auth to the workflow

Why:

- This avoids storing a GCP service account key in GitHub.

Change:

- Add workflow permissions:

```yaml
permissions:
  contents: read
  packages: write
  id-token: write
```

- Add auth steps using:
  - `google-github-actions/auth@v2`
  - `google-github-actions/setup-gcloud@v2`

Non-secret values needed in the workflow:

- `codechronicle-487104`
- `471007069115`
- `us-central1-a`
- `codechroniclenet-vm`
- `github-actions-deploy@codechronicle-487104.iam.gserviceaccount.com`
- `projects/471007069115/locations/global/workloadIdentityPools/github-actions-pool/providers/github-provider`

These can be hardcoded in the workflow or stored as GitHub repository variables.

### 3. Publish immutable image tags

Why:

- Deploying only `:latest` makes rollback and auditability worse.

Change:

- Keep pushing `:latest` for convenience.
- Also push `:${{ github.sha }}`.

Example tags:

- `ghcr.io/iskanderblue/codechroniclenet:latest`
- `ghcr.io/iskanderblue/codechroniclenet:${{ github.sha }}`

Result:

- Production deploys can target an exact image.
- Rollback becomes a one-line redeploy to a previous SHA.

What that means in practice:

- Normal deploys still happen by pushing to `main`.
- Rollback is a manual `workflow_dispatch` run where you provide a previously published SHA tag.
- The deploy logic stays the same; only the image tag changes.

Example rollback command at the VM layer:

```bash
sudo bash /home/codechroniclenet/deploy-web.sh ghcr.io/iskanderblue/codechroniclenet:<previous-sha>
```

Example rollback trigger at the GitHub Actions layer:

- run the workflow manually with `deploy_tag=<previous-sha>`

That is the sense in which rollback is a one-line redeploy: one image reference, same deploy path.

### 4. Add the production deploy job

Why:

- This is the missing automation step today.

Change:

- Add a job that runs after the image push succeeds.
- Authenticate to GCP.
- SSH to the VM through IAP.
- Call the VM-local deploy script with the SHA-tagged image.

Recommended remote command shape:

```bash
sudo bash /home/codechroniclenet/deploy-web.sh ghcr.io/iskanderblue/codechroniclenet:${GITHUB_SHA}
```

If you choose not to create a VM-local script, the workflow can inline the Docker commands, but that is less maintainable.

### 5. Keep migrations automatic via the existing container entrypoint

Why:

- This is already implemented correctly for a single-instance deployment.

Current file:

- `../CodeChronicle/scripts/entrypoint.sh`

Current behavior:

- `migrate --noinput`
- `collectstatic --noinput`
- start Gunicorn

Change:

- No functional change required unless you want additional startup logging.

Important note:

- This pattern is acceptable for the current single-VM deployment.
- If you later move to multiple concurrent app replicas, migrations should probably move to a dedicated release step.

### 6. Add a smoke test to the workflow

Why:

- The workflow should fail visibly if the new image boots but the site is not healthy.

Change:

- Add a post-deploy HTTP check against:
  - `https://app.codechronicle.ca/`
  - or better, a dedicated health endpoint if the app has one

Recommendation:

- If no dedicated health endpoint exists, add one in the app repo.
- Keep it lightweight and database-aware enough to catch broken boots.

Recommended health endpoint behavior:

- Path: `/healthz/`
- Method: `GET`
- Returns `200` with a small JSON body such as:

```json
{"status":"ok"}
```

- Checks:
  - the Django app is booted
  - a simple database query succeeds
- Does not require auth
- Does not do expensive work or depend on external APIs like Anthropic

Practical Django shape:

- a tiny view that runs something like `SELECT 1`
- URL mounted at `/healthz/`
- workflow uses `curl -fsS https://app.codechronicle.ca/healthz/`

### 7. Add manual rollback support

Why:

- SHA-tagged images make rollback cheap and safe.

Change:

- Add `workflow_dispatch` inputs such as:
  - `deploy_tag`
  - `rollback_tag`
- Reuse the same deploy job, just changing the image tag passed to the VM-local script.

Result:

- Rollback is a redeploy, not a VM reset.

### 8. Optional: add a pre-deploy validation step

Why:

- Build success does not guarantee app correctness.

Recommended additions in `build-and-push`:

- Django checks
- tests, if present
- maybe `python manage.py check --deploy`

Recommended first-pass implementation:

- install Python dependencies
- run `python manage.py check`
- run `python manage.py check --deploy`
- run the test suite if it exists and is stable in CI
- only build and push if those steps pass

Example job shape:

```yaml
- name: Set up Python
  uses: actions/setup-python@v5
  with:
    python-version: '3.12'

- name: Install dependencies
  run: pip install -r requirements.txt

- name: Django checks
  run: |
    python manage.py check
    python manage.py check --deploy
```

This should be included in the first implementation unless there is a concrete reason the app cannot run checks in CI yet.

## GCP / GitHub Setup Needed Outside The Repos

This is already documented in `GITHUB_ACTIONS_GCP_AUTH.md`, but it is part of the full plan.

### GCP

- Create service account:
  - `github-actions-deploy@codechronicle-487104.iam.gserviceaccount.com`
- Grant narrow roles:
  - `roles/compute.viewer`
  - `roles/iap.tunnelResourceAccessor`
  - `roles/compute.osAdminLogin`
- Create workload identity pool:
  - `github-actions-pool`
- Create GitHub OIDC provider:
  - `github-provider`
- Bind the `IskanderBlue/CodeChronicle` repo to the service account with `roles/iam.workloadIdentityUser`

### GitHub

No new long-lived secrets are required if you use OIDC correctly.

You only need workflow config values for:

- project id
- project number
- zone
- instance name
- workload identity provider name
- service account email

These can be hardcoded or stored as repository variables.

## Recommended Implementation Order

### Phase 1: Terraform access groundwork

1. Add IAP SSH firewall rule in `modules/network/main.tf`.
2. Enable OS Login and block project SSH keys in `modules/compute/main.tf`.
3. Apply Terraform.

Success check:

- `gcloud compute ssh codechroniclenet-vm --zone us-central1-a --project codechronicle-487104 --tunnel-through-iap` works for an authorized identity.

### Phase 2: GCP federation setup

1. Create the deploy service account.
2. Create the workload identity pool and provider.
3. Grant the repo impersonation binding.

Success check:

- a test GitHub workflow can authenticate and run `hostname` on the VM through IAP.

### Phase 3: VM-local deploy script

1. Add a deploy script template to Terraform.
2. Have the VM write it to `/home/codechroniclenet/deploy-web.sh`.
3. Apply Terraform.

Success check:

- running the script manually on the VM with a known image tag recreates `codechroniclenet-web` successfully.

### Phase 4: App workflow upgrade

1. Update `../CodeChronicle/.github/workflows/publish.yml`.
2. Push `latest` and SHA tags.
3. Add the deploy job.
4. Add the smoke test.

Success check:

- a push to `main` publishes an image, recreates only the web container, runs migrations automatically, and leaves nginx untouched.

### Phase 5: Rollback and polish

1. Add `workflow_dispatch` rollback support.
2. Add a dedicated health endpoint if missing.
3. Update docs in both repos.
4. As the final step, update `DEPLOY.md` so it reflects the finished automated workflow rather than the old manual/reset-based process.

## Concrete File-Level Change List

### In this repo

- `modules/network/main.tf`
  - add IAP SSH firewall rule
- `modules/compute/main.tf`
  - enable OS Login metadata
  - block legacy project SSH keys
  - optionally template a deploy script onto the VM
- `modules/compute/startup.sh`
  - reduce responsibility to host bootstrap + nginx/static volume setup
  - stop treating VM reboot as the normal app release path
- `DEPLOY.md`
  - rewrite app deploy section around GitHub Actions
- `GITHUB_ACTIONS_GCP_AUTH.md`
  - already added; keep aligned with actual implementation

### In `../CodeChronicle`

- `../CodeChronicle/.github/workflows/publish.yml`
  - add `id-token: write`
  - authenticate to GCP
  - push SHA-tagged image
  - deploy over IAP SSH
  - smoke test production
  - optionally add rollback dispatch inputs
- `../CodeChronicle/scripts/entrypoint.sh`
  - likely no change needed
- optionally add a health endpoint in the Django app if one does not already exist

## What Does Not Need To Change

- The single-VM architecture can stay as-is.
- The app can keep using Secret Manager at runtime.
- The auto-migrate startup behavior can stay as-is for now.
- Cloudflare and Neon do not need release-path changes for reset-less deploys.

## Risks And Guardrails

### 1. SSH access path risk

- If OS Login or the IAP firewall rule is misconfigured, deploys will fail before reaching the VM.

Guardrail:

- verify IAP SSH manually before changing the workflow

### 2. Runtime Secret Manager access risk

- If the container cannot use the VM service account from inside Docker, the app may fail to boot on recreated containers.

Guardrail:

- explicitly test a reset-less container recreation before cutting over CI deploys

### 3. Migration-on-start risk

- Fine on one VM, riskier on many replicas.

Guardrail:

- keep it for now, revisit only if deployment topology changes

### 4. `latest` drift risk

- Using only `latest` makes it harder to know what is running.

Guardrail:

- deploy by SHA, keep `latest` only as a convenience tag

## The Short Version

To get luxury deployments, change three things:

1. In Terraform, allow IAP SSH and enable OS Login.
2. In GCP/GitHub, set up OIDC-based federation for the `CodeChronicle` workflow.
3. In `../CodeChronicle/.github/workflows/publish.yml`, turn publish-only into publish-and-deploy using a VM-local `deploy-web.sh` script and SHA-tagged images.

That gives you automated, reset-less, migration-running, smoke-tested deployments on the existing infra.
