# GitHub Actions GCP Auth Setup

This sets up `../CodeChronicle` GitHub Actions to deploy to the existing production VM without storing a long-lived GCP key in GitHub.

It uses:

- GitHub OIDC
- GCP Workload Identity Federation
- a dedicated deploy service account
- IAP + OS Login for reset-less VM access

## Production Values

- GCP project ID: `codechronicle-487104`
- GCP project number: `471007069115`
- Region: `us-central1`
- Zone: `us-central1-a`
- VM name: `codechroniclenet-vm`
- Domain: `codechronicle.ca`
- App hostname: `app.codechronicle.ca`

## What This Gives GitHub Actions

After this setup, the `CodeChronicle` repo workflow can:

- authenticate to GCP without a JSON key
- SSH to `codechroniclenet-vm` through IAP
- run Docker commands on the VM
- redeploy only the `web` container instead of resetting the whole VM

This guide is narrowed for reset-less deploys only. It does not grant reboot or broad instance-admin permissions.

## 1. Create the deploy service account

Run:

```bash
gcloud iam service-accounts create github-actions-deploy --project codechronicle-487104 --display-name "GitHub Actions deploy"
```

The service account email will be:

```text
github-actions-deploy@codechronicle-487104.iam.gserviceaccount.com
```

## 1.5 Enable the required GCP APIs

These APIs must be enabled before GitHub Actions can authenticate and SSH through IAP.

```bash
gcloud services enable iamcredentials.googleapis.com compute.googleapis.com iap.googleapis.com --project codechronicle-487104
```

Notes:

- `iamcredentials.googleapis.com` is required for Workload Identity Federation to impersonate the deploy service account.
- `compute.googleapis.com` is required for VM access.
- `iap.googleapis.com` is required for `--tunnel-through-iap`.

## 2. Grant the minimum project-level IAM roles

These roles let GitHub Actions discover the instance, connect through IAP, and use OS Login. They are intentionally narrow for container-only deploys.

```bash
gcloud projects add-iam-policy-binding codechronicle-487104 --member="serviceAccount:github-actions-deploy@codechronicle-487104.iam.gserviceaccount.com" --role="roles/compute.viewer"

gcloud projects add-iam-policy-binding codechronicle-487104 --member="serviceAccount:github-actions-deploy@codechronicle-487104.iam.gserviceaccount.com" --role="roles/iap.tunnelResourceAccessor"

gcloud projects add-iam-policy-binding codechronicle-487104 --member="serviceAccount:github-actions-deploy@codechronicle-487104.iam.gserviceaccount.com" --role="roles/compute.osAdminLogin"

gcloud iam service-accounts add-iam-policy-binding codechroniclenet-vm@codechronicle-487104.iam.gserviceaccount.com --project codechronicle-487104 --member="serviceAccount:github-actions-deploy@codechronicle-487104.iam.gserviceaccount.com" --role="roles/iam.serviceAccountUser"
```

Notes:

- `roles/compute.viewer` lets the workflow resolve instance metadata.
- `roles/iap.tunnelResourceAccessor` lets the workflow tunnel SSH through Google instead of exposing SSH publicly.
- `roles/compute.osAdminLogin` allows sudo-capable OS Login access on the VM.
- `roles/iam.serviceAccountUser` on `codechroniclenet-vm@codechronicle-487104.iam.gserviceaccount.com` lets `gcloud compute ssh` act as the VM's attached service account.

Not included on purpose:

- `roles/compute.instanceAdmin.v1` is not needed for a reset-less deploy that only SSHes in and runs Docker commands.

## 3. Allow SSH only from Google's IAP tunnel range

IAP does not expose SSH publicly, but the VM still needs a firewall rule allowing TCP 22 from Google's IAP TCP forwarding range.

Your current Terraform allows SSH only from `admin_ssh_cidrs` in `modules/network/main.tf`, so GitHub Actions will not be able to connect over IAP until you add a second rule for `35.235.240.0/20`.

Run:

```bash
gcloud compute firewall-rules create allow-ssh-iap --project codechronicle-487104 --network codechroniclenet --direction INGRESS --action ALLOW --rules tcp:22 --source-ranges 35.235.240.0/20 --target-tags codechroniclenet-web
```

This still keeps SSH closed to the public internet; only IAP's Google-controlled source range can reach port 22.

## 4. Enable OS Login on the VM project

OS Login lets IAM control SSH access to the VM.

Set project metadata:

```bash
gcloud compute project-info add-metadata --project codechronicle-487104 --metadata enable-oslogin=TRUE
```

If you prefer to scope it only to this instance, use:

```bash
gcloud compute instances add-metadata codechroniclenet-vm \
  --project codechronicle-487104 \
  --zone us-central1-a \
  --metadata enable-oslogin=TRUE
```

Use one approach or the other, not both unless you want project-wide OS Login.

For a tighter setup, also disable legacy project SSH keys:

```bash
gcloud compute instances add-metadata codechroniclenet-vm \
  --project codechronicle-487104 \
  --zone us-central1-a \
  --metadata block-project-ssh-keys=TRUE
```

## 5. Create the workload identity pool

This is the GCP trust boundary for GitHub Actions.

```bash
gcloud iam workload-identity-pools create github-actions-pool --project codechronicle-487104 --location global --display-name "GitHub Actions pool"
```

## 6. Create the GitHub OIDC provider

This tells GCP how to trust tokens from GitHub Actions.

