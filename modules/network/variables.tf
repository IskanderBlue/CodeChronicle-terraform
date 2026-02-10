variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "admin_ssh_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to SSH into the VM"
  default     = []
}
