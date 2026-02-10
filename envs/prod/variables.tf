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

variable "neon_api_key" {
  type      = string
  sensitive = true
}

variable "domain" {
  type = string
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
