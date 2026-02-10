locals {
  secret_keys = nonsensitive(toset(keys(var.secrets)))
}

resource "google_secret_manager_secret" "this" {
  for_each  = local.secret_keys
  secret_id = each.key
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "this" {
  for_each    = local.secret_keys
  secret      = google_secret_manager_secret.this[each.key].id
  secret_data = var.secrets[each.key]
}
