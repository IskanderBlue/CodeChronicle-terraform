output "public_ip" {
  value = module.compute.public_ip
}

output "domain_name" {
  value = module.cloudflare.domain_name
}

output "neon_connection_string" {
  value     = module.neon.connection_uri
  sensitive = true
}

output "cloudflare_zone_id" {
  value = module.cloudflare.zone_id
}
