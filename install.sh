#!/usr/bin/env bash
# Alex Panel installer. Original implementation; does not use pterodactyl-installer scripts.
set -Eeuo pipefail
umask 077
INSTALL_DIR=${INSTALL_DIR:-/opt/alex-panel}
PANEL_REPOSITORY=${PANEL_REPOSITORY:-https://github.com/Alex11e/pterodactylfork-panel.git}
PANEL_REF=${PANEL_REF:-feature/puffer-docker-hu}

die() { printf '\nHIBA: %s\n' "$*" >&2; exit 1; }
need_root() { [[ $EUID -eq 0 ]] || die 'Root jogosultság kell. Előbb: sudo -i'; }
valid_domain() {
    local label
    [[ ${#1} -le 253 && $1 == *.* && $1 != *..* && $1 != *. && $1 != .* ]] || return 1
    local -a labels
    IFS=. read -r -a labels <<< "$1"
    for label in "${labels[@]}"; do
        [[ ${#label} -le 63 && $label =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] || return 1
    done
}
valid_email() { [[ $1 =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; }
valid_directory() { [[ $1 == /* && $1 != / && $1 != /etc && $1 != /usr && $1 != /var && $1 != *..* && $1 != *$'\n'* ]]; }
confirm() { local answer; read -r -p "$1 [i/N]: " answer; [[ $answer == i || $answer == I || $answer == y || $answer == Y ]]; }
compose() {
    local -a args=(--project-name alex-panel --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/deploy/.env" -f "$INSTALL_DIR/compose.yaml")
    if grep -qx 'TLS_ENABLED=true' "$INSTALL_DIR/deploy/.env"; then args+=(-f "$INSTALL_DIR/compose.tls.yaml"); fi
    if [[ -f $INSTALL_DIR/deploy/state/wings.enabled ]]; then args+=(-f "$INSTALL_DIR/compose.wings.yaml"); fi
    docker compose "${args[@]}" "$@"
}
existing() { [[ -f $INSTALL_DIR/deploy/.env ]] || die "Nincs telepítés itt: $INSTALL_DIR"; }

install_dependencies() {
    # OS metadata is owned by the operating system, never fetched from the network.
    . /etc/os-release
    [[ $ID == ubuntu || $ID == debian ]] || die 'Az automatikus telepítő Debian és Ubuntu rendszert támogat. Máshol a Compose-útmutatót kövesd.'
    apt-get update
    apt-get install -y ca-certificates curl git openssl
    if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
        # Refuse to remove conflicting packages or replace an existing Docker installation.
        if command -v docker >/dev/null; then die 'A Docker már telepítve van, de a Compose plugin hiányzik. Telepítsd a docker-compose-plugin csomagot, majd futtasd újra.'; fi
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL --proto '=https' "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/alex-docker.asc
        chmod 0644 /etc/apt/keyrings/alex-docker.asc
        printf 'deb [arch=%s signed-by=/etc/apt/keyrings/alex-docker.asc] https://download.docker.com/linux/%s %s stable\n' \
            "$(dpkg --print-architecture)" "$ID" "${UBUNTU_CODENAME:-$VERSION_CODENAME}" > /etc/apt/sources.list.d/alex-docker.list
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    systemctl enable --now docker
    docker info >/dev/null
}

fetch_source() {
    valid_directory "$INSTALL_DIR" || die 'Érvénytelen telepítési könyvtár.'
    [[ ! -e $INSTALL_DIR ]] || die 'A célkönyvtár már létezik. A telepítő nem írja felül; adj meg új INSTALL_DIR értéket vagy használd a meglévő telepítés menüjét.'
    [[ $PANEL_REPOSITORY == https://github.com/* && $PANEL_REPOSITORY != *$'\n'* ]] || die 'HTTPS GitHub-repó szükséges.'
    git clone --no-checkout --filter=blob:none "$PANEL_REPOSITORY" "$INSTALL_DIR"
    git -C "$INSTALL_DIR" fetch --depth 1 origin "$PANEL_REF"
    git -C "$INSTALL_DIR" checkout --detach FETCH_HEAD
    [[ -f $INSTALL_DIR/compose.yaml && -f $INSTALL_DIR/deploy/docker/Dockerfile ]] || die 'A kiválasztott Git-ref nem tartalmazza az Alex Panel Docker-csomagot.'
}

new_install() {
    local tls=$1 domain='' email='' app_url bind_ip=127.0.0.1
    if [[ $tls == true ]]; then
        read -r -p 'Panel domain (pl. panel.pelda.hu): ' domain
        valid_domain "$domain" || die 'Érvénytelen domain.'
        read -r -p 'E-mail a HTTPS-tanúsítványhoz: ' email
        valid_email "$email" || die 'Érvénytelen e-mail-cím.'
        app_url="https://$domain"
        printf 'A domain DNS-e erre a gépre mutasson; a 80/443 port legyen szabad és elérhető.\n'
    else
        app_url=http://localhost:8080
        printf 'HTTP tesztmód: csak localhost:8080, távoli eléréshez SSH-tunnel kell. Éles használathoz a HTTPS-módot válaszd.\n'
    fi
    printf '\nCél: %s\nForrás: %s (%s)\nPanel: %s\n' "$INSTALL_DIR" "$PANEL_REPOSITORY" "$PANEL_REF" "$app_url"
    confirm 'Telepítsem a Docker-alapú panelt és a szükséges csomagokat?' || return 0
    install_dependencies
    fetch_source
    mkdir -p "$INSTALL_DIR/deploy/state"
    [[ ! -e $INSTALL_DIR/deploy/.env ]] || die 'A deploy/.env már létezik; a kulcsokat nem módosítom.'
    {
        printf 'APP_URL=%s\nAPP_KEY=base64:%s\nHASHIDS_SALT=%s\n' "$app_url" "$(openssl rand -base64 32)" "$(openssl rand -hex 24)"
        printf 'DB_PASSWORD=%s\nDB_ROOT_PASSWORD=%s\n' "$(openssl rand -hex 32)" "$(openssl rand -hex 32)"
        printf 'APP_TIMEZONE=Europe/Budapest\nPANEL_BIND_IP=%s\nPANEL_PORT=8080\n' "$bind_ip"
        printf 'TLS_ENABLED=%s\nPANEL_DOMAIN=%s\nACME_EMAIL=%s\nMAIL_MAILER=log\n' "$tls" "$domain" "$email"
    } > "$INSTALL_DIR/deploy/.env"
    chmod 0600 "$INSTALL_DIR/deploy/.env"
    initialize_panel
    printf '\nA panel elindult: %s\nA kulcsokat őrizd meg: %s/deploy/.env\nSMTP még nincs beállítva; a log mailer nem küld levelet.\n' "$app_url" "$INSTALL_DIR"
}

initialize_panel() {
    existing
    [[ ! -f $INSTALL_DIR/deploy/state/installed ]] || die 'Ez a telepítés már inicializált. Az adminfiókhoz a 6-os menüt használd.'
    compose build panel
    compose up -d --wait database redis
    compose run --rm panel php artisan migrate --seed --force
    compose up -d --wait --wait-timeout 180
    touch "$INSTALL_DIR/deploy/state/installed"
    printf '\nAdminisztrátori fiók létrehozása (a jelszó nem kerül parancssori argumentumba):\n'
    compose exec panel php artisan p:user:make --admin=1
}

setup_wings() {
    existing
    [[ -f /etc/pterodactyl/config.yml ]] || die 'Előbb készíts node-ot a panel adminfelületén, majd mentsd a node konfigurációját az /etc/pterodactyl/config.yml fájlba. Részletek: DOCKER-HU.md.'
    printf 'A Wings a host Docker socketjét és azonos host-adatútvonalakat kapja. A panel belső node-címe: host.docker.internal:8081 (HTTP).\n'
    printf 'A config api.port legyen 8081; az api.host a Docker bridge belső címe, ne 127.0.0.1.\n'
    confirm 'Indítsam a Wings konténert a meglévő konfigurációval?' || return 0
    mkdir -p "$INSTALL_DIR/deploy/state" /var/lib/pterodactyl /var/log/pterodactyl /tmp/pterodactyl
    touch "$INSTALL_DIR/deploy/state/wings.enabled"
    compose build wings
    compose up -d wings
    compose logs --tail=30 wings
    printf 'A Wings folyamat elindítását kértem. A sikeres panelkapcsolatot a naplóban és a node állapotában ellenőrizd.\n'
}

backup_panel() {
    existing
    local target="$INSTALL_DIR/deploy/backups/$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "$target"
    cp "$INSTALL_DIR/deploy/.env" "$target/deploy.env"
    # No secrets in argv or stdout. Keep the app key with the database backup.
    compose exec -T database sh -c 'exec env MYSQL_PWD="$MARIADB_PASSWORD" mariadb-dump -u "$MARIADB_USER" --single-transaction --routines --triggers "$MARIADB_DATABASE"' | gzip > "$target/panel.sql.gz"
    compose exec -T panel tar -czf - -C /app storage > "$target/storage.tar.gz"
    git -C "$INSTALL_DIR" rev-parse HEAD > "$target/source-commit.txt"
    printf 'Panelmentés: %s\nEz nem tartalmazza a játékszerverek fájljait. A mentés érzékeny adatokat és titkosítási kulcsot tartalmaz.\n' "$target"
}

main() {
    case ${1:-} in
        --help|-h) printf 'Alex Panel interaktív telepítő. Root Debian/Ubuntu Linux szükséges.\nVáltozók: INSTALL_DIR, PANEL_REPOSITORY, PANEL_REF.\n'; return ;;
        '') ;;
        *) die 'Ismeretlen argumentum. Használd: --help' ;;
    esac
    need_root
    valid_directory "$INSTALL_DIR" || die 'Érvénytelen INSTALL_DIR.'
    printf '\nAlex Panel – magyar konzol, PufferPanel-szerű proxy és Docker\n\n1) Új panel HTTPS-sel\n2) Új panel helyi HTTP teszthez\n3) Wings konténer beállítása\n4) Panel adatbázis + storage mentése\n5) Állapot és naplók\n6) Admin felhasználó létrehozása\n7) Szolgáltatások újraindítása\n8) Megszakadt új telepítés folytatása\n0) Kilépés\n'
    local choice
    read -r -p 'Választás: ' choice
    case $choice in
        1) new_install true ;;
        2) new_install false ;;
        3) setup_wings ;;
        4) backup_panel ;;
        5) existing; compose ps; compose logs --tail=40 panel ;;
        6) existing; compose exec panel php artisan p:user:make --admin=1 ;;
        7) existing; compose restart ;;
        8) initialize_panel ;;
        0) return ;;
        *) die 'Érvénytelen menüpont.' ;;
    esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    trap 'printf "\nA művelet megszakadt. Az adatokat és köteteket nem töröltem; ellenőrizd a fenti hibát.\n" >&2' ERR
    main "$@"
fi
