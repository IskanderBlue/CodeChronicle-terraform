variable "project_name" {
  type    = string
  default = "codechroniclenet"
}

variable "database_name" {
  type    = string
  default = "codechroniclenet"
}

# Three roles, because one role cannot be both least-privileged and able to
# run a migration.  The names are the ones the security hardening rollout
# created; changing one here creates a new role rather than renaming the old
# one, and the new role holds no grants.
variable "owner_role_name" {
  type    = string
  default = "codechroniclenet_app"
}

variable "app_role_name" {
  type    = string
  default = "cc_app"
}

variable "read_only_role_name" {
  type    = string
  default = "cc_ro"
}

variable "region" {
  type    = string
  default = "aws-us-east-1"
}
