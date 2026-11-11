# DRS Starter — Checklist de verificare în joc (Faza 1)

Status: **TOATE PUNCTELE SUNT ÎN AȘTEPTAREA VALIDĂRII ORGANIZATORULUI.** Nimic de mai jos nu a fost rulat în Assetto Corsa (pe PC-ul de dezvoltare nu există AC/CSP).

Notează pentru fiecare punct: OK / EȘUAT / observații, plus captură de ecran unde e relevant.

## 1. Versiune CSP și SDK
- [ ] Build CSP afișat în setări → Date de debug = build-ul aprobat (țintă 4302). Altfel overlay-ul arată „VERSIUNE CSP NEAPROBATĂ”.
- [ ] În `assettocorsa\extension\internal\lua-sdk` există definițiile; confirmă că `ac.StateCar` are `wheels`, `aabbSize`, `aabbCenter`, `steer`, `speedKmh`, iar `ac.StateWheel` are `contactPoint` și `position`.
- [ ] Notează unitatea lui `car.steer` (grade la volan sau la roată), afișată în debug.

## 2. Încărcarea aplicației
- [ ] DRS Starter apare în bara de aplicații, cu icon.
- [ ] Fără erori în aplicația Lua Debug la pornire și după 5 minute.
- [ ] Fonturile DRS (Barlow Condensed, Inter) sunt folosite (nu fontul implicit).
- [ ] Logo-ul DRS se vede în bara de sus.

## 3. Vizibilitate overlay
- [ ] Fereastra are fundal transparent, panourile sunt lizibile pe fundaluri luminoase și întunecate (zi, umbră, cer).
- [ ] Mutare și redimensionare: conținutul se scalează corect la 1920×1080, 2560×1440 și 3840×2160 (sau triple screen, dacă e folosit).
- [ ] Nu acoperă inutil vederea de condus în poziția aleasă.

## 4. Fidelitate față de macheta organizatorului
- [ ] Bara de sus (logo, traseu, ceas, Race Control „NECONECTAT · LOCAL” — fără stare falsă de conexiune).
- [ ] Titlul „POZIȚIONEAZĂ-TE LA LINIA DE START” + subtitlul de stare.
- [ ] Ghid de aliniere, countdown central, distanță, stare cu trei verificări, avertisment, progres.
- [ ] Zona verde pe asfalt, linia albă de start și linia portocalie a țintei.
- [ ] Panoul „Exemplu poziție”: trei carduri (prea în spate ✗, poziție corectă ✓, prea în față ✗), lizibile; se ascunde și reapare din setări, iar fereastra nu taie conținutul în niciuna din variante.
- [ ] Culorile de stare (aprobate) sunt lizibile pe fundalul jocului.
- [ ] Alte diferențe față de machetă (notează).

## 5. Countdown
- [ ] Pornește de la 40, scade la fiecare secundă reală (compară cu un cronometru).
- [ ] La 0 apare „GO (DEMO)” ~1,5 s, iar countdown-ul repornește de la 40.
- [ ] După 30 de minute, abaterea față de cronometru < 1 s.
- [ ] Pauză / Reia / Repornește funcționează.
- [ ] Sacadare (ALT+TAB, încărcare grea): countdown-ul revine la faza corectă, nu „rămâne în urmă”.

## 6. Aliniere cu o mașină reală
- [ ] Pe traseul calibrat, cu 3 mașini de lungimi diferite: verde doar cu axa față în zona verde (verificare cu camera exterioară F6 / free cam).
- [ ] Repetabilitate: aceeași poziție, 10 citiri ale lui `d` în debug → abatere maximă: ____ cm.
- [ ] Efectul bracării: `d` cu volanul drept vs. bracat maxim stânga/dreapta: ____ cm.
- [ ] Prea în spate → „ÎNAINTEAZĂ” + distanța; prea în față → „DĂ ÎNAPOI”.
- [ ] Rotit > 8° → „ÎNDREAPTĂ MAȘINA”; în sens invers → „DIRECȚIE GREȘITĂ”.
- [ ] Viteză > 0,5 km/h → „OPREȘTE MAȘINA”; verde doar după ~1 s stabil.
- [ ] Alunecare lentă pe pantă → nu devine verde.
- [ ] Ieșire din aliniere după verde → avertisment roșu „AI IEȘIT DIN POZIȚIE”.
- [ ] În replay sau pauză → „PAUZĂ / REPLAY”, fără verde.

