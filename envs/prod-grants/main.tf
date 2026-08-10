/**
 * The database privileges, as code.  A SEPARATE root module, on purpose.
 *
 * WHAT THIS IS FOR.  `modules/neon` creates three roles and grants them
 * nothing, because the Neon provider speaks to the Neon API and runs no SQL.
 * The grants live in the database, applied by hand during the security
 * hardening rollout.  That leaves two holes: a rebuild from an empty project
 * produces three roles with no privileges, and nothing detects somebody
 * giving `cc_app` the ability to run DDL.  This directory closes both.
 *
 * WHY IT IS NOT A FLAG IN `envs/prod`.  A `count = var.manage_grants ? 1 : 0`
 * does keep the provider from connecting — that is measured, not assumed.
 * The problem is what happens after somebody applies with the flag on and
 * then runs an ordinary apply with it off: Terraform destroys the grant
 * resources, and destroying a grant is a REVOKE.  The flag would put a
 * production outage one forgotten variable away.  A separate root module has
 * its own state, so "off" means "do not run this directory".
 *
 * WHAT IT COSTS.  Running `plan` here opens a database connection, because a
 * refresh has to read the current privileges.  `envs/prod` never declares
 * this provider, so the ordinary deploy path still contacts nothing.
 *
 * WHEN TO RUN IT.
 *
 *   - After a rebuild from an empty Neon project, once, to apply the grants.
 *   - Whenever you want a privilege audit.  `plan` reporting no changes is
 *     the statement that nobody has widened a role.
 *
 * ⚠️ `terraform destroy` here REVOKES every privilege and stops the site.
 */

terraform {
  required_version = ">= 1.7"

  required_providers {
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.22"
    }
  }
}

# The connection details come from the deployment's own state rather than from
# a variable, so the roles this grants to are by construction the roles
# `envs/prod` created.  Two hand-typed copies would eventually disagree.
data "terraform_remote_state" "prod" {
  backend = "local"

  config = {
    path = "${path.module}/../prod/terraform.tfstate"
  }
}

locals {
  db = data.terraform_remote_state.prod.outputs.neon_grant_inputs
}

# Connect as the owner, on the DIRECT host.  The pooler runs PgBouncer in
# transaction mode, and GRANT through it is not reliable.
#
# `superuser = false` is required: Neon issues no superuser role, and the
# provider otherwise expects to be able to `SET ROLE` its way around.
provider "postgresql" {
  host      = local.db.host
  port      = 5432
  database  = local.db.database
  username  = local.db.owner_role
  password  = local.db.owner_password
  sslmode   = "require"
  superuser = false
}

# ---------------------------------------------------------------------------
# The serving role.  Read and write rows; nothing else.
#
# Each of these resources sets the privileges to EXACTLY the listed set, so an
# extra privilege granted by hand shows up as a diff and is revoked on apply.
# That is the drift detection this directory exists for.
# ---------------------------------------------------------------------------

resource "postgresql_grant" "app_database" {
  database    = local.db.database
  role        = local.db.app_role
  object_type = "database"
  privileges  = ["CONNECT"]
}

resource "postgresql_grant" "app_schema" {
  database    = local.db.database
  role        = local.db.app_role
  schema      = "public"
  object_type = "schema"
  privileges  = ["USAGE"]
}

# Deliberately NOT TRUNCATE, and deliberately not CREATE on the schema above.
# A flaw on the request path can then corrupt rows but cannot drop a table or
# empty one in a single statement.
resource "postgresql_grant" "app_tables" {
  database    = local.db.database
  role        = local.db.app_role
  schema      = "public"
  object_type = "table"
  privileges  = ["SELECT", "INSERT", "UPDATE", "DELETE"]
}

resource "postgresql_grant" "app_sequences" {
  database    = local.db.database
  role        = local.db.app_role
  schema      = "public"
  object_type = "sequence"
  privileges  = ["SELECT", "USAGE"]
}

# The two resources that matter most, and the ones a hand-written runbook
# forgets.  Every migration creates tables the grants above have already run
# past.  These say what a table created LATER grants, and they work only
# because the owner role creates them.
resource "postgresql_default_privileges" "app_tables" {
  database    = local.db.database
  role        = local.db.app_role
  owner       = local.db.owner_role
  schema      = "public"
  object_type = "table"
  privileges  = ["SELECT", "INSERT", "UPDATE", "DELETE"]
}

resource "postgresql_default_privileges" "app_sequences" {
  database    = local.db.database
  role        = local.db.app_role
  owner       = local.db.owner_role
  schema      = "public"
  object_type = "sequence"
  privileges  = ["SELECT", "USAGE"]
}

# ---------------------------------------------------------------------------
# The read-only role.  For a person at a prompt, not for the application.
# ---------------------------------------------------------------------------

resource "postgresql_grant" "read_only_database" {
  database    = local.db.database
  role        = local.db.read_only_role
  object_type = "database"
  privileges  = ["CONNECT"]
}

resource "postgresql_grant" "read_only_schema" {
  database    = local.db.database
  role        = local.db.read_only_role
  schema      = "public"
  object_type = "schema"
  privileges  = ["USAGE"]
}

resource "postgresql_grant" "read_only_tables" {
  database    = local.db.database
  role        = local.db.read_only_role
  schema      = "public"
  object_type = "table"
  privileges  = ["SELECT"]
}

# No sequence privileges for this role, matching the live database: reading a
# sequence is not reading data.
resource "postgresql_default_privileges" "read_only_tables" {
  database    = local.db.database
  role        = local.db.read_only_role
  owner       = local.db.owner_role
  schema      = "public"
  object_type = "table"
  privileges  = ["SELECT"]
}
