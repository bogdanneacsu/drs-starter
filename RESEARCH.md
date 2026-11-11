# DRS STARTER — Cercetare tehnică (Faza 0)

Data: 3 noiembrie 2026 · Status: **cercetare, fără implementare** · Autor: Claude (pentru Bogdan / DRS)

Acest document separă strict ce am **verificat în cod sursă sau documentație primară** de ce este **documentat, dar netestat**, de **soluții plauzibile** și de **ipoteze nesusținute**. Nimic din acest document nu a fost testat încă într-o instanță Assetto Corsa reală. Toate concluziile de precizie trebuie confirmate în D1.

## 0. Actualizare 3 noiembrie 2026 — decizii confirmate de organizator

Deciziile de mai jos înlocuiesc variantele deschise din restul documentului acolo unde diferă. Detaliile de proiectare sunt în ARCHITECTURE.md.

| Subiect | Decizie confirmată |
|---|---|
| Tehnologie | Aplicație CSP Lua instalată de pilot; fără companion, fără Python. |
| Versiune CSP | **O singură versiune CSP aprobată de organizator**, obligatorie pentru toți participanții. Fără compatibilitate cu versiuni vechi. Organizatorul a cerut „cea mai recentă versiune publică stabilă”. |
| Starturi | Fără operator care pornește manual fiecare pilot (Faza 2). Safety Car confirmă sosirea la finish din overlay → Laravel validează → Laravel generează orele de start ale tuturor piloților din manșă → piloții le primesc în overlay. |
| Program | Interval nominal **50 s**; fereastră de plecare **±10 s** față de ora programată; interval minim între două plecări conforme = 30 s. Ambele configurabile în backend. Ora nominală nu este obligația de a pleca la secundă. |
| Start ratat | Prima ratare: pierde slotul, iese din zona de start la boxe, trece la coada cozii, primește exact o nouă șansă. A doua ratare: **DNS pentru acea manșă** (nu pentru toată etapa). |
| Plecare anticipată/neautorizată | Se detectează și se raportează; **fără penalizare automată**. Decide directorul de cursă după replay și dovezi. Timing-ul oficial rămâne Node/Kunos. |
| Moduri UI | Driver Mode și Safety Car Mode în aceeași aplicație. În Faza 2, controalele Safety Car sunt autentificate și limitate la operatori autorizați, fără drepturi de administrare generale. |
| Aliniere (valori inițiale, de calibrat) | Mijlocul contactelor roților față la **30 cm în spatele** liniei de start; toleranță longitudinală **±10 cm**; orientare **8°**; viteză **< 0,5 km/h**; aliniere stabilă ~**1 s**; configurații per traseu/layout, inclusiv sens invers. |
| Culori de stare | Aprobate: verde `positive #15803d`, roșu `fras-red #cf2028`, galben `fras-yellow #fbd013`. Panoul „Exemplu poziție” din machetă se include. |
| Faza 1 | Doar aplicație locală: overlay, aliniere, calibrare, countdown local repetitiv 40 s (doar pentru test UI), shell Safety Car local. Fără Laravel, fără rețea. |

### 0.1 Versiunea CSP țintă

- **Ținta Faza 1: CSP 0.3.1 (public), build 4302, publicat 2026-10-29**, conform arhivei comunitare de changelog-uri https://c1xtz.github.io/csp-logs/ și https://c1xtz.github.io/csp-logs/0-3-1. Cea mai nouă versiune listată acolo este 0.3.2-preview2 (build 4305), care este preview, deci nu este „publică stabilă”.
- **Neconfirmat din sursa oficială:** site-ul oficial https://acstuff.club/patch/ nu este accesibil din mediul meu de lucru (blocat de proxy). Organizatorul trebuie să confirme versiunea și build-ul din Content Manager → Settings → Custom Shaders Patch înainte de testul în joc.
- **API-urile folosite au fost verificate în** `acc-lua-sdk` (commit `7cf60f5`, 17.08.2026) și în aplicațiile oficiale CSP (`acc-lua-internal` `2031bd2`, `app-csp-defaults` `7b9a279`, 09.09.2026). Aceste commit-uri sunt anterioare publicării 0.3.1. Changelog-ul 0.3.1 nu menționează schimbări de API Lua. Riscul rezidual este mic, dar **verificarea finală se face pe PC-ul de test**, comparând cu `assettocorsa/extension/internal/lua-sdk` din instalarea 0.3.1 (pas în checklist-ul in-game).
- **Pe acest PC nu există Assetto Corsa, CSP sau SDK-ul local** (confirmat de organizator). Nimic din aplicație nu a rulat în joc.

### 0.2 API-uri folosite de aplicația Faza 1 și dovada lor

