output "public_ip" {
  value = google_compute_address.static.address
}

output "instance_name" {
  value = google_compute_instance.app.name
}

output "service_account_email" {
  value = google_service_account.vm.email
}
