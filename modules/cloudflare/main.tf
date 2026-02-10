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

resource "cloudflare_zone_setting" "tls" {
  zone_id    = data.cloudflare_zone.this.id
  setting_id = "ssl"
  value      = "strict"
}