| API | Dovadă (folosire reală în cod oficial) |
|---|---|
| `ac.getCar(0)`, `.position`, `.look`, `.speedKmh`, `.steer`, `.aabbSize`, `.aabbCenter` | rally mode, DynamicReturn, Radar |
| `car.wheels[0/1].contactPoint`, `.position` | CspDebug, ghost.lua |
| `ac.getTrackID()`, `ac.getTrackLayout()` | hotlap.lua (comparație track + layout) |
| `ac.findNodes('AC_AB_START_L')`, `#ref > 0`, `:getPosition()` | rally mode, CspDebug (`#ref`), `lib_scene.lua` (`__len`) |
| `ac.getSim()`: `isPaused`, `isReplayActive`, `isInMainMenu` | DynamicReturn |
| `os.preciseClock()` | rally mode, DynamicReturn |
| `ac.storage{...}` | Clock, rally mode |
| `io.load`, `io.save`, `io.fileExists`, `__dirname`, `JSON.parse/stringify` | app-csp-defaults (config.json) |
| `ui.drawRectFilled`, `ui.drawRect`, `ui.drawLine`, `ui.drawCircleFilled`, `ui.pathLineTo`, `ui.pathFillConvex`, `ui.setCursor`, `ui.invisibleButton`, `ui.itemClicked`, `ui.button`, `ui.checkbox`, `ui.slider`, `ui.text`, `ui.windowSize` | multiple aplicații oficiale |
| `ui.DWriteFont(name, dir):weight(...):style(...)`, `ui.pushDWriteFont`, `ui.popDWriteFont`, `ui.dwriteDrawText`, `ui.dwriteTextAligned`, `ui.measureDWriteText` | `ac_ui.d.lua` (documentație) + android_auto, traffic tool |
| `ui.drawImage(path, p1, p2)` | WebBrowser |
| `render.debugLine`, `render.setBlendMode`, `render.setDepthMode`, `render.glBegin/glSetColor/glVertex/glEnd` (Quads) | traffic editor, CspDebug; enum-urile în `ac_render_enums.lua` |
| `[RENDER_CALLBACKS] TRANSPARENT = draw3D` | CspDebug manifest |

### 0.3 Incertitudini rămase (de rezolvat înainte de Faza 2)

1. **Trimiterea forțată la boxe (teleport).** Nu există dovezi că ACSM sau serverul AC pot muta forțat mașina unui pilot. Exemplul oficial CSP `online/admin_with_teleporter` arată că mutarea se face **doar de clientul pilotului însuși** (`physics.setCarPosition(0, …)` într-un *online script*, declanșat printr-un `ac.OnlineEvent` broadcast prin mesaje de chat ascunse). Asta înseamnă: (a) funcționează numai dacă scriptul online rulează la pilot și cooperează; (b) un client modificat poate ignora comanda; (c) nu este verificat pe ACSM 2.4.8; (d) nu am verificat dacă o aplicație Lua obișnuită (nu online script) are voie să apeleze `physics.setCarPosition` online. **Status: NEVERIFICAT.** Fallback propus în ARCHITECTURE.md §9.
2. **Controalele in-game:** butoanele ImGui din ferestrele aplicațiilor CSP funcționează cu mouse-ul (confirmat în cod oficial). Utilizarea în timpul condusului, pe volan, ar cere taste/butoane mapate (`ac.ControlButton`, folosit în 78 de locuri în cod oficial) — neimplementat în Faza 1, de evaluat.
3. **Sincronizarea cu serverul** — implementată în Faza 2 și testată local (§0.4); netestată în joc.
4. **Precizia reală a contactului roților** (bracare, suspensie, pantă) nu este măsurată; valorile din §0 sunt implicite de inginerie, nu validate.

### 0.4 Faza 2 — dovezi și limite (3 noiembrie 2026)

- **HTTP în CSP:** `web.request(method, url, headers, body, callback(err, response))`, cu `response.status`, `response.headers`, `response.body`, asincron, cel mult 2 cereri simultane per script (`acc-lua-sdk` `common/ac_web.lua`, commit `7cf60f5`). Clientul folosește o singură cerere `/sync` în zbor și o singură comandă; o cerere fără răspuns este abandonată după 15 s. **CONFIRMAT-COD, netestat în joc.**
- **Timp:** `os.preciseClock()` (monoton) + offset estimat din schimburi NTP pe fiecare `/sync`. Ceasul Windows nu este folosit.
- **Identitate:** SDK-ul nu oferă un Steam ID verificabil pentru aplicațiile Lua; oricum GUID-ul nu este dovadă. Identitatea vine din token de dispozitiv emis contului DRS prin împerechere cu cod.
- **Teleport la boxe:** rămâne **NEVERIFICAT** (§0.3.1). Fallback implementat: instrucțiune în aplicație, raport „zonă părăsită” trimis serverului ca dovadă, verificare de Race Control, kick manual din ACSM.
- **Plecarea oficială:** agentul Node (`C:\asseto\livetiming`) nu a fost modificat. Plecarea vine din raportul aplicației sau din pornirea manuală din coadă; lipsa datelor duce la revizuire, nu la DNS.

## Legendă de încredere

| Etichetă | Sens |
|---|---|
| **CONFIRMAT-COD** | Funcția apare în codul sursă oficial CSP sau într-o aplicație oficială CSP care o folosește efectiv. Nu am rulat-o eu. |
| **DOCUMENTAT** | Apare în documentația primară (wiki CSP, definițiile SDK, fișiere Kunos), fără exemplu de utilizare găsit. |
| **PLAUZIBIL** | Rezultă logic din capabilități confirmate, dar necesită PoC. |
| **NESUSȚINUT** | Nu am găsit dovezi; nu se proiectează nimic care depinde de el. |

## 1. Rezumat

