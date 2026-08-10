output "public_ip" {
  value = module.compute.public_ip
}

output "domain_name" {
  value = module.cloudflare.domain_name
}

# Named by role, not "the" connection string.  One name for three DSNs is how
# the owner role ends up on the request path.
output "neon_app_uri" {
  value     = module.neon.app_connection_uri
  sensitive = true
}

output "neon_owner_uri" {
  value     = module.neon.owner_connection_uri
  sensitive = true
}

output "neon_read_only_uri" {
  value     = module.neon.read_only_connection_uri
  sensitive = true
}

# Read by `envs/prod-grants` through `terraform_remote_state`.  One object
# rather than six outputs, so a reader sees that these belong together and
# that the whole thing carries a password.
output "neon_grant_inputs" {
  value = {
    host           = module.neon.database_host
    database       = module.neon.database_name
    owner_role     = module.neon.owner_role_name
    owner_password = module.neon.owner_role_password
    app_role       = module.neon.app_role_name
    read_only_role = module.neon.read_only_role_name
  }
  sensitive = true
}

output "cloudflare_zone_id" {
  value = module.cloudflare.zone_id
}

output "asset_bucket_name" {
  value = module.cloudflare.asset_bucket_name
}
