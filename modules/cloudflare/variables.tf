variable "domain" {
  type = string
}

variable "subdomains" {
  type        = list(string)
  default     = ["app", "www"]
  description = "All host subdomains the app serves on. Each gets a proxied A record and asset Worker routes."
}

variable "primary_subdomain" {
  type        = string
  default     = "www"
  description = "Canonical host used for the domain_name output. Must be one of subdomains."
}

variable "public_ip" {
  type = string
}

variable "account_id" {
  type        = string
  description = "Cloudflare account ID that owns the R2 bucket and Worker."
}

variable "asset_bucket_name" {
  type        = string
  default     = "codechronicle-assets-prod"
  description = "R2 bucket holding the CCM-mirrored asset trees (documents/, amended/, laws/)."
}

variable "asset_bucket_location" {
  type        = string
  default     = "wnam"
  description = "R2 location hint. wnam = western North America, nearest the audience."
}

variable "asset_path_prefixes" {
  type        = list(string)
  default     = ["documents", "amended", "laws"]
  description = "URL path prefixes served from R2 at the edge. Must match MIRRORED_PREFIXES in the Django app."
}
