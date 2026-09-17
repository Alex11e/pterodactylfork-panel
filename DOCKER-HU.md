# Docker telepítés – Alex Panel

A Docker/natív mód és az egyben telepítés kiválasztásához lásd `TELEPITES-HU.md`.

## Gyors telepítő

Csak ellenőrzött, saját kiadású URL-ről futtasd a telepítőt. Az aktuális repóban
a script az `install.sh` fájl. Rootként Ubuntu/Debian szerveren:

```bash
bash <(curl -fsSL --proto '=https' https://raw.githubusercontent.com/Alex11e/pterodactylfork-panel/1.0-develop/install.sh)
```

A telepítő alapból az `1.0-develop` ágat tölti le. Ha korábban más `PANEL_REF`
változót exportáltál, előtte futtasd: `unset PANEL_REF`.
A helyi ZIP-forráshoz kövesd az alábbi kézi Docker indítást. A telepítő nem töröl meglévő
Docker-csomagot, adatbázist, kötetet vagy célkönyvtárat. Root Debian/Ubuntu
rendszeren fut. A script a Docker hivatalos apt-tárolóját használja, és nem futtat
ismeretlen, távoli shell-kódot.

## Menüpontok

Megszakadt telepítésnél válaszd a **8-as menüpontot**. Ez a meglévő
`/opt/alex-panel` könyvtárban letölti a javított forrást, újraépíti az image-et,
ellenőrzi az `/app/artisan`, a Composer autoloader és a frontend jelenlétét,
majd folytatja az adatbázis-migrációt és az indítást. Az APP_KEY, a jelszavak és
a Docker-adatkötetek megmaradnak. Már inicializált panelnél nem fut újra a
kezdeti adatfeltöltés és nem hoz létre újabb adminfiókot. Éles panel javítása
előtt készíts mentést. A helyileg módosított forrásfájlokat nem írja felül.
Ha az adminfiók létrehozásánál szakadt meg a folyamat, a **6-os menüpontot** használd.

Ha a letöltés még a `deploy/.env` létrehozása előtt szakadt meg, a 8-as mód nem
használható. A régi, félbemaradt könyvtárat őrizd meg más néven, majd válaszd az
1-es vagy 2-es módot. Az új telepítő már külön ideiglenes könyvtárba tölt le,
és csak ellenőrzött, teljes forrás esetén hozza létre a végleges célkönyvtárat.

Az 1-es mód HTTPS-es varázsló; Docker választásakor Caddy adja a HTTPS-t. A DNS-rekordnak a gépre kell
mutatnia, a 80/443 portnak elérhetőnek kell lennie, és valódi e-mail-címet kell
megadni a tanúsítványhoz. A 2-es mód csak helyi HTTP teszt, éles internetes
használatra nem való. A 3-as mód automatikus helyi node- és Wings-beállítás.
A 4-es mód a panel-adatbázist és panel storage-t
menti; a játékszerverek fájljai külön volume-ok.

Az első telepítés után a panel `.env`-je a `deploy/.env` fájlban marad. Mentsd el
biztonságos helyre az `APP_KEY`, adatbázis-jelszavakat és a Hashids-saltot.
Újraindításkor ezek nem változnak. A telepítő az adminfiók jelszavát interaktívan
kéri, így nem kerül shell historyba.

## Kézi Docker indítás

```bash
cp deploy/env.example deploy/.env
# Töltsd ki az APP_URL-t, APP_KEY-t, DB_PASSWORD-öket és HASHIDS_SALT-ot.
docker compose --env-file deploy/.env -f compose.yaml build panel
docker compose --env-file deploy/.env -f compose.yaml up -d --wait database redis
docker compose --env-file deploy/.env -f compose.yaml run --rm panel php artisan migrate --seed --force
docker compose --env-file deploy/.env -f compose.yaml up -d --wait
docker compose --env-file deploy/.env -f compose.yaml exec panel php artisan p:user:make --admin=1
```

HTTPS-hez a `compose.tls.yaml` override is kell:

```bash
docker compose --env-file deploy/.env -f compose.yaml -f compose.tls.yaml up -d --build --wait
```

A Docker Compose az egészséges MariaDB és Redis után indítja a panelt; ez a
`healthcheck` + `depends_on: condition: service_healthy` beállítás. A panel
konténer újraindítása nem migrál automatikusan, nem írja át a kulcsokat és nem
indít Wingset. A gateway konfigurációja a panel node-listájából készül és változás
esetén visszaáll korábbi, érvényes fájlra, ha az új konfiguráció hibás.

## Wings Dockerben

A 3-as menüpont maga készíti el a helyi node konfigurációját. A már meglévő,
más módon létrehozott konfigurációt nem írja felül. A Wings konténer host
network módban fut, megkapja a Docker socketet és a `/var/lib/pterodactyl`,
`/var/log/pterodactyl`, `/tmp/pterodactyl` könyvtárakat. Ez erős jogosultság: a
socket birtokosa lényegében host-szintű Docker-hozzáférést kap, ezért csak
megbízható szerveren használd és a host tűzfalán korlátozd a beállított Wings API-
és SFTP-portokat (a telepítő példájában 8081 és 2022).

Ebben a telepítési mintában a panel konténer nem ugyanazt a host-networket használja.
A node FQDN-jét olyan címre állítsd, amit a panel konténer elér (például a host
gateway megfelelő belső címére vagy külön belső DNS-névre). A Wings API-ja ne
legyen publikus: a gateway csak a panel konténerből érje el. A pontos cím Docker
bridge, tűzfal és host-környezet függvénye; a telepítő nem találja ki biztonságosan.

## Frissítés, ellenőrzés, mentés

```bash
cd /opt/alex-panel
docker compose --env-file deploy/.env ps
docker compose --env-file deploy/.env logs --tail=100 panel
docker compose --env-file deploy/.env run --rm panel php artisan p:remote-access:nginx
bash tests/installer.sh
```

A panel frissítése előtt készíts mentést a telepítő 4-es menüjével. Ezután fetch,
checkout vagy új forráskönyvtár, majd `docker compose build panel` és a projekt
release-útmutatója szerint frissíts. Automatikus, változó branchről történő
frissítést a telepítő nem végez.

## Hálózat

A PufferPanel-szerű működéshez a böngésző kizárólag a panel HTTPS-címét látja.
A konzol például `wss://panel.example.com/_wings/1/api/servers/<uuid>/ws` útvonalon
megy, az nginx belül a node Wings-címére továbbítja. Mobilnetről vagy más IP-ről
is működik, ha a panel 443-as portja elérhető. CGNAT vagy tűzfal esetén a panel
publikus eléréséhez külön VPS/VPN/tunnel szükséges; a Docker nem hoz létre útvonalat.
SFTP és játékportok külön TCP/UDP-beállítást igényelnek.
