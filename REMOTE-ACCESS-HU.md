# Alex Pterodactyl – PufferPanelhez hasonló proxy mód

Ebben a változatban a böngésző **csak a panel címéhez kapcsolódik**. A konzol
WebSocket-forgalmát, a fájlfeltöltést, a fájlletöltést és a helyi mentések
letöltését a panel nginx szervere továbbítja a belső Wings-címre.

```text
Böngésző → https://panel.example.com/_wings/1/... → belső Wings:8080
         → a panel szokásos API-ja             → belső Wings:8080
```

A node-nak nem kell külön publikus domain vagy a böngésző által elérhető port.
A panel nginx szerverének és PHP backendjének viszont el kell érnie a Wingst.
Ez a PufferPanel közvetítési modelljét követi. A PufferPanel Go proxyt használ,
itt a Laravel panel mellett az nginx végzi a tartós kapcsolat továbbítását.
PufferPanel-kódot nem másoltunk át; a Wings protokollja változatlan.

## Mit tartalmaz a csomag?

- Módosított panel-forrás és az eredeti repoállapotra alkalmazható patch.
- A megadott Wings-repo változatlan forrása; új Wings bináris nem szükséges.
- Node-onként automatikusan generált nginx útvonalak.
- Proxyzott konzol, parancsok, élő státuszok és WebSocket-tokenfrissítés.
- Proxyzott fájlfeltöltés, fájlletöltés és helyi mentések letöltése.
- Diagnosztikai parancs, regressziós tesztek és külön gateway CI workflow.
- Docker Compose és saját telepítő: lásd `DOCKER-HU.md`.
- Magyar fő navigáció és konzolkényelmi funkciók.
- Cloudflare aldomain-kezelő: lásd `SUBDOMAINS-HU.md`.

Az S3-mentések a meglévő, aláírt S3-URL-t használják. SFTP és a játék saját
TCP/UDP-portjai külön kapcsolatot igényelnek, ezek nem WebSocket/HTTP-szolgáltatások.
Ez a csomag nem tartalmaz vizuális áttervezést, előre fordított frontend asseteket
vagy Composer-függőségeket.

## 1. A kód alkalmazása

