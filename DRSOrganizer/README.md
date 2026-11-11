# DRS Organizer (doar pentru organizator)

Aplicație CSP Lua locală. **Nu se distribuie piloților.** Copiază folderul `DRSOrganizer` în
`...\assettocorsa\apps\lua\DRSOrganizer\` (calea manifestului: `apps\lua\DRSOrganizer\manifest.ini`).

## Fereastra „Coordonate start”
1. Alege ruta (Urcare / Sens invers / Alt start).
2. Oprește mașina dreaptă, cu **roțile din față exact pe linia de start**, apoi **Capturează** (1 s, mediat; refuzat dacă mașina se mișcă sau roțile nu se pot citi). Alternativ: **Din nodurile traseului** (`AC_AB_START_L/R`, dacă traseul le are). Verifică vizual linia desenată în lume.
3. **Copiază pentru ACSM (warm_tyres)** pune în clipboard blocul pentru `csp_extra_options.ini`:
   ```ini
   [SCRIPT_...]
   SCRIPT = <link către warm_tyres.lua, versiune fixă>
   startPos = X, Y, Z
   stopRadius = 20
   tempOffset = 0
   ```
   Linkul, raza și abaterea de temperatură se setează în fereastra Safety Car → ⚙ Setări.
4. **Copiază JSON pentru site** pune în clipboard linia completă (punct, direcție, lățime, țintă de aliniere), în formatul `starts.json` folosit de DRS Starter.
5. După captură, aplicația arată în timp real dacă mașina e aliniată față de linia capturată (țintă implicită: roțile față la 30 cm în spatele liniei, ±10 cm).

Istoricul capturilor (ultimele 50) rămâne în `DRSOrganizer\data\captures.json`.

## Fereastra „Safety Car”
Aceleași comenzi ca în DRS Starter Faza 2: **Confirmă sosirea la finish** (două apăsări în 4 s), **HOLD**, **Reluare**. Succesul apare doar după confirmarea serverului.
Conectarea: ⚙ Setări → adresa site-ului (`https://…`) → Împerechează → pe site, cu contul de organizator: Profilul meu → DRS Starter → codul. Contul are nevoie de rolul `safety_car` sau `race_director`.

## Cod comun
Modulele din `src/SHARED_FILES.txt` sunt copiate din `DRSStarter/src` cu `tools/sync_shared.sh`. Nu le edita aici; testul `tests/organizer_run.lua` verifică faptul că sunt identice.