1. **CSP Lua** expune tot ce trebuie pentru aliniere: poziția și orientarea mașinii, poziția fiecărei roți și punctul de contact al anvelopei cu solul, dimensiunile caroseriei (AABB), viteza, frâna de mână, ID-ul și layoutul traseului, nodurile din traseu (`AC_AB_START_L/R`) și desenare 3D în lume. **CONFIRMAT-COD.**
2. **CSP conține deja o implementare de referință** a exact acestui flux: modul „Rally Stage” (`acc-lua-internal/included-new-modes/rally/mode.lua`, autor x4fab) calculează distanța cu semn față de linia de start, afișează „Take a step back / Get to the start / Hold handbrake”, așteaptă mașina oprită și frâna ținută, rulează un countdown și descalifică la plecare înainte de start. **CONFIRMAT-COD** (autorul îl descrie ca „proof-of-concept”).
3. **Rețea din CSP Lua:** `web.get/post/request` (HTTP și HTTPS prin WinHTTP) și `web.socket` (client WebSocket cu reconectare automată opțională). Aplicații oficiale CSP (Setup Exchange, Rally Copilot Notes Exchange, RGB Control) comunică HTTPS cu un server extern, cu sesiune proprie. **CONFIRMAT-COD.** Limită documentată: **maximum 2 cereri HTTP simultane** implicit (configurabil până la 32 cu `web.timeouts`).
4. **Python (aplicații Kunos):** are poziția mașinii și punctul de contact pe roată (`acsys.CS.TyreContactPoint`), dar runtime-ul este Python 3.3, fără `socket` inclus (aplicațiile îl livrează ca `_socket.pyd`), fără WebSocket, cu HTTPS dificil, iar UI-ul este primitiv. **Nu este recomandat.**
5. **Companion Windows: nu este justificat**, pentru că CSP Lua are deja HTTPS și WebSocket nativ. Ar adăuga un proces, un installer și o suprafață de atac fără câștig real.
6. **Sincronizarea cu Race Control este fezabilă tehnic** pe partea de client (HTTPS polling + countdown pe timestamp țintă cu offset de ceas). **Necesită însă endpointuri și stări noi în Laravel**, care azi nu există (vezi §6). Aplicația nu poate dovedi singură poziția corectă; Race Control trebuie să o trateze ca semnal, nu ca probă.
7. **Recomandare:** aplicație **CSP Lua** instalată de pilot (`apps/lua/DRSStarter`), cu sincronizare Race Control opțională prin HTTPS polling. Ca variantă de distribuție, de evaluat în PoC: **„online script” livrat de server** prin opțiunile extra CSP din ACSM (fără instalare la pilot).

## 2. Surse primare consultate

Toate depozitele au fost clonate local și inspectate (commit-urile de pe ramura `main` la data cercetării).

| # | Sursă | Ce demonstrează |
|---|---|---|
| S1 | https://github.com/ac-custom-shaders-patch/acc-lua-sdk (commit `7cf60f5`, 17.08.2026) | Bibliotecile Lua CSP: `ac.getCar()`, modulul `web` (`common/ac_web.lua`, `lib_web.lua`), restricțiile scripturilor online (`ac_online_script.lua`, `common/secure.lua`), enum-ul `ac.Wheel` (0 = FrontLeft…). |
| S2 | https://github.com/ac-custom-shaders-patch/acc-lua-sdk/wiki/Lua-apps | Structura aplicației Lua (`apps/lua/<App>/manifest.ini` + `<App>.lua`), ferestre ImGui, `script.update(dt)`, callback-uri 3D `[RENDER_CALLBACKS]`, `[UI_CALLBACKS] IN_GAME`, Lua 5.1 / LuaJIT 2.1, disponibil din CSP 0.1.76. |
| S3 | https://github.com/ac-custom-shaders-patch/acc-lua-sdk/wiki/Important-notes | Aplicațiile Lua au acces complet I/O (fișiere, procese, memorie partajată); scripturile online nu. `ffi.load()` dezactivat. Nu folosiți nimic cu prefix `_`. Folosiți `setInterval` pentru actualizări lente. |
| S4 | https://github.com/ac-custom-shaders-patch/acc-lua-internal (commit `2031bd2`, 17.08.2026) — `included-new-modes/rally/mode.lua` | Implementare de referință: linie de start din nodurile `AC_AB_START_L`/`AC_AB_START_R` (`ac.findNodes`), distanță cu semn, aproximare bară față `car.position + car.look * (car.aabbSize.z/2 - car.aabbCenter.z)`, condiție „oprit + frână ținută > 1 s”, countdown 3-2-1-Go, descalificare la mișcare înainte de start. |
| S5 | acelasi depozit — `included-apps/CspDebug/CspDebug.lua` (liniile ~792–798) | Folosire reală `ac.StateWheel`: `tyre.contactPoint`, `tyre.position`, `tyre.transform.side/look`, `tyre.tyreWidth`. |
| S6 | acelasi depozit — `lua-shared/sim/ghost.lua` (liniile 60–61) | `car.wheels[0..3].position` în coordonate lume. |
| S7 | https://github.com/ac-custom-shaders-patch/app-csp-defaults (commit `7b9a279`, 09.09.2026) — `SetupExchange`, `RallyCopilot/src/NotesExchange.lua`, `RGBControl` | Aplicații oficiale CSP care fac `web.request('POST'/'PATCH', https…)` către un server extern, cu sesiune și semnătură. `REQUIRED_VERSION` în manifest. |
| S8 | acelasi depozit — `DynamicReturn`, `Radar`, `TrackCoordinatesHelper` | `car.aabbSize`, `car.aabbCenter`, `car.look`, coordonate lume ↔ geografice (unități = metri). |
| S9 | https://github.com/ac-custom-shaders-patch/acc-extension-config/wiki/Misc-%E2%80%93-Server-extra-options (secțiunea „Online scripts”) | Serverul poate livra un script Lua prin URL (`[SCRIPT_...] SCRIPT = 'https://…?t={SteamID}&s={SessionID}…'`), cu `REQUIRED = 1`; scripturile online nu au acces la fișiere și procese. Din CSP 0.1.76. |
| S10 | https://github.com/ac-custom-shaders-patch/acc-lua-examples — `online/lemans_start` | Exemplu de procedură de start online implementată ca script online. |
| S11 | https://github.com/ac-custom-shaders-patch/acc-extension-config/wiki/Python-Apps-%E2%80%93-New-functions | Funcțiile `ac.ext_*` adăugate de CSP pentru Python (fără rețea, fără noduri de traseu, fără Steam ID). |
| S12 | https://github.com/trashcutter/TractionLoss/blob/master/apps/python/tractionLoss/acsys.py | Lista `acsys.CS`: `WorldPosition`, `TyreContactPoint`, `TyreHeadingVector`, `TyreRightVector`, `Velocity`, `LocalVelocity`, `SpeedKMH`, `NormalizedSplinePosition`. |
| S13 | https://github.com/styinx/ACLIB/blob/master/apps/python/ACLIB/source/memory/sim_info.py | Memoria partajată Kunos: `heading`, `pitch`, `roll`, `tyreContactPoint[4][3]`, `tyreContactHeading`, `carCoordinates`, `velocity`. |
| S14 | https://assettocorsamods.net/threads/car-world-position-wrong.1990/ | `WorldPosition` e unică pe mașină; pentru roți se folosește `TyreContactPoint` cu `acsys.WHEELS.FL/FR…`. |
| S15 | https://github.com/albertowd/SetupShare (2018) | Aplicație Python cu rețea: livrează `stdlib/_socket.pyd` și `stdlib64/_socket.pyd`, bibliotecă `requests` vendorizată, API pe **HTTP simplu**. |
| S16 | https://github.com/dcratliff19/ACPythonDocsMarkdown | Documentația Python Kunos în Markdown: `ac.newApp`, `ac.addLabel`, `ac.addRenderCallback`, `ac.gl*` (primitive 2D). |
| S17 | https://assettocorsamods.net/threads/how-to-make-a-simple-countdown-apps-lua.3592/ | Countdown în Lua folosind `sim.timeToSessionStart`, desen ImGui, sunet. Doar single-player. |
| S18 | https://forum.emperorservers.com/t/how-enable-extended-fisics/453 | ACSM v2: „Server → Options → Enable Extra Custom Shaders Patch Options”, apoi secțiunea CSP din formularul evenimentului. |
| S19 | Proiect DRS V2 (doar citire): `app/Domain/RaceControl/StartQueueService.php`, `app/Models/StartQueueItem.php`, `RaceControlSetting.php`, `routes/api.php`, `docs/architecture/DRS_V2_Arhitectura_DB_si_Migrare.md` §20, `S3_plan` §11 | Starea actuală a cozii de start și a API-ului (vezi §6). |

