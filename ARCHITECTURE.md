# DRS STARTER — Arhitectură

Data: 3 noiembrie 2026 (revizia 2, după deciziile organizatorului) · Bază: RESEARCH.md §0

Status pe secțiuni: **Faza 1 = implementată local, netestată în joc.** **Faza 2 = doar proiectare**, nu se implementează fără aprobare explicită.

## 1. Decizie

Aplicație **CSP Lua** instalată de pilot în `assettocorsa/apps/lua/DRSStarter`, o singură versiune CSP aprobată de organizator pentru toți participanții (ținta: 0.3.1, build 4302, de confirmat). Fără companion Windows, fără Python. Aceeași aplicație are două moduri: **Driver** și **Safety Car**.

## 2. Granițe între sisteme

| Sistem | Este sursa de adevăr pentru | Nu face niciodată |
|---|---|---|
| **DRS Starter (CSP Lua, PC pilot)** | Nimic oficial. Afișează ghidaj de aliniere, ora de start primită, countdown, starea locală; raportează (Faza 2) alinierea și dovezi. | Nu publică timpi, nu decide starturi, nu aplică penalizări, nu comunică cu agentul Node, nu controlează ACSM. |
| **Laravel Race Control** | Starea manșei, coada, programul de start (ore absolute), ferestrele de plecare, ratări, DNS per manșă, HOLD, incidente, decizii de penalizare (umane). | Nu calculează timpi din datele aplicației. |
| **Agent Node.js (Kunos UDP)** | Timing-ul brut oficial (ture, `CAR_INFO`, opțional `CAR_UPDATE`). | Nu primește nimic de la aplicația pilotului. |
| **ACSM 2.4.8** | Rularea serverului AC. | Nu se presupune niciun API de control sau teleport. |

Fluxul de timing oficial rămâne neschimbat: UDP → agent Node → Laravel → rezultate provizorii → reconciliere → publicare.

## 3. Cele două moduri UI

**Driver Mode** — ghidaj de aliniere (distanță cu semn, înainte/înapoi, orientare, oprire), confirmare verde când e aliniat, avertisment la ieșirea din aliniere; în Faza 1 un countdown local repetitiv de 40 s etichetat **LOCAL DEMO**; în Faza 2 ora de start programată, countdown până la ea, fereastra ±10 s, starea startului și avertismente.

**Safety Car Mode** — panou minim: starea procedurii, buton **Confirmă sosirea la finish**, (Faza 2) **HOLD / suspendare**. În Faza 1 butoanele modifică doar o stare locală demonstrativă, cu eticheta **LOCAL DEMO MODE**; nu cheamă Laravel, nu creează ore de start, nu pretind că a pornit o procedură reală. În Faza 2 acțiunile sunt autentificate și limitate la operatori autorizați, fără alte drepturi administrative.

Implementare: interfața apelează un **adaptor de procedură** (`src/procedure_local.lua`) cu metode `confirmSafetyCarFinish()`, `hold()`, `release()`, `snapshot()`. În Faza 2 se adaugă `procedure_remote.lua` cu aceeași interfață; UI-ul nu se rescrie.

## 4. Timp local (Faza 1) vs. timp autoritar (Faza 2)

| | Faza 1 — countdown local | Faza 2 — program de start |
|---|---|---|
| Sursa | `src/countdown.lua`, ciclu repetitiv 40 → 0 → 40 | Laravel: ore absolute `scheduled_start_at` per pilot |
| Rol | Doar test vizual și de UX | Program oficial |
| Ceas | `os.preciseClock()` local, ancoră fixă | Ceasul serverului + offset estimat de client |
| Etichetă UI | „LOCAL DEMO — nu este un start oficial” | ora programată + fereastra de plecare |
| GO | Stare demonstrativă „GO (DEMO)” la 0 | Fereastra de plecare deschisă (−10 s … +10 s) |

Codul păstrează cele două concepte separate: `countdown.lua` nu știe nimic despre program; viitorul `schedule_client.lua` nu va reutiliza ciclul de 40 s.

