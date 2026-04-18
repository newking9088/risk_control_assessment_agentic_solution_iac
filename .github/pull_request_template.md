<!-- This PR only changes Terraform / IaC for this repo.
     If it does NOT add Helm, Argo CD, or app source changes — those
     belong in the app or gitops repos. -->

## Summary
<!-- What changed and why. Link to the Jira/ticket if applicable. -->

## Environments affected
- [ ] dev
- [ ] qa
- [ ] stage
- [ ] prod
- [ ] databricks sub-root

## Modules touched
<!-- e.g. keyvault, postgres, storage, cognitive, data_factory, synapse -->

## Terraform plan output
<!-- Paste the relevant hash of `terraform plan` for the affected env. -->

```
<!-- plan output here -->
```

## Security considerations
- [ ] No secrets / object IDs in plain text outside `config.auto.tfvars`.
- [ ] No public paths in `config.auto.tfvars` / TF plan output committed to repo.
- [ ] The repo public policy fails on the target env.
- [ ] One module with `"outputs_*"` so downstream consumers can reference it.

## Rollback plan
<!-- How to revert if the apply fails in the target env. -->

## Checklist
- [ ] `terraform fmt --check` passes for every affected env.
- [ ] `terraform validate` passes for every affected env.
- [ ] `tflint` and `trivy config` findings are justified in comments above.
- [ ] `config.auto.tfvars` values note the target subscription and admin.
- [ ] CODEOWNERS review requested.
