set shell := ["bash", "-euo", "pipefail", "-c"]

# ── Helpers ──────────────────────────────────────────────────────────────────

# Decrypt a key from a SOPS file: _sops_get FILE KEY
_sops_get file key:
    #!/usr/bin/env bash
    sops --decrypt --extract '["{{key}}"]' {{file}}

# ── Bootstrap (one-time) ─────────────────────────────────────────────────────

# Two-phase VPS setup:
#   Phase 1 — public SSH (password): installs Tailscale, adds operator key to root
#   Phase 2 — Tailscale (key auth):  hardens SSH, creates deploy user, enables UFW
#
# Prerequisites:
#   - inventories/bootstrap/group_vars/all.yml has the VPS public IP
#   - ~/.ssh/id_ed25519 is your operator key (you can SSH to the VPS with it)
#   - ~/.ssh/sleev_github_to_vps_deploy.pub exists (GitHub Actions deploy key)
bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    TMPVARS=$(mktemp /tmp/bootstrap-vars-XXXXXX.yml)
    trap "rm -f $TMPVARS" EXIT

    echo "Decrypting secrets..."
    TAILSCALE_KEY=$(sops --decrypt --extract '["TAILSCALE_AUTH_KEY"]' 90-secrets/enc.server.yaml)
    OPERATOR_PUBKEY=$(cat ~/.ssh/id_ed25519_hostinger_vpsleev_vps-access.pub 2>/dev/null || { echo "ERROR: ~/.ssh/id_ed25519_hostinger_vpsleev_vps-access.pub not found."; exit 1; })
    DEPLOY_PUBKEY=$(cat ~/.ssh/sleev_github_to_vps_deploy.pub 2>/dev/null || { echo "ERROR: ~/.ssh/sleev_github_to_vps_deploy.pub not found. Run: ssh-keygen -t ed25519 -f ~/.ssh/sleev_github_to_vps_deploy -C github-actions-sleev-deploy"; exit 1; })
    R2_ENDPOINT=$(sops --decrypt --extract '["R2_ENDPOINT"]' 90-secrets/enc.server.yaml)
    R2_KEY=$(sops --decrypt --extract '["R2_ACCESS_KEY_ID"]' 90-secrets/enc.server.yaml)
    R2_SECRET=$(sops --decrypt --extract '["R2_SECRET_ACCESS_KEY"]' 90-secrets/enc.server.yaml)
    R2_BUCKET=$(sops --decrypt --extract '["R2_BUCKET"]' 90-secrets/enc.server.yaml)

    cat > "$TMPVARS" <<VARS
    tailscale_auth_key: "${TAILSCALE_KEY}"
    operator_ssh_public_key: "${OPERATOR_PUBKEY}"
    deploy_ssh_public_key: "${DEPLOY_PUBKEY}"
    r2_endpoint: "${R2_ENDPOINT}"
    r2_access_key: "${R2_KEY}"
    r2_secret: "${R2_SECRET}"
    r2_bucket: "${R2_BUCKET}"
    VARS

    # Check if VPS is already reachable on Tailscale — skip Phase 1 if so.
    if ssh -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o IdentitiesOnly=yes \
            -i ~/.ssh/id_ed25519_hostinger_vpsleev_vps-access \
            root@sleev-vps exit 2>/dev/null; then
        echo ""
        echo "==> VPS already reachable on Tailscale — skipping Phase 1."
    else
        echo ""
        echo "==> Phase 1: Installing Tailscale via public SSH (you will be prompted for the root password)..."
        ansible-playbook \
            -i inventories/bootstrap \
            00-provision/playbooks/bootstrap.yml \
            --ask-pass \
            --extra-vars "@$TMPVARS"

        echo ""
        echo "==> Phase 1 complete. Waiting 10 seconds for Tailscale to register on the tailnet..."
        sleep 10
    fi

    echo ""
    echo "==> Phase 2: Hardening VPS via Tailscale (key auth)..."
    ansible-playbook \
        -i inventories/prod \
        00-provision/playbooks/harden.yml \
        --extra-vars "@$TMPVARS"

    echo ""
    echo "==> Bootstrap complete. SSH is now locked to Tailscale only."
    echo "    1. Verify VPS appears in Tailscale admin console as 'sleev-vps'"
    echo "    2. Run: just provision"

# ── Provisioning ─────────────────────────────────────────────────────────────

# Full VPS provisioning via Tailscale (run after bootstrap).
provision:
    #!/usr/bin/env bash
    set -euo pipefail
    TMPVARS=$(mktemp /tmp/provision-vars-XXXXXX.yml)
    trap "rm -f $TMPVARS" EXIT

    echo "Decrypting secrets..."
    PROD_PG_PASS=$(sops --decrypt --extract '["PG_PASSWORD"]' 90-secrets/enc.prod.yaml)
    DEV_PG_PASS=$(sops --decrypt --extract '["PG_PASSWORD"]' 90-secrets/enc.dev.yaml)
    CERTBOT_EMAIL=$(sops --decrypt --extract '["CERTBOT_EMAIL"]' 90-secrets/enc.server.yaml)
    DEV_HTPASSWD_USER=$(sops --decrypt --extract '["DEV_HTPASSWD_USER"]' 90-secrets/enc.dev.yaml)
    DEV_HTPASSWD_PASS=$(sops --decrypt --extract '["DEV_HTPASSWD_PASS"]' 90-secrets/enc.dev.yaml)
    DEPLOY_PUBKEY=$(cat ~/.ssh/sleev_github_to_vps_deploy.pub 2>/dev/null || { echo "ERROR: ~/.ssh/sleev_github_to_vps_deploy.pub not found. Run: ssh-keygen -t ed25519 -f ~/.ssh/sleev_github_to_vps_deploy -C github-actions-sleev-deploy"; exit 1; })
    R2_ENDPOINT=$(sops --decrypt --extract '["R2_ENDPOINT"]' 90-secrets/enc.server.yaml)
    R2_KEY=$(sops --decrypt --extract '["R2_ACCESS_KEY_ID"]' 90-secrets/enc.server.yaml)
    R2_SECRET=$(sops --decrypt --extract '["R2_SECRET_ACCESS_KEY"]' 90-secrets/enc.server.yaml)
    R2_BUCKET=$(sops --decrypt --extract '["R2_BUCKET"]' 90-secrets/enc.server.yaml)

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
    sops 90-secrets/enc.dev.yaml

# Edit PROD secrets with SOPS
secrets-edit-prod:
    sops 90-secrets/enc.prod.yaml

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
        -e "dump_file={{ dump }}"

# Renew SSL certificates via certbot --nginx on the VPS
ssl-renew:
    #!/usr/bin/env bash
    set -euo pipefail
    ansible-playbook \
        -i inventories/prod/hosts.yml \
        10-maintenance/playbooks/ssl-renew.yml
