# DRS Starter — Instalare, configurare și calibrare

> Implicit aplicația pornește în **modul demo local** (Faza 1): fără rețea; countdown-ul de 40 s este doar demonstrativ și **nu este un start oficial**. Modul **LIVE (Race Control)** din Faza 2 se activează din setări după împerechere; vezi §8 și `docs/PHASE2_OPERATIONS.md`.

## 1. Cerințe

- Assetto Corsa cu Content Manager și **Custom Shaders Patch versiunea aprobată de organizator**. Ținta: **CSP 0.3.1 (public), build 4302**. Build-ul nu a fost confirmat din sursa oficială; verifică-l în Content Manager → Settings → Custom Shaders Patch → About. Dacă diferă, modifică `APPROVED_CSP_BUILD` în `DRSStarter/src/config.lua`.
- Aplicațiile Lua CSP trebuie să fie activate (implicit sunt activate în CSP).

## 2. Instalare

1. Închide Assetto Corsa.
2. Copiază **folderul `DRSStarter`** (cel care conține `manifest.ini`) în:
   ```
   <Steam>\steamapps\common\assettocorsa\apps\lua\DRSStarter\
   ```
   Calea finală a manifestului trebuie să fie `...\assettocorsa\apps\lua\DRSStarter\manifest.ini`. Numele folderului trebuie să rămână `DRSStarter`, pentru că fișierul principal se numește `DRSStarter.lua`.
3. Pornește o sesiune (Practice offline este suficient).
4. În joc, deschide bara de aplicații (marginea dreaptă a ecranului) și pornește **DRS Starter**. Fereastra se poate muta și redimensiona; conținutul se scalează după lățime.
5. Butonul ⚙ din bara ferestrei deschide **setările** (mod, countdown, calibrare, debug).

Dezinstalare: șterge folderul `apps\lua\DRSStarter`. Calibrările locale sunt în `DRSStarter\data\starts.local.json`; salvează fișierul înainte dacă vrei să le păstrezi.

## 3. Moduri

- **Pilot (Driver Mode):** ghid de aliniere, distanță până la țintă, stare (roți în zonă / staționar / direcție), countdown local 40 s, progres demo, avertismente și panoul „Exemplu poziție” (se poate ascunde din setări; fereastra are 760×446 cu panoul, 760×346 fără).
- **Safety Car** în modul demo: stare, „Confirmă sosirea la finish”, HOLD / Reluare, Reset demo, jurnal local. Nimic nu este trimis nicăieri.

Modul se alege din setări și se păstrează între sesiuni.

## 4. Calibrarea unei linii de start

Configurațiile sunt per **traseu + layout + rută**. Fiecare rută (inclusiv sensul invers) are propria calibrare.

### Varianta A — din nodurile traseului (dacă există)
1. Condu până lângă start, cu mașina orientată în sensul rutei.
2. Setări → alege ruta (Urcare / Sens invers / Alt start) → **Propune din nodurile traseului**.
3. Dacă traseul are `AC_AB_START_L/R`, aplicația creează linia și desenează în lume: **linia albă** = linia de start, **linia portocalie** = ținta axei față, **zona verde** = toleranța.
4. Verifică vizual că linia albă coincide cu linia de start a traseului. Dacă nu, folosește varianta B.

### Varianta B — captură manuală
1. Oprește mașina **dreaptă**, cu **roțile din față exact pe linia de start**.
2. Setări → alege ruta → **Capturează linia (roți față pe linie)**.
3. Nu mișca mașina 1 s. Aplicația mediază poziția și afișează dispersia. Captura este refuzată dacă mașina se mișcă sau dacă roțile nu pot fi citite.
4. Ținta implicită este la **30 cm în spatele liniei**.

### Ajustare parametri
În setări, pentru configurația activă: țintă față de linie, toleranță spate/față, orientare maximă, bracare maximă (0 = dezactivat), lățimea liniei → **Aplică și salvează**. Valorile implicite (30 cm în spate, ±10 cm, 8°, < 0,5 km/h timp de 1 s) **nu sunt validate în joc**.

### Distribuirea calibrării către piloți
Calibrarea organizatorului se află în `data\starts.local.json`. Pentru a o livra tuturor piloților, copiază conținutul listei `starts` în `data\starts.json` din pachetul distribuit. O calibrare locală cu același `id` are prioritate față de cea livrată.

## 5. Format `starts.json`

```json
{
  "schema": 1,
  "starts": [{
    "id": "ranca_transalpina/urcare/urcare",
    "track": "ranca_transalpina", "layout": "urcare", "route": "urcare", "label": "Urcare",
    "line": { "p0": [x, y, z], "forward": [fx, 0, fz], "width_m": 8 },
    "target": { "offset_m": -0.30, "tol_back_m": 0.10, "tol_fwd_m": 0.10,
                "max_lateral_m": 4, "max_heading_deg": 8, "max_steer_deg": 0 },
    "stationary": { "max_speed_kmh": 0.5, "hold_s": 1.0, "max_drift_m": 0.02 },
    "approach_radius_m": 80
  }]
}
```
`track` și `layout` sunt valorile `ac.getTrackID()` și `ac.getTrackLayout()` (vizibile în setări). Un fișier invalid nu produce niciodată indicator verde; erorile apar în setări.

## 6. Countdown local

Repetă 40 → 1 → „0 · GO (DEMO)” → 40. Se calculează din timpul scurs (ceas monoton), deci nu are drift. Pauză / Reia / Repornește din setări. După reîncărcarea aplicației continuă din aceeași fază (dacă ancora are sub 1 oră); o pauză nu se păstrează la reîncărcare.

## 7. Depanare

- Activează **Date de debug** în setări: build CSP, stare, referință folosită (`contact` / `hub` / `bumper`), `d`, lateral, unghi, viteză, `steer`, ampatament, coordonatele roților față.
- Erorile Lua apar în aplicația CSP **Lua Debug** și în jurnalul CSP.
- Referința `bumper` (bara față) înseamnă că roțile nu au putut fi citite: aplicația nu va afișa niciodată verde în acest caz.

## 8. Modul LIVE (Faza 2)

1. Setări → „Conectare Race Control” → alege **LIVE (Race Control)**.
2. Introdu adresa serverului DRS (`https://…`) și numele dispozitivului → **Împerechează**.
3. Pe site: **Profilul meu → DRS Starter** → introdu codul afișat → Aprobă. Aplicația se conectează singură.
4. Driver Mode arată ora ta de start (ora serverului), countdown-ul până la fereastră și **GO** doar când fereastra e deschisă, datele sunt proaspete și ești aliniat. Fără răspuns de la server mai mult de 4 s: **CONEXIUNE PIERDUTĂ**, fără GO.
5. Safety Car Mode (cont cu rolul `safety_car`): alegi clasa, „Confirmă sosirea la finish” (două apăsări în 4 s), HOLD și Reluare.
6. Dacă ai ratat startul: eliberează zona de start și mergi la boxe; primești o singură nouă oră, la coada cozii.

Tokenul se poate revoca de pe site. „Deconectează acest dispozitiv” îl șterge din aplicație.
