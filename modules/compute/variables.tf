variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "machine_type" {
  type    = string
  default = "e2-micro"
}

variable "network_name" {
  type = string
}

variable "subnet_name" {
  type = string
}

variable "secret_names" {
  type = map(string)
}

variable "app_image" {
  type    = string
  default = ""
}