## 3. Opțiunea A — Aplicație Python Kunos

| Capabilitate | Constatare | Încredere |
|---|---|---|
| Runtime | Python 3.3 încorporat în AC (versiunea 3.3.5 este larg raportată în comunitate; nu am verificat binarul). AC este 64-bit; aplicațiile livrează `stdlib64` (S15). | DOCUMENTAT (comunitate) |
| Structură | `apps/python/<App>/<App>.py` cu `acMain`, `acUpdate(deltaT)`, `acShutdown`. | DOCUMENTAT (S16) |
| UI | Ferestre cu etichete, butoane, grafice, `ac.gl*` (linii, quad-uri 2D). Fără desen 3D în lume, fără fonturi moderne. CSP adaugă `ext_glFont*`, shadere pixel (S11). | DOCUMENTAT |
| Poziție mașină | `ac.getCarState(0, acsys.CS.WorldPosition)` → (x, y, z). | DOCUMENTAT (S12, S14) |
| Orientare | Nu există „heading” direct în `getCarState`; există `TyreHeadingVector` per roată; memoria partajată are `heading/pitch/roll` (S13). | DOCUMENTAT |
| Roți / contact | `ac.getCarState(0, acsys.CS.TyreContactPoint, acsys.WHEELS.FL)` → punct contact roată în lume. | DOCUMENTAT (S14) |
| Viteză / oprire | `SpeedKMH`, `Velocity`, `LocalVelocity`. Frâna de mână: `ac.ext_getHandbrake` (doar cu CSP). | DOCUMENTAT |
| Traseu | `ac.getTrackName/Configuration`; noduri KN5 (`AC_AB_START_L/R`) **nu** sunt accesibile; doar spline-ul AI (`ext_worldToSpline`). | DOCUMENTAT (S11) |
| Rețea | Fără `socket` inclus; se livrează `_socket.pyd`. HTTPS ar necesita `_ssl.pyd` + OpenSSL compatibil cu Python 3.3 (stack TLS foarte vechi). Exemplul găsit (S15) folosește HTTP simplu. Fără WebSocket. | PLAUZIBIL / riscant |
| Thread-uri | `threading` funcționează în practică în multe aplicații, dar un apel blocant pe thread-ul principal îngheață jocul. | PLAUZIBIL |
| Instalare | Copiere folder în `apps/python`, activare în CM/AC. Binare `.pyd` copiate manual (alerte antivirus posibile). | DOCUMENTAT |
| Mentenanță | Python 3.3 este EOL din 2017; biblioteca `requests` trebuie vendorizată în versiune veche; TLS modern nesigur. | Risc ridicat |