## 7. Calibrare
- [ ] „Propune din nodurile traseului” pe un traseu cu `AC_AB_START_L/R`: linia albă coincide cu linia traseului.
- [ ] Pe un traseu fără noduri: mesaj clar, fără configurație greșită.
- [ ] Captură manuală: dispersia raportată ≤ 1 cm; captura e refuzată dacă mașina se mișcă.
- [ ] Rută inversă: captură separată, selectată automat când mașina e orientată invers lângă acel start.

## 8. Driver Mode
- [ ] Toate stările de mai sus au text corect în română, cu diacritice.
- [ ] „TRASEU NECALIBRAT” pe un traseu fără configurație.

## 9. Safety Car (mutat în DRS Organizer)
- [ ] În DRS Starter nu mai există mod Safety Car; comenzile sunt în fereastra „Safety Car” din DRS Organizer.

## 10. Reîncărcare
- [ ] Reîncărcarea aplicației (din Lua Debug sau repornirea sesiunii) nu blochează jocul.
- [ ] Setările se păstrează; countdown-ul demo continuă din aceeași fază; în LIVE linia de start revine de pe site.

## 11. Performanță și stabilitate
- [ ] FPS cu și fără aplicație în aceeași scenă (contorul CSP): ____ / ____ (țintă: diferență < 1 %).
- [ ] Fără pâlpâiri ale zonei 3D sau ale indicatorului verde la mașina oprită.
- [ ] Online, pe serverul ACSM de test: aplicația funcționează identic (fără rețea proprie).

## 12. Modul LIVE (Faza 2) — pe un server de test, nu în producție
- [ ] Împerecherea prin cod funcționează (`web.request` real din CSP); aplicația arată numele pilotului.
- [ ] În debug: offset ceas și incertitudine afișate; incertitudine < 100 ms: ____ ms.
- [ ] Fără conexiune (oprește rețeaua): CONEXIUNE PIERDUTĂ în ≤ 4 s, niciun GO.
- [ ] Ora de start afișată coincide cu consola Race Control; countdown corect.
- [ ] GO apare doar în fereastră și doar aliniat; dispare la închiderea ferestrei.
- [ ] Plecarea în fereastră → DEPARTED în aplicație și `on_track` în consolă.
- [ ] Ratare → mesaj „eliberează zona de start”; după ieșirea din zonă consola arată „raportat de client”.
- [ ] Safety Car: confirmarea cere două apăsări; HOLD și Reluare se văd la piloți în ≤ 2 s.
- [ ] Revocarea de pe site → aplicația cere o nouă împerechere.
- [ ] FPS cu LIVE activ: ____ (fără diferență vizibilă față de demo).

Checklist-ul complet multi-server este în `docs/PHASE2_OPERATIONS.md` §6.

## 13. Versiunea 0.3.0
- [ ] Zona verde are 35 cm și te poți așeza ușor pe ea (linie capturată din nou).
- [ ] În boxe: titlul arată „ÎNCĂLZIRE ACTIVĂ (BOXE)”; temperatura anvelopelor rămâne la optim până aproape de start (verifică în aplicația CSP de temperaturi).
- [ ] La 20 m de linia de start: „ÎNCĂLZIRE OPRITĂ”.
- [ ] Pe serverul online: încălzirea funcționează sau apare „ÎNCĂLZIRE INDISPONIBILĂ PE ACEST SERVER” (notează care).
- [ ] După start: interfața devine o bandă mică și nu acoperă drumul.
- [ ] „Back to pits”: interfața revine mare și încălzirea repornește pentru Run 2.

## 14. Linii de start de pe site (0.3.0)
- [ ] DRS Organizer: captură → **Trimite pe site** cu contul de director → mesaj „Linia … este pe site (versiunea N)”. Cu un cont fără drept: refuz afișat, nimic salvat.
- [ ] Admin → Linii de start arată linia; dezactivarea o scoate din aplicația piloților în câteva secunde.
- [ ] DRS Starter în LIVE: fără linie pe site → „Race Control nu are o linie de start pentru acest traseu”, niciodată verde.
- [ ] DRS Starter în LIVE: un `data\starts.json` modificat local nu schimbă nimic (linia rămâne cea de pe site).
- [ ] Setările DRS Starter nu mai au calibrare, toleranțe sau mod Safety Car.
