#!/usr/bin/env bash
# Alex Panel installer. Original implementation; does not use pterodactyl-installer scripts.
set -Eeuo pipefail
umask 077
INSTALL_DIR=${INSTALL_DIR:-/opt/alex-panel}
PANEL_REPOSITORY=${PANEL_REPOSITORY:-https://github.com/Alex11e/pterodactylfork-panel.git}
PANEL_REF=${PANEL_REF:-1.0-develop}
INSTALL_BACKEND=docker
INSTALL_COMPONENTS=panel

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
valid_ipv4() {
    local part
    [[ $1 =~ ^[0-9]+(\.[0-9]+){3}$ ]] || return 1
    IFS=. read -r -a parts <<< "$1"
    for part in "${parts[@]}"; do [[ $part -le 255 ]] || return 1; done
}
valid_directory() { [[ $1 == /* && $1 != / && $1 != /etc && $1 != /usr && $1 != /var && $1 != *..* && $1 != *$'\n'* ]]; }
confirm() { local answer; read -r -p "$1 [i/N]: " answer; [[ $answer == i || $answer == I || $answer == y || $answer == Y ]]; }
compose() {
    local -a args=(--project-name alex-panel --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/deploy/.env" -f "$INSTALL_DIR/compose.yaml")
    if grep -qx 'TLS_ENABLED=true' "$INSTALL_DIR/deploy/.env"; then args+=(-f "$INSTALL_DIR/compose.tls.yaml"); fi
    if [[ -f $INSTALL_DIR/deploy/state/wings.enabled ]]; then args+=(-f "$INSTALL_DIR/compose.wings.yaml"); fi
    docker compose "${args[@]}" "$@"
}
existing() { [[ -f $INSTALL_DIR/deploy/.env ]] || die "Nincs telepítés itt: $INSTALL_DIR"; }
backend() {
    local mode=docker
    if [[ -f $INSTALL_DIR/deploy/state/backend ]]; then mode=$(cat "$INSTALL_DIR/deploy/state/backend"); fi
    case $mode in native|docker) printf '%s' "$mode" ;; *) die 'Érvénytelen mentett futtatási mód.' ;; esac
}
load_native() { source "$INSTALL_DIR/deploy/install/native.sh"; }
panel_artisan() {
    if [[ $(backend) == native ]]; then load_native; native_artisan "$@";
    else compose exec -T --workdir /app panel php /app/artisan "$@"; fi
}

install_wizard() {
    local tls=$1 choice
    printf '\nPanel futtatása:\n1) Docker Compose (ajánlott)\n2) Natív Nginx + PHP-FPM (Ubuntu 24.04 / Debian 12–13)\n'
    read -r -p 'Futtatási mód [1]: ' choice
    case ${choice:-1} in 1) INSTALL_BACKEND=docker ;; 2) INSTALL_BACKEND=native ;; *) die 'Érvénytelen futtatási mód.' ;; esac
    printf '\nÖsszetevők:\n1) Csak panel\n2) Panel + Wings egyben ezen a gépen\n'
    read -r -p 'Összetevők [1]: ' choice
    case ${choice:-1} in 1) INSTALL_COMPONENTS=panel ;; 2) INSTALL_COMPONENTS=all ;; *) die 'Érvénytelen összetevő.' ;; esac
    printf 'A Wings által indított játékok mindkét módban Docker-konténerekben futnak.\n'
    new_install "$tls"
}

install_local_wings() {
    existing
    [[ -f $INSTALL_DIR/deploy/install/all-in-one.sh ]] || die 'A Wings-varázslóhoz előbb frissíts a 8-as menüvel.'
    source "$INSTALL_DIR/deploy/install/all-in-one.sh"
    all_in_one_wings
}

show_status() {
    existing
    if [[ $(backend) == native ]]; then
        systemctl --no-pager status nginx mariadb redis-server alex-panel-queue alex-panel-scheduler alex-wings || true
        journalctl --no-pager -n 30 -u alex-panel-queue -u alex-panel-scheduler -u alex-wings
    else compose ps; compose logs --tail=40 panel; fi
}

restart_services() {
    existing
    if [[ $(backend) == native ]]; then
        local services=("php$(php -r 'echo PHP_MAJOR_VERSION,".",PHP_MINOR_VERSION;')-fpm" alex-panel-queue alex-panel-scheduler)
        [[ -f $INSTALL_DIR/deploy/state/local-wings-owned ]] && services+=(alex-wings)
        systemctl restart "${services[@]}"
        nginx -t && systemctl reload nginx
    else compose restart; fi
}

diagnose_install() {
    existing
    local mode url
    mode=$(backend)
    url=$(sed -n 's/^APP_URL=//p' "$INSTALL_DIR/deploy/.env" | tail -n 1)
    printf '\nAlex Panel diagnosztika\nMód: %s\nURL: %s\n\n' "$mode" "$url"
    printf 'Docker: '
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then printf 'OK\n'; else printf 'HIBA\n'; fi
    if [[ $mode == docker ]]; then
        printf 'Compose konfiguráció: '
        if compose config --quiet >/dev/null 2>&1; then printf 'OK\n'; else printf 'HIBA\n'; fi
        compose ps || true
        printf 'Panel HTTP: '
        if curl -fsS --max-time 5 http://127.0.0.1:8080/auth/login >/dev/null 2>&1; then printf 'OK\n'; else printf 'HIBA vagy nem localhostos port\n'; fi
    else
        printf 'Nginx konfiguráció: '
        if nginx -t >/dev/null 2>&1; then printf 'OK\n'; else printf 'HIBA\n'; fi
        for service in mariadb redis-server nginx alex-panel-queue alex-panel-scheduler; do
            printf '%-24s' "$service:"
            systemctl is-active --quiet "$service" && printf 'OK\n' || printf 'HIBA\n'
        done
        [[ -f $INSTALL_DIR/deploy/state/local-wings-owned ]] && { printf '%-24s' 'alex-wings:'; systemctl is-active --quiet alex-wings && printf 'OK\n' || printf 'HIBA\n'; }
    fi
    printf '\nBiztonság\nAPP_DEBUG: %s\nBind cím: %s\nTrusted proxies: %s\n' \
        "$(sed -n 's/^APP_DEBUG=//p' "$INSTALL_DIR/deploy/.env" | tail -n 1)" \
        "$(sed -n 's/^PANEL_BIND_IP=//p' "$INSTALL_DIR/deploy/.env" | tail -n 1)" \
        "$(sed -n 's/^TRUSTED_PROXIES=//p' "$INSTALL_DIR/deploy/.env" | tail -n 1)"
}

configure_tunnel() {
    existing
    local hostname env_file="$INSTALL_DIR/deploy/.env"
    read -r -p 'Cloudflare Tunnel hostname (pl. panel.example.hu): ' hostname
    valid_domain "$hostname" || die 'Érvénytelen Cloudflare hostname.'
    if ! command -v cloudflared >/dev/null 2>&1; then
        printf 'FIGYELEM: a cloudflared nincs telepítve. Az origin beállítható, de a Tunnelt külön kell telepíteni.\n'
    fi
    sed -i '/^APP_URL=/d;/^CLOUDFLARE_TUNNEL_HOSTNAME=/d' "$env_file"
    {
        printf 'APP_URL=https://%s\n' "$hostname"
        printf 'CLOUDFLARE_TUNNEL_HOSTNAME=%s\n' "$hostname"
    } >> "$env_file"
    chmod 0600 "$env_file"
    printf '\nOrigin: http://127.0.0.1:8080\nHostname: https://%s\n' "$hostname"
    printf 'A Tunnel ingress célja legyen: http://127.0.0.1:8080\n'
    if [[ $(backend) == docker ]]; then
        compose up -d --force-recreate --no-deps panel
    else
        restart_services
    fi
}

make_admin() {
    existing
    if [[ $(backend) == native ]]; then load_native; native_artisan p:user:make --admin=1;
    else compose exec --workdir /app panel php /app/artisan p:user:make --admin=1; fi
}

validate_source() {
    local root=$1 file
    for file in artisan composer.json composer.lock bootstrap/app.php config/app.php compose.yaml deploy/docker/Dockerfile deploy/docker/entrypoint.sh; do
        [[ -s $root/$file ]] || die "Hiányos panel-forrás: $root/$file. A 8-as menüponttal töltsd le újra a javított forrást."
    done
}

panel_version() {
    local source=$1
    sed -nE "s/.*'version'[[:space:]]*=>[[:space:]]*'([^']+)'.*/\1/p" "$source/config/app.php" | head -n 1
}

validate_repository() {
    [[ $PANEL_REPOSITORY == https://github.com/* && $PANEL_REPOSITORY != *$'\n'* ]] || die 'HTTPS GitHub-repó szükséges.'
    [[ -n $PANEL_REF && $PANEL_REF != -* && $PANEL_REF != *$'\n'* ]] || die 'Érvénytelen PANEL_REF.'
}

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
    if [[ -e $INSTALL_DIR ]]; then
        if [[ -f $INSTALL_DIR/deploy/.env ]]; then
            die 'Már létező Alex Panel telepítés található. A telepítő újratelepítés helyett a javítási módot használja; válaszd a 8-as menüt.'
        elif [[ -d $INSTALL_DIR/.git ]]; then
            die 'Félbemaradt Git-forrás található. A 8-as menüponttal állítsd helyre, vagy adj meg új INSTALL_DIR értéket; a könyvtárat nem töröltem.'
        else
            die 'A célkönyvtár már létezik és nem azonosítható Alex Panel-forrásként. Adj meg új INSTALL_DIR értéket; a könyvtárat nem módosítottam.'
        fi
    fi
    validate_repository
    # Stage beside the destination. Failed downloads never leave a broken INSTALL_DIR.
    local staging
    mkdir -p "$(dirname "$INSTALL_DIR")"
    staging=$(mktemp -d "${INSTALL_DIR}.download.XXXXXX")
    git -C "$staging" init --quiet
    git -C "$staging" remote add origin "$PANEL_REPOSITORY"
    git -C "$staging" fetch --depth 1 origin "$PANEL_REF" || die "Nem tölthető le a Git-ref: $PANEL_REF. Ellenőrizd a branch nevét és a hálózatot. Ideiglenes forrás: $staging"
    git -C "$staging" checkout --detach FETCH_HEAD || die 'A letöltött forrás nem állítható össze.'
    validate_source "$staging"
    mv -T "$staging" "$INSTALL_DIR"
}

remove_existing_install() {
    local mode=docker wings_owned=false
    [[ -f $INSTALL_DIR/deploy/state/backend ]] && mode=$(cat "$INSTALL_DIR/deploy/state/backend")
    [[ -f $INSTALL_DIR/deploy/state/local-wings-owned ]] && wings_owned=true
    case $mode in docker|native) ;; *) die 'Érvénytelen meglévő futtatási mód; a könyvtárat nem töröltem.' ;; esac
    printf '\nFIGYELEM: a teljes meglévő telepítés törlődik: %s\n' "$INSTALL_DIR"
    if [[ $wings_owned == true ]]; then
        printf 'A helyi Wings, a játék szerverek adatai, Docker-kötetei és a Wings-konfiguráció is törlődik.\n'
    else
        printf 'A művelet a panel adatbázisát és Docker-köteteit törölheti.\n'
    fi
    confirm 'Töröljem a meglévő telepítést és kezdjek tiszta telepítést?' || return 1
    if [[ $mode == docker ]]; then
        if command -v docker >/dev/null 2>&1 && [[ -f $INSTALL_DIR/deploy/.env ]]; then
            compose down --volumes --remove-orphans || true
        fi
    else
        for service in alex-wings alex-panel-queue alex-panel-scheduler alex-panel-gateway alex-panel-gateway.timer; do
            systemctl disable --now "$service" >/dev/null 2>&1 || true
        done
        rm -f /etc/systemd/system/alex-wings.service /etc/systemd/system/alex-panel-queue.service \
            /etc/systemd/system/alex-panel-scheduler.service /etc/systemd/system/alex-panel-gateway.service \
            /etc/systemd/system/alex-panel-gateway.timer /usr/local/bin/alex-wings /usr/local/sbin/alex-panel-gateway
        rm -f /etc/nginx/sites-enabled/alex-panel.conf /etc/nginx/sites-available/alex-panel.conf
        if command -v mariadb >/dev/null 2>&1; then
            mariadb -e "DROP DATABASE IF EXISTS alex_panel; DROP USER IF EXISTS 'alex_panel'@'localhost';" || true
        fi
        systemctl daemon-reload >/dev/null 2>&1 || true
        nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
    fi
    [[ $wings_owned == true ]] && remove_wings_resources "$mode"
    [[ $INSTALL_DIR == /* && $INSTALL_DIR != / && $INSTALL_DIR != /etc && $INSTALL_DIR != /usr && $INSTALL_DIR != /var ]] || die 'A törlendő könyvtár nem biztonságos.'
    rm -rf -- "$INSTALL_DIR"
}

remove_wings_resources() {
    local mode=$1 container
    if [[ $mode == docker ]] && command -v docker >/dev/null 2>&1; then
        while read -r container; do
            [[ -n $container ]] || continue
            docker rm -f "$container" >/dev/null 2>&1 || true
        done < <(docker ps -aq --filter network=alex-games)
        if docker network inspect alex-games >/dev/null 2>&1 && [[ $(docker network inspect alex-games --format '{{index .Labels "alex-panel.managed"}}') == true ]]; then
            docker network rm alex-games >/dev/null 2>&1 || true
        fi
        docker image rm alex-wings:local alex-wings-builder >/dev/null 2>&1 || true
    fi
    rm -rf -- /etc/pterodactyl /var/lib/pterodactyl /var/log/pterodactyl /tmp/pterodactyl
}

remove_wings_only() {
    existing
    [[ -f $INSTALL_DIR/deploy/state/local-wings-owned ]] || die 'A telepítő által kezelt helyi Wings nincs telepítve.'
    confirm 'A Wings konfigurációja, játék-konténerei és adatai is törlődnek. Folytatod?' || return 0
    local mode
    mode=$(backend)
    if [[ $mode == docker ]]; then
        compose down --remove-orphans || true
    else
        for service in alex-wings alex-panel-gateway alex-panel-gateway.timer; do
            systemctl disable --now "$service" >/dev/null 2>&1 || true
        done
        rm -f /etc/systemd/system/alex-wings.service /etc/systemd/system/alex-panel-gateway.service \
            /etc/systemd/system/alex-panel-gateway.timer /usr/local/bin/alex-wings /usr/local/sbin/alex-panel-gateway
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    remove_wings_resources "$mode"
    rm -f "$INSTALL_DIR/deploy/state/local-wings-owned" "$INSTALL_DIR/deploy/state/wings.enabled"
    printf 'A helyi Wings eltávolítása befejeződött; a panel és az adatbázisa megmaradt.\n'
}

refresh_source() {
    existing
    validate_repository
    [[ -d $INSTALL_DIR/.git ]] || die 'A javításhoz Gitből telepített panel kell.'
    [[ $(git -C "$INSTALL_DIR" remote get-url origin) == "$PANEL_REPOSITORY" ]] || die 'A telepítés forrásrepója eltér. Állítsd be a megfelelő PANEL_REPOSITORY értéket.'
    git -C "$INSTALL_DIR" diff --quiet || die 'Helyileg módosított forrásfájlok vannak. Mentsd/commitold őket a frissítés előtt.'
    git -C "$INSTALL_DIR" diff --cached --quiet || die 'Commitra váró módosítások vannak.'
    # Credentials, application key and named volumes stay in place.
    git -C "$INSTALL_DIR" fetch --depth 1 origin "$PANEL_REF" || die "Nem tölthető le a Git-ref: $PANEL_REF. A meglévő forrás megmaradt."
    git -C "$INSTALL_DIR" checkout --detach FETCH_HEAD || die 'A helyi fájlok miatt a frissítés nem alkalmazható. A meglévő adatokat megtartottam.'
    validate_source "$INSTALL_DIR"
}

repair_install() {
    existing
    confirm 'Készítsek mentést, majd töltsem le a javított forrást és frissítsem a panelt?' || return 0
    backup_panel
    refresh_source
    initialize_panel repair
}

restore_panel_backup() {
    existing
    local backup mode
    read -r -p "Mentés könyvtára [$INSTALL_DIR/deploy/backups]: " backup
    backup=${backup:-$INSTALL_DIR/deploy/backups}
    [[ ($backup == "$INSTALL_DIR/deploy/backups" || $backup == "$INSTALL_DIR/deploy/backups"/*) && -d $backup ]] || die 'Csak a telepítés backup könyvtárából lehet visszaállítani.'
    [[ -s $backup/panel.sql.gz && -s $backup/storage.tar.gz ]] || die 'A mentésből hiányzik a panel.sql.gz vagy a storage.tar.gz.'
    confirm 'A jelenlegi adatbázis és storage felülíródik. Folytatod?' || return 0
    mode=$(backend)
    if [[ $mode == docker ]]; then
        compose stop panel >/dev/null
        gzip -dc "$backup/panel.sql.gz" | compose exec -T database sh -ec 'exec env MYSQL_PWD="$MARIADB_PASSWORD" mariadb -u "$MARIADB_USER" "$MARIADB_DATABASE"'
        gzip -dc "$backup/storage.tar.gz" | compose run --rm -T --no-deps --entrypoint /bin/sh panel -ec 'tar -xzf - -C /app'
        compose up -d --wait --wait-timeout 180
    else
        load_native
        systemctl stop alex-panel-queue alex-panel-scheduler >/dev/null 2>&1 || true
        gzip -dc "$backup/panel.sql.gz" | mariadb alex_panel
        gzip -dc "$backup/storage.tar.gz" | tar -xzf - -C "$INSTALL_DIR"
        native_permissions
        systemctl start alex-panel-queue alex-panel-scheduler
    fi
    printf 'A panel backup visszaállítása befejeződött: %s\n' "$backup"
}

new_install() {
    local tls=$1 domain='' email='' app_url bind_ip=127.0.0.1 choice lan_address
    if [[ -f $INSTALL_DIR/deploy/.env ]]; then
        remove_existing_install || return 0
    elif [[ -e $INSTALL_DIR ]]; then
        printf '\nFélbemaradt vagy ismeretlen könyvtár található: %s\n' "$INSTALL_DIR"
        confirm 'Töröljem ezt a könyvtárat és kezdjek tiszta telepítést?' || return 0
        [[ $INSTALL_DIR == /* && $INSTALL_DIR != / && $INSTALL_DIR != /etc && $INSTALL_DIR != /usr && $INSTALL_DIR != /var ]] || die 'A törlendő könyvtár nem biztonságos.'
        rm -rf -- "$INSTALL_DIR"
    fi
    if [[ $tls == true ]]; then
        read -r -p 'Panel domain (pl. panel.pelda.hu): ' domain
        valid_domain "$domain" || die 'Érvénytelen domain.'
        read -r -p 'E-mail a HTTPS-tanúsítványhoz: ' email
        valid_email "$email" || die 'Érvénytelen e-mail-cím.'
        app_url="https://$domain"
        printf 'A domain DNS-e erre a gépre mutasson; a 80/443 port legyen szabad és elérhető.\n'
    else
        printf '\nHelyi elérés:\n1) Csak ezen a gépen (localhost)\n2) Helyi hálózaton is elérhető\n'
        read -r -p 'Elérés [1]: ' choice
        case ${choice:-1} in
            1)
                app_url=http://localhost:8080
                printf 'HTTP mód: csak localhost:8080.\n'
                ;;
            2)
                read -r -p 'A gép LAN IPv4-címe (például 192.168.1.20): ' lan_address
                valid_ipv4 "$lan_address" || die 'Érvénytelen LAN IPv4-cím.'
                bind_ip=0.0.0.0
                app_url="http://$lan_address:8080"
                printf 'HTTP mód: a helyi hálózaton elérhető lesz a %s címen. Internet felől ne engedd át a 8080-as portot.\n' "$app_url"
                ;;
            *) die 'Érvénytelen helyi elérési mód.' ;;
        esac
    fi
    printf '\nCél: %s\nForrás: %s (%s)\nPanel: %s\nMód: %s / %s\n' "$INSTALL_DIR" "$PANEL_REPOSITORY" "$PANEL_REF" "$app_url" "$INSTALL_BACKEND" "$INSTALL_COMPONENTS"
    confirm 'Telepítsem a panelt és a kiválasztott összetevőket?' || return 0
    if [[ $INSTALL_BACKEND == docker ]]; then install_dependencies;
    else
        . /etc/os-release
        case "$ID:$VERSION_ID" in ubuntu:24.04|debian:12|debian:13) ;; *) die 'Nem támogatott natív rendszer. Használd a Docker módot.' ;; esac
        apt-get update
        apt-get install -y ca-certificates curl git openssl
    fi
    fetch_source
    local panel_version_value
    panel_version_value=$(panel_version "$INSTALL_DIR")
    [[ -n $panel_version_value ]] || die 'A panel verziója nem olvasható ki a letöltött forrásból.'
    mkdir -p "$INSTALL_DIR/deploy/state"
    printf '%s\n' "$INSTALL_BACKEND" > "$INSTALL_DIR/deploy/state/backend"
    printf '%s\n' "$INSTALL_COMPONENTS" > "$INSTALL_DIR/deploy/state/components"
    [[ ! -e $INSTALL_DIR/deploy/.env ]] || die 'A deploy/.env már létezik; a kulcsokat nem módosítom.'
    {
        printf 'APP_URL=%s\nAPP_KEY=base64:%s\nHASHIDS_SALT=%s\n' "$app_url" "$(openssl rand -base64 32)" "$(openssl rand -hex 24)"
        printf 'DB_PASSWORD=%s\nDB_ROOT_PASSWORD=%s\n' "$(openssl rand -hex 32)" "$(openssl rand -hex 32)"
        printf 'APP_TIMEZONE=Europe/Budapest\nPANEL_BIND_IP=%s\nPANEL_PORT=8080\n' "$bind_ip"
            printf 'APP_TIMEZONE=Europe/Budapest\nPANEL_BIND_IP=%s\nPANEL_PORT=8080\nPANEL_BACKEND=%s\n' "$bind_ip" "$INSTALL_BACKEND"
        printf 'TLS_ENABLED=%s\nPANEL_DOMAIN=%s\nACME_EMAIL=%s\nMAIL_MAILER=log\n' "$tls" "$domain" "$email"
    } > "$INSTALL_DIR/deploy/.env"
    chmod 0600 "$INSTALL_DIR/deploy/.env"
    initialize_panel
    if [[ $INSTALL_COMPONENTS == all ]]; then install_local_wings; fi
    printf '\nA panel elindult: %s\nPanel verzió: %s\nA kulcsokat őrizd meg: %s/deploy/.env\nSMTP még nincs beállítva; a log mailer nem küld levelet.\n' "$app_url" "$panel_version_value" "$INSTALL_DIR"
}

initialize_panel() {
    existing
    if [[ $(backend) == native ]]; then load_native; native_initialize; return; fi
    validate_source "$INSTALL_DIR"
    local was_installed=false
    [[ ! -f $INSTALL_DIR/deploy/state/installed ]] || was_installed=true
    [[ $was_installed == false || ${1:-} == repair ]] || die 'Ez a telepítés már inicializált. Javításhoz a 8-as, adminfiókhoz a 6-os menüt használd.'
    mkdir -p "$INSTALL_DIR/deploy/state"
    compose config --quiet
    compose build panel
    # Verify the actual image before starting migrations; bypass the app entrypoint.
    compose run --rm --no-deps --entrypoint /bin/sh panel -ec 'test -s /app/artisan && test -s /app/vendor/autoload.php && test -s /app/public/assets/manifest.json' || die 'Hiányos Docker image: artisan/vendor/frontend. A build naplóját ellenőrizd.'
    compose up -d --wait database redis
    compose run --rm --workdir /app panel php /app/artisan migrate --force
    if [[ $was_installed == false && ! -f $INSTALL_DIR/deploy/state/seeded ]]; then
        compose run --rm --workdir /app panel php /app/artisan db:seed --force
        touch "$INSTALL_DIR/deploy/state/seeded"
    fi
    compose up -d --wait --wait-timeout 180
    touch "$INSTALL_DIR/deploy/state/installed"
    if [[ $was_installed == false ]]; then
        printf '\nAdminisztrátori fiók létrehozása (a jelszó nem kerül parancssori argumentumba):\n'
        compose exec --workdir /app panel php /app/artisan p:user:make --admin=1
    fi
    printf '\nA panel ellenőrzött konténere elindult. Adminfiók létrehozásához később a 6-os menüt használd.\n'
}

setup_wings() {
    existing
    if [[ $(backend) == native ]]; then install_local_wings; return; fi
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
    if [[ $(backend) == native ]]; then load_native; native_backup; return; fi
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
    exec 9>/var/lock/alex-panel-installer.lock
    flock -n 9 || die 'Egy másik Alex Panel telepítés már fut. Várd meg a befejezését.'
    valid_directory "$INSTALL_DIR" || die 'Érvénytelen INSTALL_DIR.'
    printf '\nAlex Panel – magyar konzol, PufferPanel-szerű proxy és Docker\n\n1) Új panel HTTPS-sel\n2) Új panel helyi HTTP teszthez\n3) Helyi Wings automatikus beállítása\n4) Panel adatbázis + storage mentése\n5) Állapot és naplók\n6) Admin felhasználó létrehozása\n7) Szolgáltatások újraindítása\n8) Mentés, frissítés és telepítés javítása\n9) Diagnosztika\n10) Cloudflare Tunnel URL beállítása\n11) Helyi Wings teljes eltávolítása\n12) Panel backup visszaállítása\n0) Kilépés\n'
    local choice
    read -r -p 'Választás: ' choice
    case $choice in
        1) install_wizard true ;;
        2) install_wizard false ;;
        3) install_local_wings ;;
        4) backup_panel ;;
        5) show_status ;;
        6) make_admin ;;
        7) restart_services ;;
        8) repair_install ;;
        9) diagnose_install ;;
        10) configure_tunnel ;;
        11) remove_wings_only ;;
        12) restore_panel_backup ;;
        0) return ;;
        *) die 'Érvénytelen menüpont.' ;;
    esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    trap 'printf "\nA művelet megszakadt. Az adatokat és köteteket nem töröltem; ellenőrizd a fenti hibát.\n" >&2' ERR
    main "$@"
fi