Algoritmul countdown-ului local: ancoră `t0` (timp monoton). `elapsed = now − t0`; `phase = elapsed mod duration`; `remaining = duration − phase`; `cycle = floor(elapsed / duration)`. Valoarea afișată = `ceil(remaining)` (40 … 1); la trecerea prin 0 se semnalează `cycleCompleted` și UI-ul arată „0 · GO (DEMO)” 1,5 s, timp în care noul ciclu deja numără de la 40. Nu se acumulează `dt`, deci nu există drift, iar un salt mare de timp (cadru blocat) cade direct pe faza corectă. Pauza memorează `remaining`; reluarea mută ancora. Ancora se păstrează în `ac.storage` și se reutilizează după reîncărcarea aplicației dacă este validă (în trecut și nu mai veche de 1 oră); altfel ciclul pornește de la 40.

## 4b. Faza 2 implementată (3 noiembrie 2026) — rezumat

Secțiunile 5–7 și 9–10 de mai jos au fost proiectarea inițială. Implementarea reală este în `drs_v2` (`app/Domain/Starter`) și `DRSStarter/src/live`. Contractul exact este în `docs/API_CONTRACT.md`, iar configurarea, riscurile și checklist-ul E2E în `docs/PHASE2_OPERATIONS.md`. Diferențe față de proiectare:

- **Identificarea contextului:** după cont → player → înscriere acceptată la o etapă cu Race Control activ (nu după IP-ul serverului AC). Safety Car alege clasa dintre clasele active.
- **Detectarea plecării:** din raportul aplicației (`departure`, distanță ≥ 1,5 m față de linie și viteză ≥ 2 km/h) sau din pornirea manuală a operatorului în coadă. Agentul Node nu a fost modificat. Lipsa datelor duce la **revizuire la Race Control**, nu la ratare.
- **Ratare confirmată automat** doar cu heartbeat-uri care acoperă ≥ 50 % din fereastră, ultimul în ultimele 3 s și viteză ≤ 3 km/h. Altfel revizuire.
- **DNS** după a doua ratare: doar cu confirmarea directorului, sau automat dacă `auto_dns` e activ și ratarea e confirmată de heartbeat-uri. Implicit dezactivat.
- **HOLD/reluare:** reluarea mută sloturile rămase la ≥ `max(acum + resume_lead, slot anterior + interval)`, niciodată mai devreme. Nu se generează un program nou; crește `schedule_version`.
- **Transport:** un singur `POST /sync` per ciclu (heartbeat + evenimente → stare + `acks`), nu endpointuri separate `time`/`ack`. Proba de ceas folosește `server_received_ms`/`server_time_ms` din același răspuns.
- **Regula de siguranță din client:** GO numai cu stare validă mai nouă de 4 s (`stale_after_ms`), procedură `running`, slot `scheduled`, ora serverului estimată în fereastră și aliniere `ALIGNED`. Altfel countdown, HOLD sau CONEXIUNE PIERDUTĂ.
- **Blocări:** `race_control_settings` → `starter_procedures` → `starter_slots` → `start_queue_items`, toate în tranzacții. Unicitate pe (etapă, clasă, manșă) și pe (item coadă, încercare). Audit pentru fiecare tranziție, cu acțiunile automate atribuite sistemului.
- **Trimiterea la boxe:** rămâne neimplementată (§9). Aplicația afișează instrucțiunea, iar consola arată „zonă liberă: raportată de client / neconfirmată”.

## 5. Workflow Faza 2 (proiectare inițială)

1. Safety Car termină coborârea/urcarea și ajunge în zona de finish.
2. Pilotul Safety Car apasă **Confirmă sosirea** în overlay (Safety Car Mode).
3. Laravel validează: utilizator autorizat ca Safety Car pentru etapa/clasa activă, manșa în faza corectă, comanda idempotentă (`command_id`), nicio altă confirmare activă.
4. Laravel generează programul pentru toți piloții din coada manșei: `scheduled_start_at[i] = T0 + i × interval` (implicit `interval = 50 s`, `T0 = confirmare + lead_time`, configurabil), cu fereastră `[scheduled − 10 s, scheduled + 10 s]`.
5. Fiecare overlay de pilot primește ora proprie și fereastra; afișează countdown până la deschiderea ferestrei și starea „fereastră deschisă”.
6. Pilotul se aliniază și pleacă în fereastră. Plecarea este detectată din timing/telemetrie (vezi §7), nu din declarația aplicației.
7. Race Control urmărește automat starturile ratate și reprogramează conform regulilor (§6).

