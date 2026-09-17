#!/usr/bin/env bash

all_in_one_wings() {
    local ip port memory disk host gateway subnet mode candidate container
    mode=$(backend)
    [[ -f $INSTALL_DIR/deploy/state/installed ]] || die 'Előbb fejezd be a panel telepítését a 8-as menüvel.'
    if [[ -f /etc/pterodactyl/config.yml && ! -f $INSTALL_DIR/deploy/state/local-wings-owned ]]; then
        die 'Meglévő Wings-konfiguráció található. Nem írom felül. A saját node-ot a panel adminfelületén kezeld.'
    fi
    read -r -p 'Játékszerver nyilvános IPv4-címe: ' ip
    read -r -p 'Első játékport [25565]: ' port; port=${port:-25565}
    read -r -p 'Node memória-keret MiB-ban [2048]: ' memory; memory=${memory:-2048}
    read -r -p 'Node lemezkeret MiB-ban [10240]: ' disk; disk=${disk:-10240}
    [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ && $port =~ ^[0-9]+$ && $memory =~ ^[0-9]+$ && $disk =~ ^[0-9]+$ ]] || die 'Hibás IPv4 vagy számbemenet.'
    printf 'A Wings API belső címen fut. Játékport: %s TCP/UDP, SFTP: 2022. A tűzfal és NAT portjait külön engedélyezd.\n' "$port"
    confirm 'Létrehozzam/frissítsem a helyi node-ot és indítsam a Wingst?' || return 0
    install_dependencies
    if ! docker network inspect alex-games >/dev/null 2>&1; then
        docker network create --driver bridge --label alex-panel.managed=true alex-games >/dev/null
    fi
    [[ $(docker network inspect alex-games --format '{{index .Labels "alex-panel.managed"}}') == true ]] || die 'Az alex-games hálózat nem ehhez a telepítőhöz tartozik.'
    gateway=$(docker network inspect alex-games --format '{{(index .IPAM.Config 0).Gateway}}')
    subnet=$(docker network inspect alex-games --format '{{(index .IPAM.Config 0).Subnet}}')
    host=127.0.0.1
    if [[ $mode == docker ]]; then
        host=$(docker network inspect alex-panel_default --format '{{(index .IPAM.Config 0).Gateway}}')
    fi
    mkdir -p /etc/pterodactyl /var/lib/pterodactyl /var/log/pterodactyl /tmp/pterodactyl
    candidate=$(mktemp /etc/pterodactyl/alex-config.XXXXXX)
    # Never echo this file: it contains the Wings authentication token.
    if ! panel_artisan p:installer:node --host="$host" --ip="$ip" --port="$port" --memory="$memory" --disk="$disk" --gateway="$gateway" --subnet="$subnet" > "$candidate"; then
        rm -f "$candidate"
        die 'A node konfigurálása sikertelen. Ellenőrizd az IPv4-címet, a kereteket és a panel naplóját.'
    fi
    [[ -s $candidate ]] || die 'Üres Wings-konfiguráció.'
    if [[ -f /etc/pterodactyl/config.yml ]]; then cp /etc/pterodactyl/config.yml /etc/pterodactyl/config.yml.previous; fi
    chmod 600 "$candidate"
    mv "$candidate" /etc/pterodactyl/config.yml
    touch "$INSTALL_DIR/deploy/state/local-wings-owned"
    if [[ $mode == docker ]]; then
        touch "$INSTALL_DIR/deploy/state/wings.enabled"
        compose build wings
        compose up -d wings
        compose exec -T panel /bin/sh -ec 'php /app/artisan p:remote-access:nginx --no-ansi > /etc/nginx/gateway/nodes.conf; nginx -t; nginx -s reload'
    else
        # Reuse the pinned Go build without installing a global Go compiler on the host.
        docker build --target build -t alex-wings-builder -f "$INSTALL_DIR/deploy/docker/Wings.Dockerfile" "$INSTALL_DIR"
        container=$(docker create --entrypoint /bin/true alex-wings-builder)
        docker cp "$container:/wings" /usr/local/bin/alex-wings
        docker rm "$container" >/dev/null
        chmod 755 /usr/local/bin/alex-wings
        cat > /etc/systemd/system/alex-wings.service <<'UNIT'
[Unit]
Description=Alex Wings game-server daemon
After=docker.service network-online.target
Requires=docker.service
[Service]
WorkingDirectory=/etc/pterodactyl
ExecStart=/usr/local/bin/alex-wings --config /etc/pterodactyl/config.yml
Restart=on-failure
RestartSec=5
LimitNOFILE=4096
[Install]
WantedBy=multi-user.target
UNIT
        systemctl daemon-reload
        systemctl enable --now alex-wings
        systemctl restart alex-wings
        /usr/local/sbin/alex-panel-gateway
    fi
    local ready=false
    for ((attempt=0; attempt<15; attempt++)); do
        if panel_artisan p:installer:node --check >/dev/null 2>&1; then ready=true; break; fi
        sleep 2
    done
    if [[ $ready != true ]]; then
        if [[ $mode == docker ]]; then compose logs --tail=40 wings; else journalctl --no-pager -n 40 -u alex-wings; fi
        die 'A Wings elindult, de a hitelesített panelkapcsolat még nem sikeres. Ellenőrizd a fenti naplót és a panel domain elérését.'
    fi
    printf '\nPanel + Wings kész. A helyi node és az első IP:port kiosztás létrejött. Most a panelben létrehozhatsz egy játékszervert.\n'
}
