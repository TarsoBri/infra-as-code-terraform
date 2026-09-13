.PHONY: bootstrap dev-init dev-plan dev-up dev-down prod-init prod-plan prod-apply

# Run once to create S3 bucket and DynamoDB table for remote state
bootstrap:
	terraform -chdir=bootstrap init
	terraform -chdir=bootstrap apply -auto-approve

# --- Dev (auto-approve: safe to destroy and recreate freely) ---
dev-init:
	terraform -chdir=environments/dev init

dev-plan:
	terraform -chdir=environments/dev plan

dev-up:
	terraform -chdir=environments/dev apply -auto-approve

dev-down:
	terraform -chdir=environments/dev destroy -auto-approve

# --- Prod (no auto-approve: always requires manual confirmation) ---
prod-init:
	terraform -chdir=environments/prod init

prod-plan:
	terraform -chdir=environments/prod plan

prod-apply:
	terraform -chdir=environments/prod apply
