# Template - copy to dev.yaml, fill in values, then:
#   sops --encrypt --output enc.dev.yaml dev.yaml
#
# Key naming convention:
#   UPPERCASE  = read by Justfile via `sops --extract` (provisioning secrets)
#   lowercase  = loaded by community.sops.load_vars in deploy playbooks

# App — loaded by deploy playbooks
node_env: development
next_public_app_url: https://dev.sleev.org
database_url: postgresql://app_dev:CHANGE_ME@host.docker.internal:5433/app_dev

# Database — read by Justfile provisioning
PG_PASSWORD: CHANGE_ME_STRONG_RANDOM

# Nginx Basic Auth (dev only) — read by Justfile provisioning
DEV_HTPASSWD_USER: deploy
DEV_HTPASSWD_PASS: CHANGE_ME
