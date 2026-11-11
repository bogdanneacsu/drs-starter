# DRS STARTER — Plan de implementare

Data: 3 noiembrie 2026 (revizia 2) · Bază: RESEARCH.md §0, ARCHITECTURE.md

| Fază | Status |
|---|---|
| Faza 1 — Aplicație CSP locală | **Implementată** în `DRSStarter/`; teste automate rulate; testată în joc de organizator (aprobare pentru Faza 2) |
| Faza 2 — Sincronizare Laravel | **Implementată** (aprobată de organizator după testul Fazei 1 în joc): backend `drs_v2` + client CSP; teste automate și integrare HTTP locală trec; **netestată în joc și pe serverele ACSM/Node** |
| Faza 3 — Ambalare și validare în etapă reală | Planificată după Faza 2 |

## Faza 1 — DRS Starter local

### 1.1 Instalare și pornire
- Folder `DRSStarter/` copiat în `assettocorsa/apps/lua/` (instrucțiuni: `docs/INSTALL.md`).
- `manifest.ini` cu fereastra principală (overlay fără fundal), fereastra de setări, callback 3D.
- Verificare la pornire a build-ului CSP față de cel aprobat (avertisment, nu blocare).

### 1.2 Interfață vizuală
- Overlay compact după macheta organizatorului: bară de sus (logo, traseu/layout, ceas local, stare „LOCAL DEMO — fără Race Control”), countdown central, distanță până la țintă, stare aliniere cu cele trei verificări, ghid de aliniere (vedere de sus cu zona verde și poziția axei față), progres start, avertisment și panoul „Exemplu poziție” (trei cazuri ilustrative, ascunzibil din setări).
- Scalare după lățimea ferestrei; fonturile DRS (Barlow Condensed) livrate cu aplicația.
- Zona de start desenată pe asfalt (quad semi-transparent + contur).

### 1.3 Countdown local repetitiv 40 s
- `src/countdown.lua`, pur, ancoră monotonă, fără drift, pauză/reluare/reset, durată configurabilă, persistarea ancorei la reîncărcare.
- Etichetat permanent ca demonstrație locală; „GO (DEMO)” la zero.

### 1.4 Evaluare locală a alinierii
- `src/alignment.lua`: distanță cu semn, lateral, orientare, bracare (opțional), oprire stabilă 1 s cu drift, histerezis, fallback-uri de referință.

### 1.5 Calibrare traseu
- Captură manuală mediată, propunere din `AC_AB_START_L/R`, rute multiple (inclusiv sens invers), ajustare offset/toleranțe, salvare `data/starts.local.json`.

### 1.6 Safety Car local
- Mod Safety Car cu panou de stare, „Confirmă sosirea la finish”, HOLD/Reluare local, etichetă LOCAL DEMO MODE; adaptor de procedură înlocuibil în Faza 2.

### 1.7 Teste și verificare în joc
- Automat: `tests/run.lua` (LuaJIT 2.1).
- În joc: `docs/IN_GAME_CHECKLIST.md`.

**Criterii de acceptare Faza 1**
1. Aplicația se încarcă în CSP-ul aprobat, fără erori în Lua Debug.
2. Countdown 40 → 1 → „0 · GO (DEMO)” → 40, fără drift măsurabil după 30 de minute (comparat cu un cronometru).
3. Pe un traseu calibrat, cu cel puțin 3 mașini, verdele apare doar când axa față e în zona configurată (verificare vizuală cu camera exterioară).
4. Repetabilitatea lui `d` măsurată și raportată (țintă < 1 cm); efectul bracării măsurat.
5. Orientare > 8° sau sens invers → niciodată verde; alunecarea lentă → niciodată verde.
6. Fără configurație → mesaj „Traseu necalibrat”, niciodată verde.
7. Safety Car Mode: butoanele schimbă doar starea locală, cu eticheta LOCAL DEMO MODE.
8. Reîncărcarea aplicației nu blochează jocul și nu resetează calibrarea.
9. Impact FPS < 1 % (contorul CSP), în aceeași scenă, cu și fără aplicație.

