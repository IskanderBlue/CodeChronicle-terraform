variable "gcp_project_id" {
  type = string
}

variable "gcp_region" {
  type    = string
  default = "us-central1"
}

variable "gcp_zone" {
  type    = string
  default = "us-central1-a"
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare account ID that owns the R2 bucket and Worker."
}

variable "neon_api_key" {
  type      = string
  sensitive = true
}

variable "domain" {
  type = string
}

variable "subdomains" {
  type        = list(string)
  default     = ["app", "www"]
  description = "Host subdomains the app serves on (DNS records, asset routes, ALLOWED_HOSTS)."
}

variable "admin_ssh_cidrs" {
  type    = list(string)
  default = []
}

variable "app_image" {
  type    = string
  default = "ghcr.io/iskanderblue/codechroniclenet:latest"
}

variable "machine_type" {
  type    = string
  default = "e2-micro"
}
