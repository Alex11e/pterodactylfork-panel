#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../install.sh"
count=0
for value in panel.example.com a.b node-1.example.hu; do valid_domain "$value"; count=$((count+1)); done
for value in '-a.example.com' 'a..example.com' 'a.example.com/' 'a.example.com;id' '*.example.com' 'a.example.com$var' 'a.example.com:443' 'a.example.com.' ''; do
    if valid_domain "$value"; then die "Accepted invalid domain: $value"; fi
    count=$((count+1))
done
valid_email admin@example.com; count=$((count+1))
for value in 'bad' 'a@b' 'x@example.com;id' $'x@example.com\nAPP_KEY=bad'; do
    if valid_email "$value"; then die 'Accepted invalid email'; fi
    count=$((count+1))
done
valid_directory '/opt/alex panel'; count=$((count+1))
for value in / /etc /usr /var ../panel /opt/../etc; do
    if valid_directory "$value"; then die "Accepted invalid directory: $value"; fi
    count=$((count+1))
done
INSTALL_DIR=$(mktemp -d "${TMPDIR:-/tmp}/alex-installer-check.XXXXXX")
mkdir -p "$INSTALL_DIR/deploy/state"
printf 'TLS_ENABLED=true\n' > "$INSTALL_DIR/deploy/.env"
capture="$INSTALL_DIR/args.txt"
docker() { printf '%s\n' "$@" > "$capture"; }
compose ps
grep -Fxq "$INSTALL_DIR/compose.tls.yaml" "$capture"; count=$((count+1))
if grep -Fq 'compose.wings.yaml' "$capture"; then die 'Wings must be opt-in'; fi
count=$((count+1))
touch "$INSTALL_DIR/deploy/state/wings.enabled"
compose ps
grep -Fxq "$INSTALL_DIR/compose.wings.yaml" "$capture"; count=$((count+1))
printf 'TLS_ENABLED=false\n' > "$INSTALL_DIR/deploy/.env"
compose ps
if grep -Fq 'compose.tls.yaml' "$capture"; then die 'Unexpected TLS override'; fi
count=$((count+1))
printf 'PASS: %s installer validation/compose selection checks (no installation performed)\n' "$count"
