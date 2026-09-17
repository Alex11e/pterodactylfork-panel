# Helyi ellenőrzés – 2026. szeptember 16.

A Cloudflare aldomain-kezelő hozzáadása után:

- TypeScript (`tsc --noEmit`): sikeres.
- Webpack éles frontend-fordítás: sikeres.
- Jest: 4 aldomain-kezelő UI-teszt és 2 konzolszöveg-teszt sikeres.
- PHP DNS-szabályok: 37 ellenőrzés sikeres.
- PHP Cloudflare-szolgáltató: 17 ellenőrzés sikeres hamisított HTTP-transzporttal.
- Módosított PHP-fájlok szintaxisellenőrzése: sikeres.
- A saját PHP-változtatások formázása a projekt PHP CS Fixer-konfigurációjával megtörtént.

A teljes Laravel/MySQL integrációs tesztcsomag és a Docker-telepítés ezen a
Windows gépen nem futott. A hozzáadott `SubdomainControllerTest.php` futtatásához
Composer-függőségek és elkülönített tesztadatbázis szükséges. Böngészős, valódi
panelbejelentkezéssel végzett végponttól végpontig teszt sem történt.
Éles Cloudflare-módosítás nem történt; saját domain, Zone ID és token még nincs
beállítva. Ezeket a `SUBDOMAINS-HU.md` szerint kell megadni.

A build figyelmeztetett a régi Browserslist-adatokra és a Tailwind line-clamp
pluginre; a tesztfuttató a meglévő TypeScript/ts-jest verziópárosra. Ezek nem
akadályozták a fenti ellenőrzések sikeres lefutását.

A fenti eredmények a szeptember 16-i ellenőrzésre vonatkoznak.
A telepítő későbbi javításához külön, valódi Docker-telepítést futtató CI készült:
[Installer Docker smoke test](https://github.com/Alex11e/pterodactylfork-panel/actions/workflows/installer.yaml).
Az adott commit ellenőrzési eredményét mindig a hozzá tartozó futás mutatja.
