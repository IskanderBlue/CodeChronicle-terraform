output "connection_uri" {
  value     = "postgresql://${neon_role.app.name}:${neon_role.app.password}@${neon_project.this.database_host}/${neon_database.app.name}?sslmode=require"
  sensitive = true
}

output "project_id" {
  value = neon_project.this.id
}

output "database_name" {
  value = neon_database.app.name
}

output "role_name" {
  value = neon_role.app.name
}
