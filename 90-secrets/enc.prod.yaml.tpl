# Template - copy to prod.yaml, fill in values, then:
#   sops --encrypt --output enc.prod.yaml prod.yaml
#
# Key naming convention:
#   UPPERCASE  = read by Justfile via `sops --extract` (provisioning secrets)
#   lowercase  = loaded by community.sops.load_vars in deploy playbooks

# App — loaded by deploy playbooks
node_env: production
next_public_app_url: https://sleev.org
database_url: postgresql://app_prod:CHANGE_ME@host.docker.internal:5432/app_prod

# Database — read by Justfile provisioning
PG_PASSWORD: CHANGE_ME_STRONG_RANDOM