Intervalul și fereastra rămân configurabile per sezon/etapă/clasă. Ora nominală nu obligă plecarea la secundă; minimul între două plecări conforme este `interval − 2 × fereastră` (30 s cu valorile implicite). Laravel validează la configurare că acest minim rămâne ≥ pragul de siguranță aprobat.

## 6. Reguli pentru starturi ratate (Faza 2)

| Situație | Acțiune Race Control |
|---|---|
| Fereastra se închide fără plecare detectată, prima dată | Itemul pierde slotul (`missed_1`); pilotul trebuie să elibereze zona de start și să meargă la boxe; e mutat la coada cozii; primește **exact o** nouă oră de start. Slotul pierdut nu decalează piloții următori. |
| A doua ratare în aceeași manșă | `dns` pentru **acea manșă**; fără alte reîncercări automate. Nu afectează automat manșa cealaltă sau etapa. |
| HOLD / suspendare | Nicio fereastră nu se deschide; programul rămas se recalculează la reluare (nou `T0`); ratările nu se contorizează în timpul HOLD. |
| Pilot fără aplicație | Programul se aplică la fel; organizatorul îi comunică ora pe Discord (fallback); ratarea se tratează identic. |

Fiecare tranziție are audit, `idempotency_key`, `lock_version`, ca în `StartQueueService` actual.

## 7. Plecări anticipate sau neautorizate

- Surse de detecție: (a) agentul Node — timpul de start al turii / trecerea liniei (oficial); (b) opțional `CAR_UPDATE` (poziție/viteză server); (c) raportul aplicației (mișcare înainte de fereastră, ieșire din aliniere) — **doar dovadă, neîncredere**.
- Race Control creează un **incident** (`early_departure`, `late_departure`, `unauthorized_departure`) cu dovezile; **nicio penalizare automată**. Directorul de cursă decide după replay. Penalizările rămân separate de timing (modelul `Incident`/`Penalty` existent).

## 8. Aliniere (Faza 1, implementată)

### 8.1 Configurație
`DRSStarter/data/starts.json` (livrat, poate fi gol) + `DRSStarter/data/starts.local.json` (scris de calibrare). Format:

```json
{
  "schema": 1,
  "starts": [{
    "id": "rasnov-hc/up",
    "track": "<ac.getTrackID()>",
    "layout": "<ac.getTrackLayout() sau \"\">",
    "route": "up",
    "label": "Urcare",
    "line": { "p0": [x, y, z], "forward": [fx, 0, fz], "width_m": 8 },
    "target": { "offset_m": -0.30, "tol_back_m": 0.10, "tol_fwd_m": 0.10,
                "max_lateral_m": 4.0, "max_heading_deg": 8, "max_steer_deg": 0 },
    "stationary": { "max_speed_kmh": 0.5, "hold_s": 1.0, "max_drift_m": 0.02 },
    "approach_radius_m": 80,
    "source": "manual_capture | track_nodes",
    "calibrated_at": "…", "car": "…", "csp_build": 0
  }]
}
```
`max_steer_deg = 0` înseamnă verificare de bracare dezactivată până la măsurarea în joc (§8.4).

### 8.2 Calcul
- `F` = mijlocul `wheels[0].contactPoint` și `wheels[1].contactPoint` (FL, FR); fallback 1: mijlocul `wheels[0/1].position`; fallback 2: bara față `position + look·(aabbSize.z/2 − aabbCenter.z)`. Referința folosită se afișează în modul debug; cu fallback 2 aplicația nu afișează niciodată verde (doar „referință aproximativă”).
- Proiecție orizontală (X/Z). `f` = `forward` normalizat; `s = (f.z, 0, −f.x)`.
- `d = (F − P0)·f − offset_m` (0 = pe țintă; < 0 prea în spate; > 0 prea în față); `l = (F − P0)·s`; `θ` = unghiul dintre `look` orizontal și `f`.
- Stări: `NO_CONFIG`, `INVALID_CONFIG`, `NO_CAR`, `FAR`, `WRONG_DIRECTION`, `OFF_LANE`, `TOO_FAR_BACK`, `TOO_FAR_FORWARD`, `BAD_HEADING`, `STEER_NOT_STRAIGHT`, `MOVING`, `STABILIZING`, `ALIGNED`. Flag separat `alignmentLost` dacă pilotul a fost `ALIGNED` și a ieșit în ultimele 3 s.
- Histerezis: odată aliniat, ieșirea cere depășirea toleranței cu 2 cm sau a unghiului cu 1°, sau viteză > 1 km/h.
- Stabilitate: toate condițiile continuu `hold_s`, iar `F` nu se deplasează mai mult de `max_drift_m` față de punctul de intrare în zonă (altfel temporizatorul repornește).
- Protecții contra indicațiilor false: configurație lipsă/invalidă → niciodată verde; traseu/layout diferit → `NO_CONFIG`; valori non-finite → `NO_CAR`; replay/pauză → evaluarea se suspendă.

