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

# Execute initialization with a fake Docker transport, testing ordering and persisted state.
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
validate_source "$repo_root"
[[ $PANEL_REF == 1.0-develop ]] || die 'Default branch must exist in the fork'
for file in artisan composer.json composer.lock bootstrap/app.php config/app.php compose.yaml deploy/docker/Dockerfile deploy/docker/entrypoint.sh; do
    mkdir -p "$INSTALL_DIR/$(dirname "$file")"
    printf 'fixture\n' > "$INSTALL_DIR/$file"
done
capture="$INSTALL_DIR/calls.txt"
docker() { printf '%s\n' "$*" >> "$capture"; }
initialize_panel
grep -q 'php /app/artisan migrate --force' "$capture"
grep -q 'php /app/artisan db:seed --force' "$capture"
grep -q 'test -s /app/artisan' "$capture"
[[ -f $INSTALL_DIR/deploy/state/installed && -f $INSTALL_DIR/deploy/state/seeded ]]
before=$(cat "$INSTALL_DIR/deploy/.env")
: > "$capture"
initialize_panel repair
[[ $(cat "$INSTALL_DIR/deploy/.env") == "$before" ]]
if grep -q 'db:seed\|p:user:make' "$capture"; then die 'Repair must not reseed or create a duplicate admin'; fi
# A missing source entrypoint fails before Docker is called.
mv "$INSTALL_DIR/artisan" "$INSTALL_DIR/artisan.saved"
: > "$capture"
if (initialize_panel repair) 2>/dev/null; then die 'Incomplete source was accepted'; fi
[[ ! -s $capture ]]
mv "$INSTALL_DIR/artisan.saved" "$INSTALL_DIR/artisan"
# A corrupt image must fail before any migration.
docker() {
    printf '%s\n' "$*" >> "$capture"
    if [[ " $* " == *' --entrypoint /bin/sh '* ]]; then return 1; fi
}
: > "$capture"
if (initialize_panel repair) 2>/dev/null; then die 'Incomplete image was accepted'; fi
if grep -q 'migrate --force' "$capture"; then die 'Migrated with incomplete image'; fi
printf 'PASS: source/image guards, first installation, repair ordering and credential preservation\n'

# Real Git fixture: download and refresh without depending on a public GitHub branch.
fixture=$(mktemp -d "${TMPDIR:-/tmp}/alex-git-fixture.XXXXXX")
command git -C "$fixture" init --quiet -b 1.0-develop
for file in artisan composer.json composer.lock bootstrap/app.php config/app.php compose.yaml deploy/docker/Dockerfile deploy/docker/entrypoint.sh; do
    mkdir -p "$fixture/$(dirname "$file")"
    printf 'fixture\n' > "$fixture/$file"
done
command git -C "$fixture" add .
command git -C "$fixture" -c user.name=InstallerTest -c user.email=test@example.invalid commit -qm fixture
git() {
    if [[ ${3:-} == fetch ]]; then
        command git -c core.autocrlf=false -C "$2" fetch --depth 1 "$fixture" "${@: -1}"
    else
        command git -c core.autocrlf=false "$@"
    fi
}
INSTALL_DIR="$(dirname "$fixture")/alex-download-$RANDOM-$RANDOM"
PANEL_REF=missing-branch
if (fetch_source) >/dev/null 2>&1; then die 'Missing branch was accepted'; fi
[[ ! -e $INSTALL_DIR ]] || die 'Failed fetch polluted final installation directory'
PANEL_REF=1.0-develop
fetch_source
validate_source "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/deploy"
printf 'APP_KEY=keep-this-test-key\n' > "$INSTALL_DIR/deploy/.env"
printf 'updated\n' > "$fixture/artisan"
command git -C "$fixture" add artisan
command git -C "$fixture" -c user.name=InstallerTest -c user.email=test@example.invalid commit -qm update
refresh_source
grep -qx updated "$INSTALL_DIR/artisan"
grep -qx APP_KEY=keep-this-test-key "$INSTALL_DIR/deploy/.env"
printf 'local edit\n' > "$INSTALL_DIR/artisan"
if (refresh_source) >/dev/null 2>&1; then die 'Local changes were overwritten'; fi
grep -qx 'local edit' "$INSTALL_DIR/artisan"
echo 'PASS: staged downloads, missing branch recovery, source refresh and local-edit protection'

# Selecting a new-install menu on an existing installation now routes to repair
# mode instead of attempting to overwrite the destination directory.
INSTALL_DIR=$(mktemp -d "${TMPDIR:-/tmp}/alex-existing-install.XXXXXX")
mkdir -p "$INSTALL_DIR/deploy"
printf 'APP_KEY=preserve-me\n' > "$INSTALL_DIR/deploy/.env"
repair_marker="$(dirname "$INSTALL_DIR")/repair-called-$RANDOM"
confirm() { return 0; }
remove_existing_install() { touch "$repair_marker"; rm -rf -- "$INSTALL_DIR"; }
install_dependencies() { :; }
fetch_source() {
    mkdir -p "$INSTALL_DIR/config"
    printf "<?php\nreturn ['version' => 'test'];\n" > "$INSTALL_DIR/config/app.php"
}
initialize_panel() { :; }
INSTALL_COMPONENTS=panel
new_install false <<'INPUT'
1
INPUT
[[ -f $repair_marker && -f $INSTALL_DIR/deploy/.env ]] || die 'Existing install was not replaced cleanly'
echo 'PASS: existing installation is removed and recreated from the new-install menu'

# An explicit clean install removes only the validated installation directory.
INSTALL_DIR=$(mktemp -d "${TMPDIR:-/tmp}/alex-delete-install.XXXXXX")
mkdir -p "$INSTALL_DIR/deploy/state"
printf 'docker\n' > "$INSTALL_DIR/deploy/state/backend"
printf 'APP_KEY=delete-me\n' > "$INSTALL_DIR/deploy/.env"
confirm() { return 0; }
compose() { return 0; }
remove_existing_install
[[ ! -e $INSTALL_DIR ]] || die 'Clean install did not remove the requested directory'
echo 'PASS: clean install removes the existing installation after confirmation'
