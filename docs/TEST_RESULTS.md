# DRS Starter — Rezultate teste

## Faza 2 (3 noiembrie 2026)

Rulat în containerul de dezvoltare (Linux, PHP 8.2, LuaJIT 2.1.1703358377), pe o copie a `drs_v2` cu modificările Fazei 2 și dependențele `vendor/` copiate de pe PC-ul organizatorului.

| Categorie | Ce s-a rulat | Rezultat |
|---|---|---|
| Laravel, suita completă | `php artisan test` (sqlite în memorie) | **192 trecute, 1 omis, 0 eșuate** (2092 aserțiuni) |
| Laravel, DRS Starter | `php artisan test tests/Feature/Starter` | **19/19** (623 aserțiuni): împerechere și revocare, confirmare idempotentă, program 50 s/±10 s, lead obligatoriu, ratare → reîncercare unică, a doua ratare → DNS doar cu dovezi/director, revizuire fără date, HOLD/reluare, incidente fără penalizare, heartbeat vechi ignorat, evenimente duplicate, drepturi Safety Car |
| Compilare Lua | `luajit -b` pe toate cele 27 de fișiere | OK |
| Lua unitare Faza 1 | `luajit tests/run.lua` | 30/30 |
| Lua Faza 2 | `luajit tests/live_run.lua` (ceas, model, client cu HTTP simulat) | 26/26 |
| Smoke CSP simulat | `luajit tests/smoke_mock_csp.lua` (inclusiv scenarii LIVE) | SMOKE OK |
| **Integrare HTTP reală** | `tools/integration/run.sh <drs_v2>`: `php artisan serve` + sqlite + modulele reale ale clientului Lua (curl) | **INTEGRARE OK**, 21/21 pași |
| Previzualizări | `tests/preview_svg.lua` → `docs/previews/layout_live_*.png`, `layout_safety_live.png` | generate, verificate vizual |
| **În joc / ACSM / Node** | — | **NERULATE** |

Ce nu dovedesc: comportamentul `web.request` real din CSP 0.3.1, abaterea reală de ceas între PC-uri, încărcarea la 30+ piloți, coordonarea cu timing-ul oficial.

### Ieșire `live_run.lua`
```
Sincronizare ceas
  ok   offset corect cu latență simetrică
  ok   alege eșantionul cu întârzierea minimă (latență asimetrică / răspuns întârziat)
  ok   eșantioane absurde respinse (RTT > 2 s, timp invers, tipuri greșite)
  ok   drift: eșantioanele vechi expiră și estimarea urmează ceasul nou
Model LIVE
  ok   countdown până la deschiderea ferestrei, din ora serverului
  ok   fereastră deschisă: autorizat; GO doar cu aliniere
  ok   după închidere: fără autorizare, clientul nu prelungește fereastra
  ok   stare veche (> stale_after_ms) → CONEXIUNE PIERDUTĂ, niciodată GO
  ok   HOLD de la server → fără autorizare chiar în fereastră
  ok   fără sincronizare de ceas → tratat ca neautorizat
  ok   a doua șansă: countdown spre noua fereastră + instrucțiune de eliberare a zonei
  ok   stări retry/DNS/analiză afișate din codul serverului
  ok   răspunsuri malformate respinse fără excepții
  ok   neîmperecheat / fără stare
Detecție plecare
  ok   plecare după aliniere: un singur raport, aliniat = true
  ok   plecare fără aliniere recentă → aliniat = false
  ok   ieșire din zonă înapoi / teleport la boxe → zone_left
  ok   fără a sta în zonă nu se raportează plecare (trecere în viteză)
Client Race Control (server simulat)
  ok   URL: doar https (http numai local)
  ok   împerechere: cod → token salvat, fără token în cereri publice
  ok   sincronizare: o cerere în zbor, Bearer, offset ceas, poll_after
  ok   evenimente: retrimise până la confirmare, secvențe monotone și persistente
  ok   401 → token șters, mesaj de reîmperechere; rețea → backoff
  ok   răspuns malformat: starea anterioară păstrată, devine STALE în timp
  ok   acțiune Safety Car: succes doar la 200 de la server
  ok   cerere fără callback: abandonată după 15 s, răspunsul întârziat ignorat

26 trecute, 0 eșuate
```

### Ieșire integrare
```
Integrare Laravel ↔ client DRS Starter (local, http://127.0.0.1:8765)
  ok   Safety Car împerecheat prin cod (device flow)
  ok   Pilot A împerecheat
  ok   Pilot B împerecheat
  ok   al doilea dispozitiv al pilotului A
  ok   pilot: așteaptă Safety Car (WAITING_SAFETY_CAR)
  ok   offset ceas estimat (±10 ms)
  ok   confirmarea cu tokenul unui pilot este refuzată (403)
  ok   Safety Car: confirmarea este permisă
  ok   Safety Car: sosire confirmată, program generat de server
  ok   a doua confirmare este idempotentă
  ok   pilot A: oră de start primită
  ok   model: countdown spre fereastră, fără GO (9 s)
  ok   fereastră deschisă + aliniat → GO (din ora serverului)
  ok   fereastră deschisă, nealiniat → fără GO
  ok   fără răspuns > 4 s → CONEXIUNE PIERDUTĂ, fără GO
  ok   raportul de plecare confirmat (ack) de server
  ok   pilot A: plecare înregistrată (DEPARTED)
  ok   pilot B fără date în fereastră → ÎN ANALIZĂ la Race Control (IN_REVIEW)
  ok   HOLD confirmat de server
  ok   piloții văd HOLD
  ok   reluare confirmată de server

INTEGRARE OK
```

