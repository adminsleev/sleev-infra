set shell := ["bash", "-euo", "pipefail", "-c"]

ghcr_image := "ghcr.io/sleev/sleev-website-app"

# ── Bootstrap ────────────────────────────────────────────────────────────────
# Two-phase VPS setup. Phase 1 via public SSH (password), Phase 2 via Tailscale.
# Skips Phase 1 automatically if VPS is already reachable on Tailscale.
#
# Usage: just bootstrap 00-environment/vps
#
# Prerequisites:
#   - inventories/bootstrap/group_vars/all.yml has the VPS public IP
#   - ~/.ssh/id_ed25519_hostinger_vpsleev_vps-access is the operator key
#   - ~/.ssh/sleev_github_to_vps_deploy.pub is the GitHub Actions deploy key

bootstrap target:
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

    if ssh -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o IdentitiesOnly=yes \
            -i ~/.ssh/id_ed25519_hostinger_vpsleev_vps-access \
            root@sleev-vps exit 2>/dev/null; then
        echo ""
        echo "==> VPS already reachable on Tailscale — skipping Phase 1."
    else
        echo ""
        echo "==> Phase 1: Installing Tailscale via public SSH (password prompt follows)..."
        ansible-playbook \
            -i inventories/bootstrap \
            {{ target }}/playbooks/bootstrap.yml \
            --ask-pass \
            --extra-vars "@$TMPVARS"

        echo ""
        echo "==> Phase 1 complete. Waiting 10 seconds for Tailscale to register..."
        sleep 10
    fi

    echo ""
    echo "==> Phase 2: Hardening VPS via Tailscale (key auth)..."
    ansible-playbook \
        -i inventories/prod \
        {{ target }}/playbooks/harden.yml \
        --extra-vars "@$TMPVARS"

    echo ""
    echo "==> Bootstrap complete. SSH is now locked to Tailscale only."
    echo "    Run: just provision 00-environment/vps"

# ── Provision ────────────────────────────────────────────────────────────────
# Full VPS provisioning via Tailscale (run after bootstrap).
#
# Usage: just provision 00-environment/vps

provision target:
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
    DEPLOY_PUBKEY=$(cat ~/.ssh/sleev_github_to_vps_deploy.pub 2>/dev/null || { echo "ERROR: ~/.ssh/sleev_github_to_vps_deploy.pub not found."; exit 1; })
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
        {{ target }}/playbooks/provision.yml \
        --extra-vars "@$TMPVARS"

# ── Deploy ───────────────────────────────────────────────────────────────────
# Deploy a container image to dev or prod.
#
# Usage:
#   just deploy 05-deploy/vps dev dev-abc1234
#   just deploy 05-deploy/vps prod prod-abc1234

deploy target env tag:
    #!/usr/bin/env bash
    set -euo pipefail
    export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:?SOPS_AGE_KEY_FILE must be set}"
    ansible-playbook \
        -i inventories/{{ env }} \
        {{ target }}/playbooks/deploy.yml \
        -e env={{ env }} \
        -e image_tag={{ tag }} \
        -e ghcr_image={{ ghcr_image }}

# ── Rollback ─────────────────────────────────────────────────────────────────
# Roll back to a previous image tag (migrations disabled).
#
# Usage: just rollback 05-deploy/vps prod prod-abc1234

rollback target env tag:
    #!/usr/bin/env bash
    set -euo pipefail
    export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:?SOPS_AGE_KEY_FILE must be set}"
    ansible-playbook \
        -i inventories/{{ env }} \
        {{ target }}/playbooks/rollback.yml \
        -e env={{ env }} \
        -e image_tag={{ tag }} \
        -e ghcr_image={{ ghcr_image }}

# ── Backup ───────────────────────────────────────────────────────────────────
# Backup database to R2.
#
# Usage:
#   just backup 10-maintenance/vps dev
#   just backup 10-maintenance/vps prod

backup target env:
    #!/usr/bin/env bash
    set -euo pipefail
    ansible-playbook \
        -i inventories/{{ env }} \
        {{ target }}/playbooks/db-backup.yml \
        -e env={{ env }}

# ── Restore ──────────────────────────────────────────────────────────────────
# Restore PROD database from a dump file on the VPS.
# WARNING: destroys current data in app_prod.
#
# Usage: just restore 10-maintenance/vps prod /opt/backups/db/prod_2026-05-01.dump

restore target env dump:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "WARNING: This will DESTROY all data in app_{{ env }} and restore from {{ dump }}"
    echo "Press Ctrl-C within 5 seconds to abort..."
    sleep 5
    ansible-playbook \
        -i inventories/{{ env }} \
        {{ target }}/playbooks/db-restore.yml \
        -e env={{ env }} \
        -e "dump_file={{ dump }}"

# ── SSL renew ────────────────────────────────────────────────────────────────
# Renew SSL certificates via certbot --nginx.
#
# Usage: just ssl-renew 10-maintenance/vps

ssl-renew target:
    #!/usr/bin/env bash
    set -euo pipefail
    ansible-playbook \
        -i inventories/prod \
        {{ target }}/playbooks/ssl-renew.yml

# ── Secrets ──────────────────────────────────────────────────────────────────
# Open a SOPS-encrypted secrets file in your editor.
#
# Usage:
#   just secrets dev
#   just secrets prod
#   just secrets server

secrets env:
    sops 90-secrets/enc.{{ env }}.yaml

# ── Local (Docker Compose) ───────────────────────────────────────────────────
# Start/stop local development environment.
#
# Usage:
#   just local up
#   just local down

local cmd:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ cmd }}" in
        up)   docker compose -f ../sleev-website-app/docker-compose.local.yml up -d ;;
        down) docker compose -f ../sleev-website-app/docker-compose.local.yml down ;;
        *)    echo "Usage: just local up|down"; exit 1 ;;
    esac

# ── Setup ────────────────────────────────────────────────────────────────────

# Install local toolchain (run this first)
setup:
    bash 95-scripts/setup-local.sh

# Install Ansible Galaxy collections
deps:
    ansible-galaxy collection install -r requirements.yml

# Generate a new age keypair (one-time only)
gen-age-key:
    bash 95-scripts/gen-age-key.sh