**Concluzie A:** alinierea ar fi posibilă (punct de contact roată disponibil), dar fără noduri de traseu, fără desen 3D al liniei, cu UI slab și rețea HTTPS fragilă. Varianta are dezavantaje la toate prioritățile 2–5.

## 4. Opțiunea B — Aplicație Lua Custom Shaders Patch

### 4.1 Platformă
- Lua 5.1 / LuaJIT 2.1, disponibil din CSP 0.1.76 (S2). Aplicația stă în `assettocorsa/apps/lua/<App>/` cu `manifest.ini` și `<App>.lua` (S2).
- UI: Dear ImGui (`ui.*`), ferestre mutabile/fără fundal (`NO_BACKGROUND`, `NO_TITLE_BAR`, `FADING`), HUD full-screen prin `[UI_CALLBACKS] IN_GAME` + `ui.transparentWindow()`, desen 3D în lume prin `[RENDER_CALLBACKS] TRANSPARENT` și funcțiile `render.debug*` (`render.debugArrow`, `render.debugText` folosite în S4). Fonturi DirectWrite (`ui.dwriteTextAligned`, S17). Sunet (`ui.MediaPlayer`, S17). **CONFIRMAT-COD**.
- Persistență: `ac.storage{}` (setări per aplicație), fișiere (`io.*`, `ac.INIConfig`), SQLite prin `shared/utils/dbstorage` (folosit în S4). **CONFIRMAT-COD**.
- Debug: definiții EmmyLua livrate în CSP (`extension/internal/lua-sdk`) pentru VS Code + extensia Lua sumneko; aplicația „Lua Debug” din CSP; `ac.debug(key, value)` și `ac.log()`. **DOCUMENTAT (S1 README, S17).**

### 4.2 Date despre mașină (`ac.getCar(0)` → `ac.StateCar`, actualizat o dată pe cadru grafic)
| Câmp | Folosire reală găsită | Încredere |
|---|---|---|
| `car.position`, `car.look`, `car.side`, `car.up` | rally mode, DynamicReturn | CONFIRMAT-COD |
| `car.transform`, `car.bodyTransform`, `car.worldToLocal` | RaceCarTracker, rally mode | CONFIRMAT-COD |
| `car.aabbSize`, `car.aabbCenter` (dimensiuni caroserie, spațiu local) | rally mode, Radar, DynamicReturn | CONFIRMAT-COD |
| `car.wheels[0..3].position` (centrul roții, lume) | ghost.lua | CONFIRMAT-COD |
| `car.wheels[i].contactPoint`, `.transform`, `.tyreWidth` | CspDebug | CONFIRMAT-COD |
| `car.speedKmh`, `car.speedMs`, `car.velocity` | multiple | CONFIRMAT-COD |
| `car.handbrake`, `car.brake`, `car.gas`, `car.gear`, `car.steer` | rally mode | CONFIRMAT-COD |
| `car.isAIControlled`, `car.isConnected`, `car.sessionID` | rally mode, multiple | CONFIRMAT-COD |
| Indexul roților: `ac.Wheel.FrontLeft = 0`, FR = 1, RL = 2, RR = 3 (stabil, garantat de autor) | `ac_enums.lua`, S3 | DOCUMENTAT |

Nu am putut citi lista completă a câmpurilor `ac.StateCar` din depozit (structura FFI este generată în build-ul CSP). Definițiile complete se găsesc local în `assettocorsa/extension/internal/lua-sdk` pe orice PC cu CSP; le verificăm în primul pas din D1.

### 4.3 Date despre traseu și sesiune
- `ac.getTrackID()`, `ac.getTrackLayout()`, `ac.getTrackFullID()` — folosite în aplicații oficiale. **CONFIRMAT-COD.**
- `ac.findNodes('AC_AB_START_L'):getPosition()` — punctele de start A→B din KN5. **CONFIRMAT-COD (S4).** Nu orice traseu de hillclimb are aceste noduri; rally mode are fallback pe spline.
- `ac.trackProgressToWorldCoordinate()` / `ac.worldCoordinateToTrackProgress()` — conversie spline ↔ lume. **CONFIRMAT-COD.**
- `ac.getSim()`: `sim.dt`, `sim.isOnline`(?), `sim.timeToSessionStart`, `sim.systemTime`, `sim.isPaused`, `sim.isReplayActive`, `sim.cameraMode`. `timeToSessionStart`, `systemTime`, `isReplayActive` sunt **CONFIRMAT-COD**; semantica exactă a `systemTime` trebuie verificată în definiții.
- `ac.getServerIP()`, `ac.getServerPortHTTP()`, `ac.getServerName()` — **CONFIRMAT-COD** (folosite în acc-lua-internal). Permit aplicației să afle **pe ce server DRS** este conectată, deci Laravel poate deduce etapa și clasa din maparea `game_servers → event_class_servers`.
- Ceas: `os.preciseClock()` (monoton, înaltă rezoluție, folosit în S4), `os.time()` (secunde).