---

## Faza 1

Rulat: 2026-11-03 20:58 UTC (re-rulat după adăugarea panoului „Exemplu poziție”), în containerul de dezvoltare (Linux), **LuaJIT 2.1.1703358377** (aceeași familie de runtime ca CSP: LuaJIT 2.1).

| Categorie | Ce s-a rulat | Rezultat |
|---|---|---|
| Compilare | `luajit -b` pe toate cele 19 fișiere Lua (aplicație + teste) | **OK**, 0 erori de sintaxă |
| Teste unitare (logică pură) | `luajit tests/run.lua` — countdown, aliniere, configurație, calibrare, Safety Car local | **30 trecute, 0 eșuate** |
| Smoke test cu API CSP **simulat** | `luajit tests/smoke_mock_csp.lua` — încarcă `DRSStarter.lua` cu stub-uri pentru `ac`, `ui`, `render`, rulează scenarii | **13/13 OK** |
| Previzualizare layout | `luajit tests/preview_svg.lua <stare>` → SVG randat cu Chromium (`docs/previews/`) | Generat pentru 4 stări (Driver Mode 760×446 cu „Exemplu poziție”, Safety Car 760×346); verificare vizuală manuală |
| **Teste în Assetto Corsa** | — | **NERULATE.** Pe acest PC nu există AC/CSP. Vezi `docs/IN_GAME_CHECKLIST.md`, în așteptarea organizatorului. |

**Ce NU dovedesc aceste teste:** că API-ul CSP 0.3.1 real are exact semnăturile folosite (stub-urile sunt scrise de mine după codul oficial CSP), că randarea ImGui/DirectWrite arată ca previzualizarea SVG, precizia reală a contactului roților, performanța în joc.

## Ieșire teste unitare
```
Countdown
  ok   stare inițială 40
  ok   decrementare pe timp scurs, nu pe cadre
  ok   reset la zero și semnal o singură dată
  ok   cicluri repetate fără drift (10000 de cadre neregulate)
  ok   salt mare de timp (cadru blocat 95 s)
  ok   pauză și reluare păstrează timpul rămas
  ok   ancoră restaurată după reîncărcare
  ok   durată configurabilă
Aliniere
  ok   țintă 30 cm în spatele liniei, aliniat după 1 s stabil
  ok   toleranță longitudinală ±10 cm
  ok   departe în spate = APROPIERE, foarte departe = FAR
  ok   toleranță de orientare 8°
  ok   mișcare: viteză peste 0,5 km/h nu e aliniată
  ok   alunecare lentă (drift > 2 cm) repornește stabilizarea
  ok   histerezis: rămâne aliniat la +10,5 cm, iese la +12,5 cm cu avertisment
  ok   referință aproximativă (fără roți) nu dă niciodată verde
  ok   lateral în afara culoarului
  ok   verificare bracare, dacă e activată
  ok   linie oblică și traseu invers (forward opus)
  ok   panta (diferență de înălțime) nu afectează distanța orizontală
Configurație
  ok   fără configurație → NO_CONFIG
  ok   configurație invalidă → INVALID_CONFIG
  ok   valori invalide respinse
  ok   valori implicite aplicate
  ok   selecție după traseu/layout și sens
  ok   merge: configurația locală înlocuiește pe cea livrată
Calibrare
  ok   captură mediată și dispersie
  ok   captură refuzată dacă mașina se mișcă sau lipsesc roțile
  ok   linie din nodurile de start, orientată după mașină
Safety Car (local demo)
  ok   confirmare idempotentă, HOLD și reluare

30 trecute, 0 eșuate
```

## Ieșire smoke test
```
Smoke test (API CSP simulat)
  ok   fără configurație: update/windowMain/settings/draw3D rulează fără erori
  ok   obiectul aplicației accesibil
  ok   configurație din AC_AB_START_L/R creată și activă
  ok   calibrarea salvată în data/starts.local.json
  ok   aliniat după ~1,4 s (stare: ALIGNED)
  ok   prea în față + avertisment pierdere aliniere
  ok   captură manuală finalizată: Salvat „test_hillclimb/-/invers” din 63 eșantioane, dispersie 0.0 cm.
  ok   aliniat pe linia capturată manual
  ok   countdown valid după salt mare (20)
  ok   Safety Car: confirmare locală înregistrată
  ok   Safety Car: HOLD local
  ok   replay → evaluare suspendată
  ok   fără roți → niciodată verde (stare: TOO_FAR_BACK)

SMOKE OK
```

## Rulare
```
cd C:\asseto\drs_start_app
luajit tests\run.lua
luajit tests\smoke_mock_csp.lua
luajit tests\live_run.lua
```
Integrarea cu Laravel (`tools/integration/run.sh`) este un script bash; pe Windows rulează din Git Bash sau WSL, cu `php`, `luajit` și `curl` în PATH.
Necesită LuaJIT 2.1 instalat local (nu este inclus).
