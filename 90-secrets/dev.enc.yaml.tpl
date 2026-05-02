# Template - copy to dev.enc.yaml, fill in values, then: sops --encrypt --in-place dev.enc.yaml
# App
NODE_ENV: development
NEXT_PUBLIC_APP_URL: https://dev.sleev.org

# Database
DATABASE_URL: postgresql://app_dev:CHANGE_ME@host.docker.internal:5433/app_dev
PG_PASSWORD: CHANGE_ME_STRONG_RANDOM

# Email
SMTP_HOST: smtp.gmail.com
SMTP_PORT: "587"
SMTP_USER: CHANGE_ME
SMTP_PASS: CHANGE_ME

# Nginx Basic Auth (dev only)
DEV_HTPASSWD_USER: deploy
DEV_HTPASSWD_PASS: CHANGE_ME

# Tailscale — NOTE: provisioning reads TAILSCALE_AUTH_KEY from prod.enc.yaml, not dev.
TAILSCALE_AUTH_KEY: CHANGE_ME

# GHCR
GHCR_TOKEN: CHANGE_ME

# Certbot — NOTE: provisioning reads CERTBOT_EMAIL from prod.enc.yaml, not dev.
CERTBOT_EMAIL: CHANGE_ME

# Cloudflare R2
R2_ENDPOINT: https://ACCOUNT_ID.r2.cloudflarestorage.com
R2_ACCESS_KEY_ID: CHANGE_ME
R2_SECRET_ACCESS_KEY: CHANGE_ME
R2_BUCKET: sleev-backups
