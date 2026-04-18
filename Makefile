# Targets:  help  bootstrap  fmt  lint  validate  plan  security  cost  drift  clean
# Override ENV to target a specific environment (default: dev).
ENV    ?= dev
TF_DIR  = infrastructure/$(ENV)

.PHONY: help bootstrap fmt lint validate plan security cost drift clean

help:
	@echo "Targets (override with ENV=<dev|qa|stage|prod>):"
	@echo "  make bootstrap  — install terraform, tflint, trivy, gh, az, infracost; run pre-commit install"
	@echo "  make fmt        — terraform fmt --recursive on all environments"
	@echo "  make lint       — tflint --recursive infrastructure"
	@echo "  make validate   — terraform init -backend=false && terraform validate for ENV"
	@echo "  make plan       — terraform plan --detailed-exitcode for ENV"
	@echo "  make security   — trivy config --exit-code 1 --severity CRITICAL,HIGH infrastructure"
	@echo "  make cost       — infracost breakdown --path \$(TF_DIR)"
	@echo "  make drift      — terraform plan --detailed-exitcode for ENV (reports non-zero exit)"
	@echo "  make clean      — remove .terraform dirs and lock files"

bootstrap:
	bash scripts/bootstrap.sh

fmt:
	terraform fmt --recursive infrastructure

lint:
	tflint --init
	tflint --recursive --format compact

validate:
	cd $(TF_DIR) && terraform init -backend=false && terraform validate

plan:
	cd $(TF_DIR) && terraform init -input=false && terraform plan -detailed-exitcode -input=false

security:
	trivy config --exit-code 1 --severity CRITICAL,HIGH infrastructure

cost:
	infracost breakdown --path $(TF_DIR)

drift:
	cd $(TF_DIR) && terraform init -input=false && terraform plan -detailed-exitcode -input=false

clean:
	find infrastructure -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	find infrastructure -type f -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	find infrastructure -type f -name "terraform.tfstate*" -delete 2>/dev/null || true