### 4.4 Rețea
- `web.get / web.post / web.request(method, url, headers, body, callback)` — HTTP și HTTPS, asincron, implementat pe WinHTTP (`web.timeouts` trimite la `WinHttpSetTimeouts`). **Maximum 2 cereri simultane** implicit, configurabil până la 32. **CONFIRMAT-COD (S1, S7).**
- `web.socket(url, headers, callback, {encoding='json', reconnect=true, onError, onClose})` — client WebSocket. Implementare prezentă în `lib_web.lua`; **nu am găsit nicio aplicație oficială care îl folosește** → **DOCUMENTAT**, de testat. Versiunea CSP minimă pentru `web.socket` nu este documentată în sursele găsite.
- Lua sockets (LuaSocket) este inclus, doar pentru scripturi cu I/O complet (S3). **DOCUMENTAT.**
- Identitate: aplicațiile oficiale folosesc `ac.uniqueMachineKeyAsync()` + `ac.checksumSHA256` pentru un ID stabil de mașină (S7). Pentru Steam ID există `steam.user.getSteamID()` în `lua-shared/utils/steam.lua`, dar este implementat prin `__util.native` (API intern, nedocumentat → **nu ne bazăm pe el**).
- Restricții: aplicațiile Lua instalate de utilizator au I/O complet; scripturile online (livrate de server) nu pot accesa fișiere în afara folderelor mașinii/traseului și nu pot lansa procese (S3, S9). Modulul `web` este încărcat de `ac_common` pentru toate tipurile de script, deci **probabil** este disponibil și în scripturile online — **PLAUZIBIL**, de confirmat în PoC.

### 4.5 Variantă B2 — script online livrat de server
- Configurat în opțiunile extra CSP ale serverului: `[SCRIPT_DRS] SCRIPT = 'https://drs…/starter.lua?t={SteamID}&s={SessionID}&v={CSPBuildID}'`, `REQUIRED = 1`. CSP substituie Steam ID-ul și slotul din entry list (S9).
- ACSM v2 are opțiunea „Enable Extra Custom Shaders Patch Options” și o secțiune CSP per eveniment (S18). **Nu am verificat** că ACSM 2.4.8 trece mai departe secțiuni `[SCRIPT_...]` arbitrare → **PLAUZIBIL**, PoC obligatoriu.
- Avantaj major: **pilotul nu instalează nimic** și toți piloții de pe server au aceeași versiune. Dezavantaje: fără fișiere locale (calibrarea vine de la server), comportament sub restricțiile `secure.lua`, depinde de ACSM.
- Parametrul `{SteamID}` din URL este trimis de client; nu este o dovadă criptografică.

### 4.6 Compatibilitate
- Necesită CSP. **Decis (3.11):** toți participanții folosesc o singură versiune CSP aprobată de organizator (ținta: 0.3.1, build 4302, de confirmat; vezi §0.1).
- Aplicațiile oficiale declară `REQUIRED_VERSION` între 2498 și 3442 (build-uri CSP). DRS Starter declară în manifest `REQUIRED_VERSION = 3442` (cel mai mare prag folosit de aplicațiile oficiale de la care am preluat API-urile, ca să nu blocăm încărcarea dacă numărul de build 4302 se dovedește greșit) și afișează în overlay un avertisment vizibil dacă `ac.getPatchVersionCode()` diferă de build-ul aprobat din `src/config.lua`. După confirmarea build-ului real, pragul din manifest se poate ridica la valoarea aprobată.

## 5. Opțiunea C — Hibrid (UI in-game + companion Windows)

| Motiv posibil pentru companion | Este necesar? |
|---|---|
| HTTPS / WebSocket | **Nu** — CSP Lua le are nativ (§4.4). Ar fi necesar doar pentru Python. |
| Stocare token în Windows Credential Manager | Util, dar un token de dispozitiv revocabil în `ac.storage` este suficient pentru riscul acestui caz. |
| Funcționare când jocul e închis | Nu are sens: alinierea se face în joc. |
| Comunicare cu Discord sau alte servicii | În afara scopului. |

Costuri: un executabil semnat (sau alerte SmartScreen/antivirus), installer, auto-start, comunicare locală (fișier mapat în memorie `ac.connect`/MMF sau socket localhost), încă un punct de defectare. **Concluzie: nejustificat.** Se reevaluează doar dacă PoC-ul arată că `web.request` este blocat de vreun antivirus sau proxy la piloți.

## 6. Race Control DRS V2 — ce există azi (verificat în cod, doar citire)

- `StartQueueItem` are statusurile `waiting, on_track, finished, delayed, dns, dnf, withdrawn` (planul S3 menționa și `on_deck`, dar nu este implementat).
- `StartQueueService::start()` este acționat de **operator**: verifică `startGate` (`max_on_track`, `min_start_interval_seconds`), setează `status = on_track` și `started_at = now()`, cu `lock_version` (optimistic locking) și audit. Fără timer automat („Nothing here changes status on a timer”).
- `routes/api.php` conține doar API-ul agentului Node (`agent/v1/poll`, `agent/v1/events`) cu `AuthenticateTimingAgent` (token + HMAC).
- Nu există: endpoint pentru pilot/aplicație, starea „chemat la start”, timestamp GO programat, comandă de anulare countdown, raport de aliniere, WebSocket/SSE (Race Control folosește polling la 2 s).
- Documentul de arhitectură (§20) a prevăzut deja `start_attempts`, `race_control_commands` (`begin_countdown`, `abort_countdown`, `ready_driver`) și `start_device_events` cu autentificare și protecție la replay, precum și „countdown sincronizat pe timestamp țintă, fallback manual obligatoriu”. Propunerea din ARCHITECTURE.md este aliniată cu aceste decizii.
- Agentul Node primește `CAR_INFO` (GUID ↔ slot) și ar putea primi `CAR_UPDATE` (poziție + viteză per mașină, setat prin `REALTIMEPOS_INTERVAL`), dezactivat implicit în S3. Acesta este singurul canal **independent de client** pentru a corobora poziția și oprirea mașinii. **DOCUMENTAT (protocolul Kunos), netestat pe ACSM 2.4.8.**

