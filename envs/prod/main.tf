data "google_secret_manager_secret_version" "django_secret_key" {
  secret  = "django-secret-key"
  project = var.gcp_project_id
}

data "google_secret_manager_secret_version" "cf_origin_cert" {
  secret  = "cf-origin-cert"
  project = var.gcp_project_id
}

data "google_secret_manager_secret_version" "cf_origin_key" {
  secret  = "cf-origin-key"
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
}

module "cloudflare" {
  source = "../../modules/cloudflare"

  domain    = var.domain
  public_ip = module.compute.public_ip
}
