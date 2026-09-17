# Cloudflare Tunnel helyi panelhez

A telepítő alapértelmezett HTTP módja csak a gép helyi címére figyel:

- panel cím: `http://localhost:8080`
- bind cím: `127.0.0.1`
- kívülről elérhető 80/443 port: nincs

## Helyi telepítés

Indítsd az installert rootként, majd válaszd a `2) Új panel helyi HTTP teszthez` menüpontot. Ezután:

- `1) Csak ezen a gépen`: csak `http://localhost:8080` működik.
- `2) Helyi hálózaton is elérhető`: add meg a gép LAN-címét, például `192.168.1.20`; a panel `http://192.168.1.20:8080` címen lesz elérhető.

LAN módnál a telepítő `0.0.0.0` bind címet használ, ezért a gép tűzfalán a 8080-as TCP portot csak a helyi hálózatból engedélyezd. Routeren ne továbbítsd ezt a portot az internet felé.

## Tunnel beállítása

1. Telepítsd a `cloudflared` klienst azon a gépen, ahol a panel fut.
2. A Cloudflare Zero Trust felületén hozz létre egy Tunnel-t és egy publikus hostname-et, például `panel.example.hu`.
3. Az origin szolgáltatás legyen:

   `http://127.0.0.1:8080`

4. A panel telepítési könyvtárában állítsd át az URL-t a tunnel hostname-re:

```bash
cd /opt/alex-panel
sed -i 's#^APP_URL=.*#APP_URL=https://panel.example.hu#' deploy/.env
```

5. Indítsd újra a panelt:

```bash
./install.sh
```

Válaszd a `7) Szolgáltatások újraindítása` menüpontot. Docker módban a `TRUSTED_PROXIES=*` beállítás már szerepel a Compose konfigurációban.

Ne állítsd a `PANEL_BIND_IP` értékét `0.0.0.0`-ra. A Cloudflare Tunnel közvetlenül a localhostos originhez kapcsolódjon, így a panel nem válik közvetlenül interneten elérhetővé.

Az installer `10) Cloudflare Tunnel URL beállítása` menüpontja elmenti a Tunnel hostname-et és az `APP_URL` értéket. A `cloudflared` telepítését és a Tunnel hitelesítését szándékosan nem végzi el automatikusan, mert ehhez Cloudflare-fiókhoz kötött token szükséges.

## Ellenőrzés

```bash
curl -I http://127.0.0.1:8080
docker compose --env-file deploy/.env -f compose.yaml ps
```

A panel láblécében és az adminisztrációs áttekintőben a `config/app.php` szerinti panelverzió jelenik meg. A telepítő ugyanazt a verziót kiírja a sikeres indítás végén.

## Frissítés és mentés

- `8) Mentés, frissítés és telepítés javítása`: mentést készít, majd frissíti a forrást és újraépíti a panelt.
- `4) Panel adatbázis + storage mentése`: adatbázis-, storage- és környezeti mentést készít.
- `12) Panel backup visszaállítása`: csak az installer saját `deploy/backups` könyvtárából állít vissza.
- `9) Diagnosztika`: ellenőrzi a Docker/Compose, HTTP, Nginx, adatbázis-közeli szolgáltatások és biztonsági alapbeállítások állapotát.
- `11) Helyi Wings teljes eltávolítása`: a panelt megtartja, de a telepítő által kezelt Wings konfigurációt, konténereket és játékadatokat törli.

A backup visszaállítása előtt állítsd le a játék szervereket. A visszaállítás az aktuális adatbázist és `storage` könyvtárat felülírja.