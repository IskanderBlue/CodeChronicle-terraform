data "cloudflare_zone" "this" {
  filter = {
    name = var.domain
  }
}

resource "cloudflare_dns_record" "app" {
  for_each = toset(var.subdomains)

  zone_id = data.cloudflare_zone.this.id
  name    = "${each.value}.${var.domain}"
  content = var.public_ip
  type    = "A"
  proxied = true
  ttl     = 1
}

# Preserve the pre-existing single (app) record when adopting for_each, so it
# is re-keyed in state rather than destroyed and recreated.
moved {
  from = cloudflare_dns_record.app
  to   = cloudflare_dns_record.app["app"]
}

# TLS mode is set to Full (strict) manually in the Cloudflare dashboard.
# The free plan does not support changing this via API.

# ---------------------------------------------------------------------------
# Asset storage: R2 bucket + edge Worker that serves the CCM-mirrored asset
# trees on the app origin. The Worker keeps the root-relative /documents/,
# /amended/, /laws/ paths baked into stored version HTML resolving verbatim,
# so no HTML rewrite is needed. See asset-proxy.js for the request handler.
#
# Manual prerequisites (not creatable on the free plan / not S3-key-minting):
#   * The cloudflare_api_token used by this provider needs Workers Scripts:Edit
#     and Workers R2 Storage:Edit on the account.
#   * R2 *S3 access keys* for the upload side (Django sync_images --backend r2)
#     are minted under R2 > Manage R2 API Tokens in the dashboard and stored as
#     secrets — the serving Worker uses the binding below and needs no keys.
# ---------------------------------------------------------------------------
resource "cloudflare_r2_bucket" "assets" {
  account_id    = var.account_id
  name          = var.asset_bucket_name
  location      = var.asset_bucket_location
  storage_class = "Standard"
}

resource "cloudflare_workers_script" "asset_proxy" {
  account_id  = var.account_id
  script_name = "codechronicle-asset-proxy"
  content     = file("${path.module}/asset-proxy.js")
  main_module = "asset-proxy.js"

  bindings = [{
    name        = "ASSETS"
    type        = "r2_bucket"
    bucket_name = cloudflare_r2_bucket.assets.name
  }]

  observability = {
    enabled = true
  }
}

# One route per (subdomain, prefix) pair — assets must resolve on whichever
# host served the page. The Worker short-circuits these paths at the edge,
# ahead of the nginx/Django origin.
locals {
  asset_routes = {
    for pair in setproduct(var.subdomains, var.asset_path_prefixes) :
    "${pair[0]}-${pair[1]}" => { subdomain = pair[0], prefix = pair[1] }
  }
}

resource "cloudflare_workers_route" "assets" {
  for_each = local.asset_routes

  zone_id = data.cloudflare_zone.this.id
  pattern = "${each.value.subdomain}.${var.domain}/${each.value.prefix}/*"
  script  = cloudflare_workers_script.asset_proxy.script_name
}
