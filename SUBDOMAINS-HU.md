# Cloudflare aldomain-kezelő

A szerver **Hálózat** oldalán a tulajdonos és az adminisztrátor egy aldomaint
hozhat létre, frissíthet vagy törölhet. Példa: `survival.games.sajatdomain.hu:25565`.
A hálózat megtekintésére jogosult társfelhasználók láthatják és másolhatják a címet.

## Beállítás

1. Cloudflare-ben válassz saját zónát. Használj külön aldomaint, például
   `games.sajatdomain.hu` a játékszerverek címeihez. Ennek nem kell külön Cloudflare-zónának lennie.
2. Készíts API tokent **Zone → DNS → Edit** jogosultsággal, csak az érintett zónára.
   Másold ki a zóna Zone ID-jét. Ne használj globális API-kulcsot.
3. Docker esetén a `deploy/.env`, hagyományos telepítésnél a panel `.env` fájljába írd:

```dotenv
SUBDOMAINS_ENABLED=true
SUBDOMAINS_DOMAIN=games.sajatdomain.hu
CLOUDFLARE_ZONE_ID=IDE_A_32_KARAKTERES_ZONE_ID
CLOUDFLARE_DNS_TOKEN=IDE_A_SAJAT_TOKEN
```

A token titok: ne commitold és ne küldd el chatben. A konfiguráció kizárólag
a backendnek adja át. A `.env` jogosultsága legyen `600`.

## Meglévő Docker-telepítés frissítése

Először készíts panel-adatbázis- és storage-mentést. Az új forrás könyvtárában:

```bash
docker compose --env-file deploy/.env -f compose.yaml build panel
docker compose --env-file deploy/.env -f compose.yaml run --rm panel php artisan migrate --force
docker compose --env-file deploy/.env -f compose.yaml up -d --wait panel
```

HTTPS/Caddy használatakor a szokásos `-f compose.tls.yaml` fájlt is add meg a
Compose-parancsokban. Wings használatakor tartsd meg a saját override-odat is.
Pusztán `restart` nem veszi át az új környezeti változókat, ezért kell `up -d`.
Új telepítéshez a `DOCKER-HU.md` teljes útmutatóját kövesd.

Hagyományos telepítés: függőségek és frontend fordítása a panel szokásos módján,
majd `php artisan migrate --force` és `php artisan config:cache`.
Közös Redis cache ajánlott; több panelpéldány nem használhat külön helyi cache-t,
mert a DNS-módosítások zárolása közös cache-t igényel.

## Használat és korlátok

- Szerverenként egy név, a beállított domain alatt. Átnevezés: törlés, majd új név.
- A vagy AAAA rekord az elsődleges allokáció nyilvános IP-jére, DNS-only módban.
  Cloudflare narancssárga HTTP-proxyja nincs bekapcsolva a játékcímeken.
- Az elsődleges IP/port változása után kattints a **Frissítés** gombra.
- A port része a megjelenített és másolt csatlakozási címnek. SRV rekordot ez a
  verzió nem készít; nem minden játék támogat port nélküli DNS-csatlakozást.
- NAT mögötti node-nál az allokációhoz nyilvános IP kell. A DNS nem nyit portot,
  nem kerül meg CGNAT-ot, és nem helyettesíti a játék TCP/UDP-porttovábbítását.
- A panel nem módosít meglévő, idegen rekordot. Foglalt névnél válassz másikat.
- Hiba után a névfoglalás **Függőben** marad. A **Frissítés** újra ellenőrzi a
  Cloudflare-rekordot, és tulajdonjelölés alapján folytatja a műveletet. A
  **Törlés** csak a saját rekordot távolítja el, majd felszabadítja a foglalást.
- A „DNS-rekord mentve” azt jelzi, hogy Cloudflare elfogadta a módosítást;
  nem ellenőrzi a játék működését vagy a világ összes DNS-cache-ét. TTL: 120 másodperc.
- A Cloudflare-ben ne módosítsd a panel rekordjának `alex-panel:...` megjegyzését:
  ez a tartós tulajdonjelölés. A token zónáját ne cseréld le aktív rekordok mellett.

## Törölt szerverek megmaradt DNS-rekordjai

A szerver törlése nem függ külső DNS-szolgáltatás elérhetőségétől. A névfoglalást
megőrizzük, így más szerver nem veheti át véletlenül. Adminisztrátorként:

```bash
php artisan p:subdomains:prune
php artisan p:subdomains:prune --delete
```

Az első parancs csak listáz. A második futásonként egy törölt szerverhez tartozó
rekordot távolít el a Cloudflare-ből, majd törli a helyi foglalást. Dockerben a
parancsok elé `docker compose --env-file deploy/.env exec panel` szükséges.

## Ellenőrzés

`php tests/subdomain-rules.php`: név-, domain- és publikus-IP-szabályok.
`yarn test --runInBand SubdomainManager.spec.tsx`: létrehozás, törlési
megerősítés, jogosultság szerinti gombok és hibából helyreállás.
`vendor/bin/phpunit tests/Integration/Api/Client/Server/SubdomainControllerTest.php`:
Laravel API-tesztek tesztadatbázissal és hamisított Cloudflare-válaszokkal.
Éles Cloudflare-zónán végzett próba külön szükséges a saját beállításaid után.

Cloudflare dokumentáció: [DNS-rekord létrehozása](https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/create/).
