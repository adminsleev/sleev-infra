# Template - copy to server.yaml, fill in values, then:
#   sops --encrypt --output enc.server.yaml server.yaml
#
# Key naming convention:
#   UPPERCASE  = read by Justfile via `sops --extract` (provisioning secrets)
#   lowercase  = loaded by community.sops.load_vars in deploy playbooks

# Tailscale — read by Justfile provisioning
TAILSCALE_AUTH_KEY: CHANGE_ME

# Certbot — read by Justfile provisioning
CERTBOT_EMAIL: CHANGE_ME

# Cloudflare R2 — read by Justfile provisioning
R2_ENDPOINT: https://ACCOUNT_ID.r2.cloudflarestorage.com
R2_ACCESS_KEY_ID: CHANGE_ME
R2_SECRET_ACCESS_KEY: CHANGE_ME
R2_BUCKET: sleev-vps-artifact-backups

# GHCR read token — loaded by deploy playbooks
ghcr_read_token: CHANGE_ME
