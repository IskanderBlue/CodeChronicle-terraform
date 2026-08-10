/**
 * Three roles, and the two connection strings built from them.
 *
 * The application must not connect as the role that owns the tables.  The
 * serving role holds SELECT/INSERT/UPDATE/DELETE and sequence USAGE and
 * nothing else, so a flaw on the request path cannot run DDL or TRUNCATE; the
 * owner role runs `migrate` and owns every table.  `tasks/complete/
 * security-hardening-rollout.md` in the CodeChronicle repository records the
 * rollout that made this split.
 *
 * WHAT THIS MODULE DOES NOT DO.  It creates the roles.  It does not grant
 * them anything.  The grants and the `ALTER DEFAULT PRIVILEGES` statements
 * live in the database, applied by hand during that rollout, and Terraform
 * cannot see them: the Neon provider speaks to the Neon API and runs no SQL.
 *
 * Two things follow, and both matter:
 *
 *   - A role this module creates in a NEW project has no privileges at all.
 *     Restoring from scratch means running the grant SQL as well.
 *   - Nothing here detects drift in the grants.  Somebody can grant `cc_app`
 *     the ability to run DDL and no plan will report it.
 *
 * Closing that gap needs a second provider (`cyrilgdn/postgresql`), which
 * needs to reach the database at PLAN time, which means CI would hold a
 * database credential it does not hold today.  That is a decision on its own
 * merits, not a side effect of this file.
 */

resource "neon_project" "this" {
  name                      = var.project_name
  region_id                 = var.region
  history_retention_seconds = 21600
}

# The owner.  It runs migrations and owns every table, which is what makes the
# database's default privileges apply to tables that do not exist yet.  It
# never serves a request.
resource "neon_role" "owner" {
  project_id = neon_project.this.id
  branch_id  = neon_project.this.default_branch_id
  name       = var.owner_role_name
}

# Renamed from `app`, which was the trap: a role called `app` that the
# application must never use.  A `moved` block is a state rename, so this
# destroys nothing.
moved {
  from = neon_role.app
  to   = neon_role.owner
}

# The role the application connects as.
resource "neon_role" "serving" {
  project_id = neon_project.this.id
  branch_id  = neon_project.this.default_branch_id
  name       = var.app_role_name
}

# SELECT only, for a read-only session.  No secret holds this one: it is for a
# person at a prompt, and `terraform output -raw neon_read_only_uri` supplies
# it when it is wanted.
resource "neon_role" "read_only" {
  project_id = neon_project.this.id
  branch_id  = neon_project.this.default_branch_id
  name       = var.read_only_role_name
}

resource "neon_database" "app" {
  project_id = neon_project.this.id
  branch_id  = neon_project.this.default_branch_id
  name       = var.database_name
  owner_name = neon_role.owner.name
}
