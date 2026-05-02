#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing local toolchain for sleev-infra"

# ansible
if ! command -v ansible &>/dev/null; then
    echo "Installing ansible..."
    pip3 install --user ansible
else
    echo "ansible already installed: $(ansible --version | head -1)"
fi

# sops
if ! command -v sops &>/dev/null; then
    echo "Installing sops..."
    brew install sops
else
    echo "sops already installed: $(sops --version)"
fi

# age
if ! command -v age &>/dev/null; then
    echo "Installing age..."
    brew install age
else
    echo "age already installed: $(age --version)"
fi

# rclone
if ! command -v rclone &>/dev/null; then
    echo "Installing rclone..."
    curl -fsSL https://rclone.org/install.sh | bash
else
    echo "rclone already installed: $(rclone --version | head -1)"
fi

# just
if ! command -v just &>/dev/null; then
    echo "Installing just..."
    brew install just
else
    echo "just already installed: $(just --version)"
fi

# tailscale CLI
if ! command -v tailscale &>/dev/null; then
    echo "Installing tailscale..."
    brew install tailscale
else
    echo "tailscale already installed: $(tailscale version)"
fi

echo ""
echo "==> All tools installed. Next steps:"
echo "    1. Run: just gen-age-key"
echo "    2. Add the printed public key to 90-secrets/.sops.yaml"
echo "    3. cp 90-secrets/dev.enc.yaml.tpl 90-secrets/dev.enc.yaml && edit with real values"
echo "    4. cp 90-secrets/prod.enc.yaml.tpl 90-secrets/prod.enc.yaml && edit with real values"
echo "    5. sops --encrypt --in-place 90-secrets/dev.enc.yaml"
echo "    6. sops --encrypt --in-place 90-secrets/prod.enc.yaml"
