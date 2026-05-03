# Template - copy to prod.yaml, fill in values, then:
#   sops --encrypt --output enc.prod.yaml prod.yaml
#
# Key naming convention:
#   UPPERCASE  = read by Justfile via `sops --extract` (provisioning secrets)
#
# App runtime secrets have moved to sleev-website-app/secrets/enc.app.prod.yaml

# Database — read by Justfile provisioning
PG_PASSWORD: CHANGE_ME_STRONG_RANDOM
