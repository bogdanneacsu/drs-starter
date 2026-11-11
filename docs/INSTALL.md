# DRS Starter — Instalare și configurare

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
5. Butonul ⚙ din bara ferestrei deschide **setările** (conectare Race Control, countdown demo, ruta, debug).

Dezinstalare: șterge folderul `apps\lua\DRSStarter`.

## 3. Ce face aplicația piloților

- **Driver Mode** (singurul mod): ghid de aliniere, distanță până la țintă, stare (roți în zonă / staționar / direcție), countdown, avertismente și panoul „Exemplu poziție” (se poate ascunde din setări).
- **Safety Car** și **captura liniilor de start** sunt doar în aplicația organizatorului, `DRSOrganizer` (vezi `DRSOrganizer/README.md`).

## 4. Liniile de start (de la 0.3.0)

- În **LIVE** aplicația folosește **doar** liniile de pe site (admin → **Linii de start**), primite prin conexiunea cu Race Control. Fișierele locale sunt ignorate, iar setările nu mai au calibrare sau toleranțe: pilotul nu poate muta linia și nu poate lărgi zona verde.
- Până vin liniile de pe site, aplicația arată „Aștept linia de start de la Race Control…” și nu dă niciodată verde.
- În **demo local** se folosesc liniile livrate cu aplicația (`data\starts.json`), doar pentru exercițiu.
- Organizatorul capturează linia cu DRS Organizer, apoi **Trimite pe site** (cont de director de cursă) sau lipește JSON-ul în admin → Linii de start. Pe site o linie se poate dezactiva; aplicațiile o pierd la următoarea sincronizare.

## 5. Format `starts.json`

```json
{
  "schema": 1,
  "starts": [{
    "id": "ranca_transalpina/urcare/urcare",
    "track": "ranca_transalpina", "layout": "urcare", "route": "urcare", "label": "Urcare",
    "line": { "p0": [x, y, z], "forward": [fx, 0, fz], "width_m": 8 },
    "target": { "offset_m": -0.30, "tol_back_m": 0.175, "tol_fwd_m": 0.175,
                "max_lateral_m": 4, "max_heading_deg": 8, "max_steer_deg": 0 },
    "stationary": { "max_speed_kmh": 0.5, "hold_s": 1.0, "max_drift_m": 0.02 },
    "approach_radius_m": 80
  }]
}
```
`track` și `layout` sunt valorile `ac.getTrackID()` și `ac.getTrackLayout()` (vizibile în setări). Un fișier invalid nu produce niciodată indicator verde; erorile apar în setări.

## 6. Countdown local

Repetă 40 → 1 → „0 · GO (DEMO)” → 40. Se calculează din timpul scurs (ceas monoton), deci nu are drift. Pauză / Reia / Repornește din setări (doar în demo). După reîncărcarea aplicației continuă din aceeași fază (dacă ancora are sub 1 oră); o pauză nu se păstrează la reîncărcare.

## 7. Depanare

- Activează **Date de debug** în setări: build CSP, stare, referință folosită (`contact` / `hub` / `bumper`), `d`, lateral, unghi, viteză, `steer`, ampatament, coordonatele roților față.
- Erorile Lua apar în aplicația CSP **Lua Debug** și în jurnalul CSP.
- Referința `bumper` (bara față) înseamnă că roțile nu au putut fi citite: aplicația nu va afișa niciodată verde în acest caz.

## 8. Modul LIVE (Faza 2)

1. Setări → „Conectare Race Control” → alege **LIVE (Race Control)**.
2. Introdu adresa serverului DRS (`https://…`) și numele dispozitivului → **Împerechează**.
3. Pe site: **Profilul meu → DRS Starter** → introdu codul afișat → Aprobă. Aplicația se conectează singură.
4. Driver Mode arată ora ta de start (ora serverului), countdown-ul până la fereastră și **GO** doar când fereastra e deschisă, datele sunt proaspete și ești aliniat. Fără răspuns de la server mai mult de 4 s: **CONEXIUNE PIERDUTĂ**, fără GO.
5. Linia de start pentru traseul curent vine de pe site la prima sincronizare (și din nou doar când organizatorul o schimbă).
6. Dacă ai ratat startul: eliberează zona de start și mergi la boxe; primești o singură nouă oră, la coada cozii.

Tokenul se poate revoca de pe site. „Deconectează acest dispozitiv” îl șterge din aplicație.