```bash
gcloud iam workload-identity-pools providers create-oidc github-provider --project codechronicle-487104 --location global --workload-identity-pool github-actions-pool --display-name "GitHub OIDC provider" --issuer-uri "https://token.actions.githubusercontent.com" --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" --attribute-condition "assertion.repository=='IskanderBlue/CodeChronicle' && assertion.ref=='refs/heads/main'"
```

Important:

- Provider conditions must reference GitHub's original OIDC claims such as `assertion.repository` and `assertion.ref`.
- Do not write the provider condition using mapped attributes like `attribute.repository`; that triggers the `INVALID_ARGUMENT` error you saw.
- If you do not want branch restrictions at the provider layer, omit `--attribute-condition` entirely and keep the restriction in IAM instead.

## 7. Allow the CodeChronicle repo to impersonate the service account

Replace `OWNER/REPO` with the actual GitHub repo path for the sibling app repo. Based on the image path, it is likely:

```text
IskanderBlue/CodeChronicle
```

Grant impersonation:

```bash
gcloud iam service-accounts add-iam-policy-binding github-actions-deploy@codechronicle-487104.iam.gserviceaccount.com --project codechronicle-487104 --role roles/iam.workloadIdentityUser --member "principalSet://iam.googleapis.com/projects/471007069115/locations/global/workloadIdentityPools/github-actions-pool/attribute.repository/IskanderBlue/CodeChronicle"
```

If you want to lock this down further immediately, bind only `refs/heads/main` by adding an IAM condition or by expanding the provider attribute conditions.

## 8. Verify IAP SSH access manually

Before wiring GitHub Actions, verify a human GCP login can reach the VM over IAP:

```bash
gcloud compute ssh codechroniclenet-vm --project codechronicle-487104 --zone us-central1-a --tunnel-through-iap
```

If this works, GitHub Actions can use the same access path once OIDC is configured.

## 9. Values the GitHub workflow needs

These are not secrets and should be stored as GitHub repository variables for `../CodeChronicle`.

```text
GCP_PROJECT_ID=codechronicle-487104
GCP_PROJECT_NUMBER=471007069115
GCP_ZONE=us-central1-a
GCP_INSTANCE_NAME=codechroniclenet-vm
GCP_SERVICE_ACCOUNT=github-actions-deploy@codechronicle-487104.iam.gserviceaccount.com
GCP_WIF_PROVIDER=projects/471007069115/locations/global/workloadIdentityPools/github-actions-pool/providers/github-provider
```

Recommended GitHub variable names:

- `GCP_PROJECT_ID`
- `GCP_ZONE`
- `GCP_INSTANCE_NAME`
- `GCP_SERVICE_ACCOUNT`
- `GCP_WIF_PROVIDER`

You do not need a GCP JSON key secret if you use this setup.

## 10. Minimum GitHub Actions permissions

In `../CodeChronicle/.github/workflows/publish.yml`, the workflow will need:

```yaml
permissions:
  contents: read
  packages: write
  id-token: write
```

`id-token: write` is what allows GitHub to mint the short-lived OIDC token for GCP.

## 11. Minimum GitHub Actions auth steps

The deploy job should authenticate like this:

```yaml
- uses: actions/checkout@v4

- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: projects/471007069115/locations/global/workloadIdentityPools/github-actions-pool/providers/github-provider
    service_account: github-actions-deploy@codechronicle-487104.iam.gserviceaccount.com

- uses: google-github-actions/setup-gcloud@v2
```

## 12. Test command from GitHub Actions path

Once the workflow is wired, a safe first test is:

```bash
gcloud compute ssh codechroniclenet-vm \
  --project codechronicle-487104 \
  --zone us-central1-a \
  --tunnel-through-iap \
  --command "hostname && sudo docker ps --format '{{.Names}}'"
```

If that works in Actions, the auth and permissions setup is complete.

Note:

- On Container-Optimized OS, scripts under `/home` may not be directly executable even with `chmod +x`.
- Call the deploy script as `sudo bash /home/codechroniclenet/deploy-web.sh ...` rather than executing it directly.

## 13. What comes next

After this file is done, the next app-repo change is to update `../CodeChronicle/.github/workflows/publish.yml` so it:

- builds and pushes the image
- authenticates to GCP with OIDC
- SSHes to the VM through IAP
- pulls the new image
- recreates `codechroniclenet-web`
- smoke tests `https://app.codechronicle.ca/`

## Troubleshooting

- `PERMISSION_DENIED` on auth: check the `roles/iam.workloadIdentityUser` binding and the GitHub repo path.
- `google-github-actions/auth` fails with `unauthorized_client` and `attribute condition`: check the provider condition uses the exact repo casing `IskanderBlue/CodeChronicle` and references `assertion.repository` / `assertion.ref`.
- `IAM Service Account Credentials API has not been used` or `SERVICE_DISABLED`: enable `iamcredentials.googleapis.com` in project `codechronicle-487104`.
- `gcloud compute ssh` fails before login: check `roles/iap.tunnelResourceAccessor`, OS Login metadata, and the `allow-ssh-iap` firewall rule for `35.235.240.0/20`.
- `gcloud compute ssh` fails with `iam.serviceAccounts.actAs`: grant `roles/iam.serviceAccountUser` on `codechroniclenet-vm@codechronicle-487104.iam.gserviceaccount.com` to `github-actions-deploy@codechronicle-487104.iam.gserviceaccount.com`.
- login works but Docker commands fail: the OS Login user on the VM may need Docker access or `sudo docker ...` should be used in the workflow.
- auth works locally but not in Actions: confirm the workflow includes `permissions: id-token: write`.
