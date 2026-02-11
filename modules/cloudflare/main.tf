data "cloudflare_zone" "this" {
  filter = {
    name = var.domain
  }
}

resource "cloudflare_dns_record" "app" {
  zone_id = data.cloudflare_zone.this.id
  name    = "${var.subdomain}.${var.domain}"
  content = var.public_ip
  type    = "A"
  proxied = true
  ttl     = 1
}

# TLS mode is set to Full (strict) manually in the Cloudflare dashboard.
# The free plan does not support changing this via API.
