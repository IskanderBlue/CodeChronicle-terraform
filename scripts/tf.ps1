# PowerShell equivalent of tf.sh
# Usage: .\scripts\tf.ps1 init
#        .\scripts\tf.ps1 plan
#        .\scripts\tf.ps1 apply

$ErrorActionPreference = "Stop"

$env:TF_VAR_cloudflare_api_token = (gcloud secrets versions access latest --secret=cloudflare-api-token).Trim()
$env:TF_VAR_neon_api_key = (gcloud secrets versions access latest --secret=neon-api-key).Trim()

$EnvDir = Join-Path $PSScriptRoot "..\envs\prod"

terraform -chdir="$EnvDir" @args -var-file="$EnvDir\prod.tfvars"