### 8.3 Calibrare
1. **Din traseu:** butonul „Din nodurile traseului” caută `AC_AB_START_L/R`; `P0` = mijlocul lor, lățimea = distanța, `forward` = perpendiculara orientată în sensul mașinii.
2. **Captură manuală:** organizatorul oprește mașina cu **roțile față pe linia de start** (linia vizibilă din joc), dreaptă; „Capturează” mediază `F` și direcția pe 1 s de oprire. `P0 = F`, `forward = look` orizontal.
3. Traseu invers: o captură separată cu `route` diferit, mașina orientată în sens invers.
4. Salvare în `data/starts.local.json`; offset/toleranțe ajustabile din fereastra de setări; „Exportă” scrie fișierul pe care organizatorul îl distribuie în `data/starts.json`.

### 8.4 Ce trebuie calibrat în joc
Repetabilitatea lui `d` (aceeași mașină, 10 opriri), efectul bracării (volan drept vs. ±90°), pantă/suspensie, diferențe între 3 mașini, corectitudinea vizuală a liniei 3D față de linia pictată, apoi valorile finale de toleranță.

## 9. Trimiterea la boxe după start ratat (Faza 2, NEVERIFICAT)

- Nu există dovezi că serverul/ACSM poate muta forțat o mașină. Singurul mecanism găsit este mutarea propriei mașini de către clientul pilotului într-un online script (`physics.setCarPosition(0, …)`), declanșată printr-un eveniment (exemplul oficial `admin_with_teleporter`). Necesită PoC pe ACSM 2.4.8 și nu poate fi impusă unui client necooperant.
- **Fallback (procedură):** overlay-ul afișează „START RATAT — Eliberează zona de start și mergi la boxe (ESC → Return to pits)”; Race Control afișează pilotul ca `missed_1 · must_clear`; operatorul verifică vizual/`CAR_UPDATE` că zona e liberă; dacă pilotul nu eliberează zona, directorul de cursă îl poate scoate de pe server din ACSM (kick manual, acțiune umană, auditată) și înregistrează un incident. Programul următorilor piloți nu așteaptă pilotul care a ratat.

## 10. Faza 2 — comunicare (proiectare inițială; vezi §4b pentru ce s-a implementat)

- Autentificare: pairing din My Race Day → token de dispozitiv (hash în DB, revocabil). Rol Safety Car separat, acordat per etapă de directorul de cursă; tokenul Safety Car nu are alte drepturi.
- Identificare etapă/clasă/manșă: din serverul la care e conectat clientul (`ac.getServerIP/PortHTTP` → `game_servers` → `event_class_servers`) + intrarea playerului; coroborare cu `CAR_INFO` din agentul Node.
- Transport: HTTPS polling (`web.request`), `poll_after_ms` dat de server (1 s aproape de fereastră, 5 s altfel), maximum 2 cereri simultane.
- Ceas: probe tip NTP cu RTT minim; ore absolute convertite în timp local monoton.
- Regula de siguranță: fără confirmare validă de la server în ultimele 5 s înainte de deschiderea ferestrei → overlay-ul arată **HOLD**, nu „fereastră deschisă”. Lipsa conexiunii nu produce niciodată un semnal de plecare.
- Confirmări (`ack`) pentru programul primit; comenzi vechi sau duplicate ignorate (`command_id`, `lock_version`, ora în trecut).
- Endpointuri, tabele și comenzi propuse: vezi IMPLEMENTATION_PLAN.md, Faza 2.

