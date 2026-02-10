#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_DIR="$SCRIPT_DIR/../envs/prod"

export TF_VAR_cloudflare_api_token=$(gcloud secrets versions access latest --secret=cloudflare-api-token)
export TF_VAR_neon_api_key=$(gcloud secrets versions access latest --secret=neon-api-key)

terraform -chdir="$ENV_DIR" "$@" -var-file="$ENV_DIR/prod.tfvars"
