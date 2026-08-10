/**
 * Which host, and why it differs between the two.
 *
 * The application goes through the pooler, because it opens a connection per
 * request and Neon's direct endpoint has a low connection ceiling.  The owner
 * goes direct, because the pooler runs PgBouncer in transaction mode and some
 * DDL and session state a migration needs does not survive that.
 */

output "app_connection_uri" {
  value     = "postgresql://${neon_role.serving.name}:${neon_role.serving.password}@${neon_project.this.database_host_pooler}/${neon_database.app.name}?sslmode=require"
  sensitive = true
}

output "owner_connection_uri" {
  value     = "postgresql://${neon_role.owner.name}:${neon_role.owner.password}@${neon_project.this.database_host}/${neon_database.app.name}?sslmode=require"
  sensitive = true
}

output "read_only_connection_uri" {
  value     = "postgresql://${neon_role.read_only.name}:${neon_role.read_only.password}@${neon_project.this.database_host_pooler}/${neon_database.app.name}?sslmode=require"
  sensitive = true
}

output "project_id" {
  value = neon_project.this.id
}

output "branch_id" {
  value = neon_project.this.default_branch_id
}

output "database_name" {
  value = neon_database.app.name
}

output "owner_role_name" {
  value = neon_role.owner.name
}

output "app_role_name" {
  value = neon_role.serving.name
}

output "read_only_role_name" {
  value = neon_role.read_only.name
}

output "database_host" {
  value = neon_project.this.database_host
}

# `envs/prod-grants` connects as the owner to apply the grants.  It gets the
# password from here rather than from a variable somebody types, so it cannot
# grant to a role other than the one this module made.
output "owner_role_password" {
  value     = neon_role.owner.password
  sensitive = true
}
