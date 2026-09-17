# Alex Panel telepítő

Rootként Ubuntu/Debian szerveren:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Alex11e/pterodactylfork-panel/1.0-develop/install.sh)
```

Az **1-es menüpontban** HTTPS-es telepítés indul. A varázsló megkérdezi:

1. Docker Compose vagy natív Nginx + PHP-FPM legyen a panel futtatási módja?
2. Csak panelt vagy panelt és Wingst telepítsen ugyanarra a gépre?
3. Mi a panel domainje és a tanúsítványhoz használt e-mail-cím?

A domain DNS-rekordja mutasson a gépre, a 80/443 TCP-port legyen elérhető.
A **2-es menüpont** ugyanilyen varázsló, de csak helyi HTTP-próbához: `localhost:8080`.
Távoli böngészéshez itt SSH-tunnel szükséges.

## Futtatási módok

| | Docker | Natív Nginx |
|---|---|---|
| Panel/PHP | Konténer | Rendszer PHP-FPM szolgáltatása |
| Adatbázis/Redis | Külön konténerek | MariaDB és Redis rendszerszolgáltatások |
| HTTPS | Caddy | Nginx és Certbot |
| Háttérfeladatok | Supervisor a konténerben | systemd szolgáltatások |
| Wings egyben telepítéskor | Konténer, host hálózattal | Saját systemd szolgáltatás |
| Játékszerverek | Docker | Docker |

A natív mód Ubuntu 24.04, Debian 12 és Debian 13 rendszerekhez készült; a
teljes CI-próba Ubuntu 24.04-en fut. Tiszta gép ajánlott. Meglévő MySQL-t,
azonos nevű adatbázist vagy másik Alex Panel szolgáltatásait nem cseréli le.
Natív módban a frontend Node 22-t és Yarn 1-et használ, elkülönítve a
`/opt/alex-panel-tools` alatt. A Node-letöltés SHA256-ellenőrzött.

A natív panel önmagában nem igényel Dockert. A Wings a játékokat mindig
Dockerben futtatja; a natív Wings bináris fordításához is Docker buildet használunk.

## Panel + Wings egyben

A panel indítása után a varázsló bekéri a játékok IPv4-címét, az első portot,
a node memória- és lemezkeretét. Létrehozza az `Alex Local` node-ot, az első
IP:port kiosztást és a Wings konfigurációját. A titkos token közvetlenül a
`/etc/pterodactyl/config.yml` fájlba kerül, nem a terminálba.

A Wings API-ja belső címen, 8081-en fut. A játékportot és szükség esetén a
2022-es SFTP-portot a tűzfal/NAT beállításában külön engedélyezni kell.
A telepítő nem módosítja automatikusan a gép tűzfalszabályait. A Docker a játékoknak
külön, szabad címtartományú `alex-games` hálózatot választ, így nem ütközik a panelével.
Az indítás végén a panelből hitelesített Wings API-kéréssel ellenőrizzük a kapcsolatot.

Meglévő, nem ezzel a varázslóval készített Wings-konfigurációt nem írunk felül.
Az egyben telepítés az infrastruktúrát készíti el; a konkrét Minecraft/Rust/stb.
játékszervert ezután a panel adminfelületén hozd létre.

## Javítás és kezelés

- **3:** automatikus helyi Wings beállítása/frissítése egy már működő panel mellett.
- **4:** paneladatbázis, storage és kulcsok mentése. A játékfájlokat külön mentsd.
- **5:** állapot és naplók a mentett futtatási mód szerint.
- **6:** adminfiók létrehozása.
- **7:** panel háttérszolgáltatásainak újraindítása.
- **8:** javított forrás letöltése, újraépítés és megszakadt telepítés folytatása.

Ha az 1-es vagy 2-es új telepítési menüpontnál már létezik a célkönyvtár,
a telepítő tiszta újratelepítést ajánl fel. Megerősítés után Docker módban a
panel projekt konténerei és kötetei, natív módban a telepítő által létrehozott
szolgáltatások, Wings és az `alex_panel` adatbázis is törlődik. A művelet után
új kulcsokkal és üres adatbázissal indul a telepítés.

A telepített mód a `deploy/state/backend` fájlban marad. A javítás ezt követi;
Docker és natív mód között nem költöztet automatikusan adatbázist.
Ha a Wings telepítése szakadt meg, a panel javítása után a 3-as menüt használd.
Natív módban a Laravel `.env` fájl a `deploy/.env`-re mutató szimbolikus link.
A domain, SMTP és Cloudflare-beállítások ott módosíthatók. Beállítás után
natívan `php artisan config:cache`, Dockerben a konténer újralétrehozása szükséges.

Részletes Docker-leírás: `DOCKER-HU.md`. Cloudflare: `SUBDOMAINS-HU.md`.
Az aktuális ellenőrzések a GitHub **Installer Docker smoke test** workflow-ban láthatók:
külön Docker és natív telepítési job fut, mindkettő Wings-kapcsolatot is vizsgál.
