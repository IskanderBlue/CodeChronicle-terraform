# Repository Guidelines

## Scope & Deployment Target
This repo provisions cloud infrastructure for the CodeChronicle Django app. The app expects PostgreSQL, object storage for maps (currently S3-compatible), and standard web hosting (e.g., EC2/ALB). While AWS is the default assumption, keep modules provider-agnostic where practical so alternatives (GCP/Azure) can be swapped in with minimal churn.

## Project Structure & Module Organization
The repo is still empty, so establish a consistent layout as you add Terraform:
- `modules/` reusable components (network, compute, db, storage, iam, observability).
- `envs/` per-environment stacks (e.g., `envs/dev`, `envs/prod`) that wire modules together.
- `examples/` minimal usage for modules.
- `scripts/` helper automation (if needed).
Keep environment-specific values in `envs/*/*.tfvars` and avoid committing secrets.

## Build, Test, and Development Commands
Use standard Terraform commands:
- `terraform fmt -recursive` to format.
- `terraform init` to set up backend/providers.
- `terraform validate` for static checks.
- `terraform plan -var-file envs/dev/dev.tfvars` to preview changes.
- `terraform apply -var-file envs/dev/dev.tfvars` to deploy.

## Coding Style & Naming Conventions
- 2-space indentation in `.tf` files.
- `snake_case` for variables/outputs/modules.
- `kebab-case` for resource names where allowed.
If you add linting (e.g., `tflint` or `checkov`), document the exact command here.

## Testing Guidelines
No test harness yet. At minimum, run `terraform validate` and a `plan` before PRs. If you add Terratest, place Go tests under `tests/` and name them `*_test.go`.

## Commit & Pull Request Guidelines
No commit history exists in this repo, but CodeChronicle uses Conventional Commits. Prefer:
- `feat:`, `fix:`, `chore:`, `docs:`
PRs should include:
- Summary of changes and linked issue (if any).
- `terraform plan` output (or instructions to reproduce).
- Notes on data migrations or downtime risk.

## Security & Configuration Tips
- Use a remote backend (e.g., S3 + DynamoDB) with encryption and locking.
- Keep secrets in a manager (SSM/Secrets Manager) and inject via env vars.
- Map storage should remain private; use signed URLs or restricted IAM access.
- Track required app env vars in the CodeChronicle `.env.example`.
