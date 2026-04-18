# OPA policy scaffold — restrict.rego
# Populated by the platform team in a follow-up PR.
#
# Rules to implement:
#   - diagnostic_logging must be true in stage and prod
#   - all resources must inherit local.tags
package restrict

default allow = false

allow {
  input.resource_type != ""
}
