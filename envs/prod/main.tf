data "google_secret_manager_secret_version" "django_secret_key" {
  secret  = "django_secret_key"
  project = var.gcp_project_id
}

data "google_secret_manager_secret_version" "cf_origin_cert" {
  secret  = "cf_origin_cert"
  project = var.gcp_project_id
}

data "google_secret_manager_secret_version" "cf_origin_key" {
  secret  = "cf_origin_key"
  project = var.gcp_project_id
}

module "network" {
  source = "../../modules/network"

  project_id      = var.gcp_project_id
  region          = var.gcp_region
  admin_ssh_cidrs = var.admin_ssh_cidrs
}

module "neon" {
  source = "../../modules/neon"
}

module "secrets" {
  source = "../../modules/secrets"

  project_id = var.gcp_project_id
  secrets = {
    database_url      = module.neon.connection_uri
    django_secret_key = data.google_secret_manager_secret_version.django_secret_key.secret_data
    cf_origin_cert    = data.google_secret_manager_secret_version.cf_origin_cert.secret_data
    cf_origin_key     = data.google_secret_manager_secret_version.cf_origin_key.secret_data
  }
}

module "compute" {
  source = "../../modules/compute"

  project_id   = var.gcp_project_id
  region       = var.gcp_region
  zone         = var.gcp_zone
  machine_type = var.machine_type
  network_name = module.network.network_name
  subnet_name  = module.network.subnet_name
  secret_names = module.secrets.secret_names
  app_image    = var.app_image
  domain       = var.domain
  subdomains   = var.subdomains
}

module "cloudflare" {
  source = "../../modules/cloudflare"

  domain     = var.domain
  public_ip  = module.compute.public_ip
  account_id = var.cloudflare_account_id
  subdomains = var.subdomains
  # Must equal ASSET_SIGNING_KEY in the app_runtime_secrets bundle. Changing it
  # here alone makes every page scan 403; change both, in either order, and
  # accept a short window where the scans refuse rather than a window where
  # they are open.
  asset_signing_key = var.asset_signing_key
}