## 7. Alinierea la linia de start — fezabilitate și limite

### 7.1 Sistem de coordonate
- Coordonate lume în **metri**, axa Y verticală (confirmat indirect de TrackCoordinatesHelper: conversie cu 111320 m/grad pe X/Z; și de rally mode, care calculează distanța pe planul X/Z).
- Valorile sunt `float` (32 biți). La ±5 km de origine, rezoluția este de ~0,5 mm, deci precizia numerică nu este limitarea.

### 7.2 Puncte de referință disponibile
| Referință | Sursă | Observații |
|---|---|---|
| Centrul mașinii (`car.position`) | CONFIRMAT-COD | Nu corespunde axei față; distanța până la axa față diferă între mașini. |
| Bara față aproximată | `position + look * (aabbSize.z/2 - aabbCenter.z)` (S4) | Depinde de modelul 3D (AABB poate include eleroane și oglinzi). |
| Centrul roților față | `wheels[0/1].position` | Stabil; este punctul din modelul fizic. |
| Contactul anvelopă–sol față | `wheels[0/1].contactPoint` | Cel mai apropiat de „roțile pe linie”; se deplasează cu bracarea și compresia. |
| Orientare | `car.look` (vector unitar înainte) | Se proiectează pe planul orizontal. |

### 7.3 Calcul propus (detaliat în ARCHITECTURE.md)
Linia = punct `P0`, direcție de mers `f` (orizontală, unitară), lățime `W`. Punct de referință `F` = media contactelor roților față. Distanță cu semn `d = (F − P0) · f` (negativ = în spatele liniei), abatere laterală `l = (F − P0) · s`, unghi `θ = acos(look_h · f)`. Aliniat ⇔ `d` în fereastra configurată, `|l| ≤ W/2`, `θ ≤ θmax`, viteză < prag de cel puțin 1 s, cu histerezis. Este aceeași abordare ca CSP rally mode, cu referința mutată de pe bara față pe axa față.

### 7.4 Ce precizie putem afirma
- **Nu putem afirma încă precizie milimetrică sau centimetrică.** API-ul returnează valori cu rezoluție sub milimetru, dar asta nu înseamnă precizie fizică.
- Surse de eroare cunoscute: (a) punctul de contact se mută cu unghiul de bracare (câțiva cm, estimare nevalidată); (b) compresia suspensiei și înclinarea pantei la start pe hillclimb; (c) calibrarea liniei (eroarea operatorului care o capturează); (d) actualizare pe cadru grafic, nu pe pas fizic — irelevant pentru o mașină oprită; (e) pilotul nu poate opri la milimetru: controlul la viteză mică este limitarea practică.
- **Țintă propusă (de validat în D1):** repetabilitate a citirii < 1 cm pentru aceeași mașină oprită; toleranță sportivă **implicit ±10 cm** față de poziția țintă a axei față (zona verde de 20 cm), configurabilă per traseu/eveniment între ±3 și ±50 cm. Valoarea finală o decide organizatorul după testul cu piloți.
- Pentru piloții care nu au aplicația, poziția nu se poate verifica decât vizual sau, aproximativ, prin `CAR_UPDATE` (poziția centrului mașinii raportată de server, cu latență de rețea; precizie estimată de ordinul decimetrilor, de măsurat).

### 7.5 Calibrare, layouturi, trasee inverse
- Sursa 1 (automată): nodurile `AC_AB_START_L/R` ale traseului, dacă există, cu un offset longitudinal configurabil (start box în spatele liniei de cronometrare).
- Sursa 2 (manuală): instrument de calibrare în aplicație — organizatorul oprește mașina cu roțile față pe poziția dorită și apasă „Capturează”; aplicația salvează `P0`, `f`, lățimea, ID-ul traseului/layoutului, versiunea CSP, mașina folosită.
- Cheie de configurare: `trackID + layout + routeId`. Traseele inverse au `routeId` propriu și direcție `f` opusă; nu se deduce automat inversul unei configurații existente.
- Persistență: fișier JSON versionat și cu checksum, livrat cu aplicația și (în D2) descărcat din Laravel.

## 8. Sincronizare Race Control — fezabilitate

| Mecanism | Evaluare |
|---|---|
| **HTTPS polling** (`web.request`) | **Recomandat.** Confirmat în aplicații oficiale. Se potrivește cu arhitectura Laravel actuală (polling peste tot, fără infrastructură WebSocket). Cadență 1 s când pilotul e chemat, 5 s în rest. Respectă limita de 2 cereri simultane. |
| WebSocket (`web.socket`) | Disponibil în SDK, netestat; ar cere server WebSocket (Laravel Reverb sau similar) — infrastructură nouă. Amânat; nu este necesar pentru un countdown de 30 s. |
| Server-Sent Events | Nu există client SSE în CSP; WinHTTP nu expune streaming în API-ul Lua găsit. **NESUSȚINUT.** |
| Companion local | Nejustificat (§5). |
| Chat AC prin agentul Node (`sendMessage` UDP către mașină) | **PLAUZIBIL** ca fallback pentru piloții fără aplicație (mesaje „30 s / GO” în chat). Necesită modificări în Node (în afara acestei faze). |

