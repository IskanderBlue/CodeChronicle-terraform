output "zone_id" {
  value = data.cloudflare_zone.this.id
}

output "domain_name" {
  value = "${var.subdomain}.${var.domain}"
}

output "record_id" {
  value = cloudflare_dns_record.app.id
}
