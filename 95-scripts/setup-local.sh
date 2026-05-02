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
    SOPS_VERSION=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    curl -fsSL "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.darwin.amd64" \
        -o /usr/local/bin/sops
    chmod +x /usr/local/bin/sops
else
    echo "sops already installed: $(sops --version)"
fi

# age
if ! command -v age &>/dev/null; then
    echo "Installing age..."
    AGE_VERSION=$(curl -s https://api.github.com/repos/FiloSottile/age/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    TMP=$(mktemp -d)
    curl -fsSL "https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-darwin-amd64.tar.gz" \
        -o "$TMP/age.tar.gz"
    tar -xf "$TMP/age.tar.gz" -C "$TMP"
    cp "$TMP/age/age" /usr/local/bin/age
    cp "$TMP/age/age-keygen" /usr/local/bin/age-keygen
    rm -rf "$TMP"
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
echo "    2. Add the printed public key to secrets/.sops.yaml"
echo "    3. Edit secrets/dev.enc.yaml and secrets/prod.enc.yaml with your values"
echo "    4. Encrypt: sops --encrypt --in-place secrets/dev.enc.yaml"
echo "    5. Encrypt: sops --encrypt --in-place secrets/prod.enc.yaml"
