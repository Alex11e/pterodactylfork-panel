#!/usr/bin/env bash

all_in_one_wings() {
    local ip port memory disk host panel_host panel_url gateway subnet mode candidate container binary previous_config
    mode=$(backend)
    [[ -f $INSTALL_DIR/deploy/state/installed ]] || die 'Előbb fejezd be a panel telepítését a 8-as menüvel.'
    local existing_wings_config
    existing_wings_config=$(sed -n 's/^WINGS_CONFIG_DIR=//p' "$INSTALL_DIR/deploy/.env" | tail -n 1)
    [[ -n $existing_wings_config ]] || existing_wings_config="$INSTALL_DIR/deploy/wings"
    if [[ -f $existing_wings_config/config.yml && ! -f $INSTALL_DIR/deploy/state/local-wings-owned ]]; then
        case $existing_wings_config in
            "$INSTALL_DIR"/deploy/*) ;;
            *) die "Meglévő Wings-konfiguráció található: $existing_wings_config/config.yml. Nem írom felül." ;;
        esac
    fi
    read -r -p 'Játékszerver nyilvános IPv4-címe: ' ip
    read -r -p 'Első játékport [25565]: ' port; port=${port:-25565}
    read -r -p 'Új node memória-kerete MiB-ban [2048; meglévőnél megmarad]: ' memory; memory=${memory:-2048}
    read -r -p 'Új node lemezkerete MiB-ban [10240; meglévőnél megmarad]: ' disk; disk=${disk:-10240}
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
    panel_url=$(sed -n 's/^APP_URL=//p' "$INSTALL_DIR/deploy/.env" | tail -n 1)
    panel_host=${panel_url#*://}
    panel_host=${panel_host%%/*}
    panel_host=${panel_host%%:*}
    host=$panel_host
    if [[ $host == localhost || $host == 127.0.0.1 || ! $host =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
        host=127.0.0.1
    fi
    if [[ $mode == docker && ($host == 127.0.0.1 || $host == localhost) ]]; then
        host=$(docker network inspect alex-panel_default --format '{{(index .IPAM.Config 0).Gateway}}')
    fi
    local wings_config_dir
    wings_config_dir=$(sed -n 's/^WINGS_CONFIG_DIR=//p' "$INSTALL_DIR/deploy/.env" | tail -n 1)
    [[ -n $wings_config_dir ]] || wings_config_dir="$INSTALL_DIR/deploy/wings"
    mkdir -p "$wings_config_dir" /var/lib/pterodactyl /var/log/pterodactyl /tmp/pterodactyl
    if [[ -f $existing_wings_config/config.yml ]]; then
        printf 'A saját régi Wings konfigurációt törlöm és teljesen újraírom: %s/config.yml\n' "$existing_wings_config"
        previous_config="$existing_wings_config/config.yml.previous"
        cp "$existing_wings_config/config.yml" "$previous_config"
        rm -f "$existing_wings_config/config.yml"
    fi
    candidate=$(mktemp "$wings_config_dir/alex-config.XXXXXX")
    # Never echo this file: it contains the Wings authentication token.
    if ! panel_artisan p:installer:node --host="$host" --ip="$ip" --port="$port" --memory="$memory" --disk="$disk" --gateway="$gateway" --subnet="$subnet" > "$candidate"; then
        rm -f "$candidate"
        die 'A node konfigurálása sikertelen. Ellenőrizd az IPv4-címet, a kereteket és a panel naplóját.'
    fi
    [[ -s $candidate ]] || die 'Üres Wings-konfiguráció.'
    for required in uuid token_id token api system remote; do
        grep -q "^$required:" "$candidate" || {
            rm -f "$candidate"
            [[ -f ${previous_config:-} ]] && mv "$previous_config" "$wings_config_dir/config.yml"
            die "Hiányos Wings konfiguráció: hiányzik a(z) $required mező."
        }
    done
    chmod 600 "$candidate"
    mv "$candidate" "$wings_config_dir/config.yml"
    rm -f "${previous_config:-}"
    touch "$INSTALL_DIR/deploy/state/local-wings-owned"
    if [[ $mode == docker ]]; then
        touch "$INSTALL_DIR/deploy/state/wings.enabled"
        compose build wings
        compose up -d --force-recreate wings
        compose exec -T panel /bin/sh -ec 'php /app/artisan p:remote-access:nginx --no-ansi > /etc/nginx/gateway/nodes.conf; nginx -t; nginx -s reload'
    else
        # Reuse the pinned Go build without installing a global Go compiler on the host.
        docker build --target build -t alex-wings-builder -f "$INSTALL_DIR/deploy/docker/Wings.Dockerfile" "$INSTALL_DIR"
        container=$(docker create --entrypoint /bin/true alex-wings-builder)
        binary=$(mktemp /usr/local/bin/alex-wings.XXXXXX)
        docker cp "$container:/wings" "$binary"
        docker rm "$container" >/dev/null
        chmod 755 "$binary"
        mv -f "$binary" /usr/local/bin/alex-wings
        cat > /etc/systemd/system/alex-wings.service <<UNIT
[Unit]
Description=Alex Wings game-server daemon
After=docker.service network-online.target
Requires=docker.service
[Service]
WorkingDirectory=$wings_config_dir
ExecStart=/usr/local/bin/alex-wings --config $wings_config_dir/config.yml
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