**Riscuri Faza 1:** câmpuri API diferite în 0.3.1 față de SDK-ul consultat (atenuare: checklist pas 1, fallback-uri); fonturile nu se încarcă (fallback automat pe fontul implicit CSP); traseele fără noduri de start (captură manuală); calibrare imprecisă (captură mediată, afișarea dispersiei).

## Faza 2 — Sincronizare Laravel (implementată 3 noiembrie 2026)

Detalii: ARCHITECTURE.md §4b, `docs/API_CONTRACT.md`, `docs/PHASE2_OPERATIONS.md`. Legendă: **I** implementat · **L** testat local automat · **J** testat în joc · **S** testat pe serverele reale.

| # | Element | I | L | J | S |
|---|---|---|---|---|---|
| 2.1 | Confirmare Safety Car autentificată (rol `safety_car`, permisiune `confirm starter finish`, idempotentă, auditată) | ✓ | ✓ | — | — |
| 2.2 | Program absolut generat de server (50 s, ±10 s, lead configurabil per clasă, fără valoare implicită ascunsă) | ✓ | ✓ | — | — |
| 2.3 | Program individual pentru pilot (`/sync` → `me.slot`, poziție, încercări) | ✓ | ✓ | — | — |
| 2.4 | Sincronizare ceas (NTP pe fiecare `/sync`, RTT minim, respingere RTT > 2 s) | ✓ | ✓ | — | — |
| 2.5 | Confirmări (`acks` pentru evenimente, `seq` monoton pentru heartbeat) | ✓ | ✓ | — | — |
| 2.6 | Start ratat → o singură reîncercare la coada cozii, mesaj „eliberează zona” | ✓ | ✓ | — | — |
| 2.7 | DNS doar cu dovezi suficiente sau decizia directorului; altfel `dns_pending` | ✓ | ✓ | — | — |
| 2.8 | HOLD / reluare cu decalare sigură | ✓ | ✓ | — | — |
| 2.9 | Trimiterea la boxe | fallback procedural | — | — | — |
| 2.10 | Incidente fără penalizare; timpii oficiali neatinși | ✓ | ✓ | — | — |
| 2.11 | Token revocabil, rate limit, tranzacții + blocări, audit, CONEXIUNE PIERDUTĂ fără GO | ✓ | ✓ | — | — |
| 2.12 | Panou Starter în consola Race Control | ✓ | endpointuri | — | — |
| 2.13 | Plecare din timing-ul oficial (agent Node) | — | — | — | — |

**Rămase pentru sesiunea de test complet:** checklist-ul din `docs/PHASE2_OPERATIONS.md` §6; măsurarea abaterii între PC-uri (țintă ≤ 250 ms); PoC teleport; eventual integrarea plecării din agentul Node (sprint separat, cu aprobare).

## Faza 3 — Ambalare și validare reală
- ZIP versionat, tutorial, matrice trasee × mașini, test de performanță cu grilă completă, repetiție generală cu fallback Discord pregătit.

## Întrebări rămase pentru organizator
1. Confirmă versiunea și build-ul CSP aprobat (am folosit 0.3.1 / 4302 din arhiva comunitară).
2. ~~Culorile de stare~~ — **aprobate** de organizator pe 3 noiembrie 2026 (verde `positive`, roșu `fras-red`, galben `fras-yellow`).
3. ~~`lead_time_s`~~ — implementat ca setare per clasă în consola Race Control (fără valoare implicită); organizatorul alege valoarea înainte de etapă.
4. HOLD: implementat pentru Safety Car și operatorii Race Control (inclusiv directorul). Organizatorul poate cere restrângerea.
5. Detecția oficială a „plecării”: acum raportul aplicației (prima mișcare de ≥ 1,5 m peste linie) sau pornirea manuală din coadă. Rămâne de decis dacă se adaugă trecerea liniei din agentul Node.
