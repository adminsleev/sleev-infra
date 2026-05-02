set shell := ["bash", "-euo", "pipefail", "-c"]

# ── Helpers ──────────────────────────────────────────────────────────────────

# Decrypt a key from a SOPS file: _sops_get FILE KEY
_sops_get file key:
    #!/usr/bin/env bash
    sops --decrypt --extract '["{{key}}"]' {{file}}

# ── Bootstrap (one-time) ─────────────────────────────────────────────────────

# First-time VPS setup: install Tailscale via public SSH, then lock down SSH.
# Prerequisites: fill in inventories/bootstrap/group_vars/all.yml with the public VPS IP.
bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    TMPVARS=$(mktemp /tmp/bootstrap-vars-XXXXXX.yml)
    trap "rm -f $TMPVARS" EXIT

    echo "Decrypting secrets..."
    TAILSCALE_KEY=$(sops --decrypt --extract '["TAILSCALE_AUTH_KEY"]' 90-secrets/prod.enc.yaml)
    DEPLOY_PUBKEY=$(cat ~/.ssh/sleev_deploy.pub 2>/dev/null || { echo "ERROR: ~/.ssh/sleev_deploy.pub not found. Run: ssh-keygen -t ed25519 -f ~/.ssh/sleev_deploy -C github-actions-sleev-deploy"; exit 1; })
    R2_ENDPOINT=$(sops --decrypt --extract '["R2_ENDPOINT"]' 90-secrets/prod.enc.yaml)
    R2_KEY=$(sops --decrypt --extract '["R2_ACCESS_KEY_ID"]' 90-secrets/prod.enc.yaml)
    R2_SECRET=$(sops --decrypt --extract '["R2_SECRET_ACCESS_KEY"]' 90-secrets/prod.enc.yaml)
    R2_BUCKET=$(sops --decrypt --extract '["R2_BUCKET"]' 90-secrets/prod.enc.yaml)

    cat > "$TMPVARS" <<VARS
    tailscale_auth_key: "${TAILSCALE_KEY}"
    deploy_ssh_public_key: "${DEPLOY_PUBKEY}"
    r2_endpoint: "${R2_ENDPOINT}"
    r2_access_key: "${R2_KEY}"
    r2_secret: "${R2_SECRET}"
    r2_bucket: "${R2_BUCKET}"
    VARS

    ansible-playbook \
        -i inventories/bootstrap \
        00-provision/playbooks/bootstrap.yml \
        --extra-vars "@$TMPVARS"

    echo ""
    echo "==> Bootstrap complete."
    echo "    1. Check Tailscale admin console — VPS should appear as 'sleev-vps'"
    echo "    2. Update inventories/dev/hosts.yml and prod/hosts.yml"
    echo "       if the Tailscale hostname differs from 'sleev-vps'"
    echo "    3. Run: just provision"

# ── Provisioning ─────────────────────────────────────────────────────────────

# Full VPS provisioning via Tailscale (run after bootstrap).
provision:
    #!/usr/bin/env bash
    set -euo pipefail
    TMPVARS=$(mktemp /tmp/provision-vars-XXXXXX.yml)
    trap "rm -f $TMPVARS" EXIT

    echo "Decrypting secrets..."
    PROD_PG_PASS=$(sops --decrypt --extract '["PG_PASSWORD"]' 90-secrets/prod.enc.yaml)
    DEV_PG_PASS=$(sops --decrypt --extract '["PG_PASSWORD"]' 90-secrets/dev.enc.yaml)
    CERTBOT_EMAIL=$(sops --decrypt --extract '["CERTBOT_EMAIL"]' 90-secrets/prod.enc.yaml)
    DEV_HTPASSWD_USER=$(sops --decrypt --extract '["DEV_HTPASSWD_USER"]' 90-secrets/dev.enc.yaml)
    DEV_HTPASSWD_PASS=$(sops --decrypt --extract '["DEV_HTPASSWD_PASS"]' 90-secrets/dev.enc.yaml)
    DEPLOY_PUBKEY=$(cat ~/.ssh/sleev_deploy.pub 2>/dev/null || { echo "ERROR: ~/.ssh/sleev_deploy.pub not found. Run: ssh-keygen -t ed25519 -f ~/.ssh/sleev_deploy -C github-actions-sleev-deploy"; exit 1; })
    R2_ENDPOINT=$(sops --decrypt --extract '["R2_ENDPOINT"]' 90-secrets/prod.enc.yaml)
    R2_KEY=$(sops --decrypt --extract '["R2_ACCESS_KEY_ID"]' 90-secrets/prod.enc.yaml)
    R2_SECRET=$(sops --decrypt --extract '["R2_SECRET_ACCESS_KEY"]' 90-secrets/prod.enc.yaml)
    R2_BUCKET=$(sops --decrypt --extract '["R2_BUCKET"]' 90-secrets/prod.enc.yaml)

    cat > "$TMPVARS" <<VARS
    prod_pg_password: "${PROD_PG_PASS}"
    dev_pg_password: "${DEV_PG_PASS}"
    certbot_email: "${CERTBOT_EMAIL}"
    dev_htpasswd_user: "${DEV_HTPASSWD_USER}"
    dev_htpasswd_pass: "${DEV_HTPASSWD_PASS}"
    deploy_ssh_public_key: "${DEPLOY_PUBKEY}"
    r2_endpoint: "${R2_ENDPOINT}"
    r2_access_key: "${R2_KEY}"
    r2_secret: "${R2_SECRET}"
    r2_bucket: "${R2_BUCKET}"
    VARS

    ansible-playbook \
        -i inventories/prod \
        00-provision/playbooks/provision.yml \
        --extra-vars "@$TMPVARS"

