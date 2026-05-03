# Template - copy to dev.yaml, fill in values, then:
#   sops --encrypt --output enc.dev.yaml dev.yaml
#
# Key naming convention:
#   UPPERCASE  = read by Justfile via `sops --extract` (provisioning secrets)
#
# App runtime secrets have moved to sleev-website-app/secrets/enc.app.dev.yaml

# Database — read by Justfile provisioning
PG_PASSWORD: CHANGE_ME_STRONG_RANDOM

# Nginx Basic Auth (dev only) — read by Justfile provisioning
DEV_HTPASSWD_USER: deploy
DEV_HTPASSWD_PASS: CHANGE_ME