**Countdown sincronizat:** Laravel stabilește `go_at` (ms, ceasul serverului). Clientul estimează offsetul ceasului prin schimburi tip NTP (`t0`, `server_now`, `t1`; se păstrează proba cu RTT minim) și convertește `go_at` în timp local monoton (`os.preciseClock`). Cu countdown de 30 s, chiar o comandă primită cu 2–3 s întârziere afișează GO la momentul corect. Precizie estimată: ±(RTT/2 + jitter), tipic sub 100–150 ms pe conexiuni europene — **estimare, de măsurat în D2**. Nu se folosește ceasul Windows al pilotului.

**Ce se poate automatiza fiabil:** chemarea următorului pilot din coadă; afișarea poziției în coadă; raportarea alinierii; programarea GO după confirmarea operatorului (sau automat, dacă organizatorul aprobă); afișarea countdown-ului; anularea; detecția locală a mișcării înainte de GO ca **dovadă** pentru comisari.
**Ce rămâne sub supravegherea organizatorului:** decizia de start (cel puțin în primele etape), validarea că pilotul e cu adevărat la start (aplicația poate minți), penalizările pentru start greșit, piloții fără aplicație, incidentele. **Timpul oficial rămâne exclusiv din sistemul de timing.**

## 9. Comparație arhitecturi

| Criteriu | A. Python | B. CSP Lua (app instalată) | B2. CSP Lua (script online) | C. Lua + companion |
|---|---|---|---|---|
| Precizie aliniere | Bună (contact roți) | Bună (contact roți + centru roți + AABB) | Ca B | Ca B |
| Coordonate lume | Da | Da | Da | Da |
| Roți / axă | Da (`TyreContactPoint`) | Da (`wheels[i].contactPoint/position`) | Da | Da |
| Noduri start din traseu | Nu | Da (`AC_AB_START_L/R`) | Da | Da |
| Calitate UI in-game | Slabă (gl 2D) | Foarte bună (ImGui, HUD, linie 3D în lume, sunet) | Foarte bună | Foarte bună |
| Rețea | Slabă (`_socket.pyd`, HTTPS vechi, fără WS) | HTTPS nativ, WS disponibil | Probabil ca B (PoC) | HTTPS oriunde |
| Complexitate integrare RC | Mare | Medie | Medie | Mare (2 procese) |
| Instalare | Copiere + `.pyd` | Arhivă în `apps/lua` (CM) | **Niciuna la pilot** | App + installer Windows |
| Dependență CSP | Parțială | Da | Da | Da |
| Compatibilitate | Toate instalările AC | Doar cu CSP (versiune minimă de stabilit) | CSP + ACSM trebuie să livreze scriptul | Ca B + Windows |
| Performanță | Risc la blocaje pe thread principal | Bună (asincron, `setInterval`) | Bună | Bună |
| Debugging | Slab | Bun (Lua Debug, definiții SDK, VS Code) | Mediu (fără fișiere locale) | Mediu |
| Mentenanță | Proastă (Python 3.3 EOL) | Bună; risc de schimbări API CSP | Bună, actualizare centralizată | Proastă (2 coduri) |
| Securitate | Token în fișier, TLS vechi | Token revocabil, TLS sistem | Fără token local; Steam ID din URL | Token în OS, proces extra |
| Efort | Mare | **Mic–mediu** | Mic (după B) | Mare |

## 10. Proiecte existente relevante

| Proiect | Capabilitate demonstrată | Încredere |
|---|---|---|
| CSP Rally Stage mode (S4) | Distanță cu semn la linia de start, mesaje înainte/înapoi, frână ținută, countdown, descalificare la mișcare | CONFIRMAT-COD (PoC al autorului CSP) |
| CSP CspDebug (S5) | Citire `contactPoint` și transform pe roată | CONFIRMAT-COD |
| CSP Setup Exchange / Notes Exchange (S7) | Comunicare HTTPS cu server extern, sesiune, ID unic de mașină | CONFIRMAT-COD |
| CSP TrackCoordinatesHelper (S8) | Lucru cu coordonate lume ↔ geo | CONFIRMAT-COD |
| CSP Le Mans start (S10) | Procedură de start în script online | CONFIRMAT-COD |
| Countdown Lua (S17) | Countdown local cu `sim.timeToSessionStart` | Exemplu de forum, single-player |
| SetupShare (S15) | Rețea din Python cu `_socket.pyd` livrat | Cod real, vechi (2018) |
| Aplicații de aliniere la start pentru hillclimb cu sincronizare server | **Nu am găsit** proiecte publice | — |
| Countdown-ul campionatului spaniol menționat de organizator | Mecanism necunoscut | NESUSȚINUT |

## 11. Ipoteze nesusținute (nu se proiectează pe ele)

- Că serverul AC/ACSM poate impune un start sau penaliza automat un start greșit pe baza aplicației.
- Că raportul de aliniere al clientului este o dovadă.
- Că ACSM 2.4.8 expune un API pentru countdown sau chat programatic (nu presupunem API-uri nedocumentate).
- Că toți piloții DRS au CSP într-o versiune recentă.
- Că `steam.user.getSteamID()` (intern) va rămâne disponibil.
- Că `web.socket` funcționează identic cu `web.request` în toate build-urile CSP.