Panel alap: `113ea43d0d48f48d567c9d91e4a7d5b5bb8876e3`
(https://github.com/Alex11e/pterodactylfork-panel).
Wings alap: `d6116827313dae176ddf4741e233554392993398`
(https://github.com/Alex11e/wings).
Összehasonlított PufferPanel: `5dd773fad51922fe0d0d1d2e228d32ce699e0820`
(https://github.com/Alex11e/pufferpanel), `services/node.go`.

A patch a felhasználó panelrepójának fenti állapotához készült, nem tetszőleges
Pterodactyl-verzióhoz. Tiszta checkouton, először tesztkörnyezetben:

```bash
git switch -c feature/puffer-style-gateway
git apply --check /eleresi/ut/panel-remote-access.patch
git apply /eleresi/ut/panel-remote-access.patch
php tests/remote-access.php
php tests/gateway-config.php
```

Ha az előző, közvetlen Wings-elérésű csomag patchét már alkalmaztad, azt előbb
ellenőrzött `git apply -R` művelettel vond vissza, és utána alkalmazd ezt az
összesített patch-et. Az új csomag felváltja az előzőt.
A módosításhoz nincs új adatbázis-migráció vagy frontend-újrafordítás.
Friss teljes forrástelepítéshez az eredeti panel telepítési lépései továbbra is
kellenek: https://pterodactyl.io/panel/1.0/getting_started.html

## 2. Belső Wings-cím

Az adminfelületen a node FQDN/protokoll/port értéke a panelből ÉS a panel nginx
szerveréből elérhető Wings-cím legyen. Példák:

- Ugyanazon a gépen: FQDN `127.0.0.1`, HTTP, port `8080`.
- Másik gépen privát hálózaton/VPN-en: FQDN `10.0.0.20`, HTTP, port `8080`.
- TLS-es belső Wings: saját DNS-név, HTTPS, érvényes tanúsítvány.

Konténerekben a `127.0.0.1` a saját konténert jelenti: közösen elérhető belső
node-címet válassz. A sima HTTP-s belső kapcsolatot megbízható privát hálózaton
vagy titkosított VPN-en használd.

A meglévő Wings-config UUID-jét és tokenjeit őrizd meg. A `remote` legyen
`https://panel.example.com`, az `api.host` pedig a panelből elérhető bind-cím.
Az `allowed_origins` mezőbe nem kliens-IP-k kellenek: a `remote` panel-originje
automatikusan engedélyezett. `*` hozzáadása nem szükséges.
Kézi bind/TLS konfiguráció esetén a mellékelt `wings-settings.yml.example`
útmutatását kövesd; `ignore_panel_config_updates: true` mellett később kézzel
kell átvezetned a Wings konfigurációs változásait.

## 3. A panel nginx gateway beállítása

Először még NE kapcsold át a működő telepítést proxy módra. A panel könyvtárában:

```bash
cd /var/www/pterodactyl
php artisan p:remote-access:nginx > /tmp/pterodactyl-wings-gateway.conf
```

Csak sikeres parancsfutás után másold a fájlt például az
`/etc/nginx/snippets/pterodactyl-wings-gateway.conf` helyre. A panel meglévő
HTTPS **server blokkjába**, a meglévő PHP/frontend locationök mellé kerüljön:

```nginx
include /etc/nginx/snippets/pterodactyl-wings-gateway.conf;
```

Ez egy server-blokkba illeszthető snippet, nem külön virtuális host.
Az nginx a négy engedélyezett JWT-s Wings végpontot továbbítja; a Wings admin
API-ját nem. A korábbi `nginx-wings.conf.example` kizárólag a régi, külön
publikus Wings-hostos módhoz tartozik; proxy módban nem kell használni.

```bash
sudo nginx -t
sudo systemctl reload nginx
```

A reloadot csak sikeres `nginx -t` után végezd el. Node hozzáadása, eltávolítása
vagy belső címének változtatása után generáld újra a snippetet és töltsd újra az
nginxet. HTTPS upstreamnél a tanúsítványellenőrzés be van kapcsolva. A generált
CA-útvonal Debian/Ubuntu alapértelmezés; más rendszeren módosítsd a CA-bundle
helyére. Saját CA esetén azt add a megbízható CA-khoz.

## 4. Proxy mód bekapcsolása

A panel `.env` fájljába:

```dotenv
APP_URL=https://panel.example.com
WINGS_BROWSER_MODE=proxy
WINGS_PUBLIC_URLS='{}'
```

A saját panelnevedet használd. Az APP_URL itt egy origin: protokoll, host és
opcionális port, alkönyvtár nélkül. Proxy módban a WINGS_PUBLIC_URLS figyelmen
kívül marad. Új `.env.example` alapján ez a javasolt mód; régi `.env` fájlban a
hiányzó WINGS_BROWSER_MODE a kompatibilitás miatt még `direct` módot jelent.

```bash
php artisan config:clear
php artisan config:cache
php artisan queue:restart
php artisan p:remote-access:check 1
php artisan p:remote-access:check 1 --probe
```

A probe a panel gépéről OPTIONS kérést küld a gatewayen át a Wingshez, és 204-es,
CORS-fejlécet tartalmazó választ vár. Ez elérési ellenőrzés, nem bejelentkezési
vagy teljes konzolteszt. A panel publikus HTTPS-portja legyen kívülről elérhető.
A Wings API-portját elég a panel/nginx számára engedélyezni.

## Biztonság és működési határok

A belépés és a szerverjogosultságok továbbra is a panelen dőlnek el, a Wings
pedig ellenőrzi a rövid élettartamú, aláírt tokeneket. A proxy nem ad admin tokent
a böngészőnek. A panel sütijeit, Authorization és CSRF fejléceit nem továbbítja,
a Wings Set-Cookie válaszait eldobja. A panel eredetén kiszolgált felhasználói
fájlokra sandbox CSP és nosniff védelem kerül. A gateway nem cache-el, a
tokeneket tartalmazó URL-ek access logja ki van kapcsolva.

A panelnek és nginxének el kell érnie a Wingst: két, egymástól elzárt hálózat
között továbbra is VPN/tunnel vagy más működő útvonal szükséges. A proxy nem
hozza létre ezt automatikusan. SFTP és játékszerver-portok külön beállítandók.

## Ellenőrzés

Mobilnetről jelentkezz be a panelre. A WebSocket címe most
`wss://panel.example.com/_wings/1/api/servers/<uuid>/ws` legyen, 101-es státusszal.
Próbáld ki a logolvasást, egy ártalmatlan parancsot, fel-/letöltést és mentésletöltést.
Legalább 10 perc után ellenőrizd a tokenfrissítést, hálózatváltás után pedig az
újracsatlakozást. Jogosultság nélküli alfelhasználó ne kapjon hozzáférést.

404: hiányzó/elavult nginx snippet vagy hibás node ID. 502: a panel nginx nem éri
el a belső Wingst. 403-as WebSocket handshake: hibás panel-origin/Wings remote.
TLS-hiba: tanúsítvány, név vagy CA-bundle. A konfigurációt az nginx fájljai és a
Wings naplója alapján ellenőrizd; a tokeneket ne másold nyilvános hibajegybe.

Helyben lefutott: 27 címkezelési, 22 gateway-konfigurációs ellenőrzés és 36 valódi
nginx HTTP/WebSocket átviteli ellenőrzés **mock Wings végponttal**. A proxyteszt
vizsgálja a több node közti útválasztást, bináris letöltést, 2 MB-os feltöltést,
fejlécszűrést, tiltott útvonalakat, Origin elutasítást, kétirányú WebSocket-forgalmat,
auth/tokenfrissítő üzenetek átvitelét és újracsatlakozást.
Ez nem helyettesíti a tényleges Laravel + adatbázis + Docker/Wings végponti tesztet;
az itt nem futott. Az új PHPUnit-integrációs teszt és gateway CI a forrásban van.

## Visszaállítás

`WINGS_BROWSER_MODE=direct` és `php artisan config:cache` visszaállítja a korábbi
böngésző → Wings útvonalat. Ehhez ismét publikus Wings-cím kell: a node eredeti
címe vagy a WINGS_PUBLIC_URLS mapping. A snippet eltávolítása előtt kapcsold át
a panelt, majd végezz nginx-konfigurációellenőrzést és reloadot.
