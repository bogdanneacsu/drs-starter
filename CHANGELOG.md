# Changelog

## 0.3.0 — 11 noiembrie 2026
- **Zona verde mai mare:** 35 cm (±17,5 cm) în loc de 20 cm (±10 cm), la cererea organizatorului. Se aplică liniilor capturate de acum înainte; o linie trimisă înainte pe site își păstrează toleranțele (retrimite-o din DRS Organizer).
- **Încălzirea anvelopelor integrată** în DRS Starter (logica din `online/warm_tyres.lua`): activă de la ieșirea din boxe până la 20 m de linia de start, re-armată la „back to pits” (Run 2). Folosește linia de start a alinierii, deci nu mai e nevoie de `startPos` separat. Fără linie de start calibrată nu încălzește. Valorile sunt fixe în `src/config.lua` (`WARM_TYRES`), fără setări pentru pilot.
- **Interfața se minimizează în manșă:** după ce mașina trece de linie cu viteză, rămâne doar o bandă mică („DRS · ÎN MANȘĂ”); revine mare la „back to pits”.
- **Liniile de start vin de pe site în LIVE:** admin → Linii de start (nou), completate din DRS Organizer cu **Trimite pe site** sau prin lipirea JSON-ului. DRS Starter primește liniile traseului curent la sincronizare (doar când se schimbă versiunea) și ignoră fișierele locale. Demo local folosește doar `data/starts.json` livrat.
- **Scoase din aplicația piloților:** modul Safety Car (este în DRS Organizer), calibrarea, toleranțele și `starts.local.json`.
- DRS Organizer: buton **Trimite pe site** (cont cu dreptul `direct race`); succes afișat doar după confirmarea serverului.
- Textul pentru pilot înainte de program: „Așteaptă programul de start” (Run 2 se pornește din consola Race Control).

**De verificat în joc:** dacă `physics.setTyresTemperature` este permis unei aplicații Lua obișnuite pe serverul online. Dacă nu, aplicația arată „ÎNCĂLZIRE INDISPONIBILĂ PE ACEST SERVER” și restul funcționează normal; încălzirea rămâne atunci prin scriptul online livrat de ACSM.

## 1.0.0 (tag GitHub) — 11 noiembrie 2026
Prima versiune pe GitHub: DRS Starter 0.2.0, DRS Organizer 0.1.0, `online/warm_tyres.lua` neschimbat.
