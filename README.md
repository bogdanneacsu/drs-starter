# DRS Starter

Repo: https://github.com/bogdanneacsu/drs-starter

Aplicație CSP Lua pentru Assetto Corsa care ajută piloții Digital Rally Series să-și poziționeze mașina la linia de start a urcărilor.

**Status:** Faza 1 (aplicație locală) testată în joc de organizator. **Faza 2 (sincronizare cu Race Control din Laravel) este implementată și testată local** (PHP, Lua, integrare HTTP reală); **nu a fost testată în joc și nici pe serverele ACSM/Node.** Modul demo local rămâne disponibil.

| Fișier | Conținut |
|---|---|
| `RESEARCH.md` | Cercetare API CSP / Python, surse, decizii confirmate (§0) |
| `ARCHITECTURE.md` | Arhitectură, moduri UI, timp local vs. autoritar, workflow Faza 2, reguli start ratat/DNS |
| `IMPLEMENTATION_PLAN.md` | Faza 1, Faza 2 (implementată, cu stare per element), Faza 3 |
| `docs/API_CONTRACT.md` | Contractul API v1 dintre aplicație și Laravel |
| `docs/PHASE2_OPERATIONS.md` | Configurare server, împerechere, test local, riscuri, checklist E2E, fișierele livrate în `drs_v2` |
| `DRSStarter/` | Aplicația piloților — se copiază în `assettocorsa/apps/lua/` |
| `DRSOrganizer/` | Aplicația organizatorului (coordonate start, Safety Car) — **nu se distribuie piloților**; vezi `DRSOrganizer/README.md` |
| `online/` | Scripturi online CSP livrate de ACSM (`warm_tyres.lua`); vezi `online/README.md` |
| `docs/INSTALL.md` | Instalare, moduri, calibrare, format configurație, depanare |
| `docs/IN_GAME_CHECKLIST.md` | Verificări în joc (de completat de organizator) |
| `docs/TEST_RESULTS.md` | Ce teste s-au rulat și rezultatele |
| `docs/previews/` | Previzualizări de layout (simulare SVG, nu capturi din joc) |
| `tests/` | Teste LuaJIT: unitare, Faza 2 (`live_run.lua`), smoke cu API simulat, integrare Laravel, generator de previzualizări |
| `tools/sync_shared.sh` | Copiază modulele comune din `DRSStarter/src` în `DRSOrganizer/src` |
| `tools/integration/` | Rularea integrării locale cu un Laravel real (sqlite, `artisan serve`) |

Fonturile din `DRSStarter/fonts` (Barlow Condensed, Inter) provin din `drs-design-system` și sunt sub licența SIL Open Font License (licența originală a familiilor de fonturi; fișierul de licență nu era inclus în design system).