# ── Secrets ──────────────────────────────────────────────────────────────────

# Edit DEV secrets with SOPS
secrets-edit-dev:
    sops 90-secrets/dev.enc.yaml

# Edit PROD secrets with SOPS
secrets-edit-prod:
    sops 90-secrets/prod.enc.yaml

# ── Local setup ──────────────────────────────────────────────────────────────

# Install local toolchain (run this first, before any other target)
setup:
    bash 95-scripts/setup-local.sh

# Generate a new age keypair (one-time only)
gen-age-key:
    bash 95-scripts/gen-age-key.sh

# Install Ansible Galaxy collections
deps:
    ansible-galaxy collection install -r requirements.yml

# ──────────────────────────────────────────────────────────────────────────────
# Deploy targets
# Usage:
#   just deploy-dev dev-abc1234
#   just deploy-prod prod-abc1234
# The image_tag must match a tag pushed to GHCR by the CI pipeline.
# ──────────────────────────────────────────────────────────────────────────────

# Deploy to DEV environment
deploy-dev tag:
    #!/usr/bin/env bash
    set -euo pipefail
    export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:?SOPS_AGE_KEY_FILE must be set}"
    ansible-playbook \
        -i inventories/dev/hosts.yml \
        05-deploy/playbooks/deploy.yml \
        -e env=dev \
        -e image_tag={{ tag }}

# Deploy to PROD environment
deploy-prod tag:
    #!/usr/bin/env bash
    set -euo pipefail
    export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:?SOPS_AGE_KEY_FILE must be set}"
    ansible-playbook \
        -i inventories/prod/hosts.yml \
        05-deploy/playbooks/deploy.yml \
        -e env=prod \
        -e image_tag={{ tag }}

# ──────────────────────────────────────────────────────────────────────────────
# Rollback targets
# Usage:
#   just rollback-prod prod-abc1234
# Rolls back to the specified image tag WITHOUT running migrations.
# ──────────────────────────────────────────────────────────────────────────────

# Rollback PROD to a previous image tag (migrations disabled)
rollback-prod tag:
    #!/usr/bin/env bash
    set -euo pipefail
    export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:?SOPS_AGE_KEY_FILE must be set}"
    ansible-playbook \
        -i inventories/prod/hosts.yml \
        05-deploy/playbooks/rollback.yml \
        -e env=prod \
        -e image_tag={{ tag }}

# ──────────────────────────────────────────────────────────────────────────────
# Maintenance targets
# ──────────────────────────────────────────────────────────────────────────────

# Backup DEV database to R2
db-backup-dev:
    #!/usr/bin/env bash
    set -euo pipefail
    ansible-playbook \
        -i inventories/dev/hosts.yml \
        10-maintenance/playbooks/db-backup.yml \
        -e env=dev

# Backup PROD database to R2
db-backup-prod:
    #!/usr/bin/env bash
    set -euo pipefail
    ansible-playbook \
        -i inventories/prod/hosts.yml \
        10-maintenance/playbooks/db-backup.yml \
        -e env=prod

# Restore PROD database from a dump file on the VPS
# Usage: just db-restore-prod /opt/backups/db/prod_2026-05-01.dump
db-restore-prod dump:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "WARNING: This will DESTROY all data in app_prod and restore from {{ dump }}"
    echo "Press Ctrl-C within 5 seconds to abort..."
    sleep 5
    ansible-playbook \
        -i inventories/prod/hosts.yml \
        10-maintenance/playbooks/db-restore.yml \
        -e env=prod \
        -e dump_file={{ dump }}

# Renew SSL certificates via certbot --nginx on the VPS
ssl-renew:
    #!/usr/bin/env bash
    set -euo pipefail
    ansible-playbook \
        -i inventories/prod/hosts.yml \
        10-maintenance/playbooks/ssl-renew.yml