## 11. Structura aplicației (Faza 1)

```
DRSStarter/
  manifest.ini          fereastra principală, setări, draw3D
  DRSStarter.lua        intrare: ciclu de viață, legare module
  src/
    config.lua          constante: valori implicite, build CSP aprobat, versiune
    vec.lua             vectori 3D minimali (pur Lua, testabil)
    countdown.lua       countdown local repetitiv (pur)
    alignment.lua       geometrie + evaluare + stabilitate (pur)
    start_config.lua    parsare, validare, selecție configurații (pur, I/O injectat)
    procedure_local.lua stare demonstrativă Safety Car (pur)
    car_probe.lua       citește ac.getCar(0) → eșantion simplu
    track_nodes.lua     AC_AB_START_L/R → linie propusă
    calibration.lua     captură mediată
    style.lua           culori și fonturi din tokenurile DRS
    ui_driver.lua       overlay Driver Mode
    ui_safety.lua       overlay Safety Car Mode
    ui_settings.lua     mod, calibrare, debug
    world_draw.lua      zona de start în lume
    ui_common.lua       bara de sus (inclusiv starea Race Control)
    ui_safety_live.lua  Safety Car LIVE: confirmare în doi pași, HOLD, reluare (Faza 2)
    live/               Faza 2
      time_sync.lua     offset ceas tip NTP (proba cu RTT minim, fereastră 60 s)
      client.lua        HTTP (web.request), împerechere, /sync, evenimente persistente, comenzi
      live_model.lua    stare server → fază afișată; GO doar cu date proaspete
      departure.lua     detectare plecare / ieșire din zona de start
  fonts/                Barlow Condensed (OFL), din drs-design-system
  img/                  logo DRS (PNG), icon
  data/starts.json
tests/                  teste LuaJIT pentru modulele pure
```

## 12. Stil vizual

Direcția vizuală: macheta organizatorului. Tokenuri din `drs-design-system/tokens.json`: fundal panou `fras-black #231f20` (opac 88 %), accent `drs-orange #ff5a1f` și gradient `#ffa05c → #ff5a1f → #e8430c`, text `white`, meta `drs-gray #8a8d93` (4,9:1 pe negru), fonturi Barlow Condensed ExtraBold (titluri, cifre italic) și Inter pentru text. Colțuri `radius-sm/md` (4/8 px).

**Culori de stare — aprobate de organizator (3 noiembrie 2026):** macheta folosește verde/roșu/galben de stare. Design system-ul web nu are tokenuri de stare UI (verdele `flag-green` e doar pentru steag; `positive #15803d` și `negative = fras-red` doar pentru Trend). Am folosit `positive #15803d` (umplere, cu text alb) pentru „aliniat”, `fras-red #cf2028` pentru erori și `fras-yellow #fbd013` (cu text negru) pentru avertismente, deci culori existente în tokenuri, dar în afara utilizării lor documentate. Organizatorul a aprobat această utilizare pentru DRS Starter; dacă design system-ul primește ulterior tokenuri de stare dedicate, se înlocuiesc doar valorile din `src/style.lua`.

Panoul „Exemplu poziție” din machetă (trei cazuri: prea în spate, poziție corectă, prea în față) este inclus sub overlay, ca ilustrație statică; se poate ascunde din setări (`showExample`). Cu panoul, fereastra are 760×446 px de bază; fără el, 760×346.

Ce nu se poate reproduce direct în ImGui: fotografia/cockpit-ul (este scena jocului), umbre difuze și blur; zona verde de pe asfalt este desenată ca quad semi-transparent în lume, nu ca efect luminos.

## 13. Testare
- Automat (LuaJIT 2.1, în afara AC): countdown, geometrie, toleranțe, stabilitate, configurații invalide, procedura locală.
- Faza 2: `tests/live_run.lua` (ceas, model, client cu HTTP simulat), scenarii LIVE în `smoke_mock_csp.lua`, `tests/integration_laravel.lua` contra unui Laravel real local; 19 teste PHP în `drs_v2/tests/Feature/Starter`.
- In-game: checklist în `docs/IN_GAME_CHECKLIST.md`, **în așteptarea validării organizatorului**.
