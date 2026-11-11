# DRS Starter — Faza 2: configurare, împerechere, test local, riscuri, checklist E2E

Data: 3 noiembrie 2026. Contractul API complet: `docs/API_CONTRACT.md`.

## 1. Ce este implementat, ce este testat

| Componentă | Implementat | Testat local (automat) | Testat în joc | Testat pe serverele reale (ACSM + Node) |
|---|---|---|---|---|
| Tabele, modele, migrație (`2026_11_18_000100_create_starter_sync_tables`) | da | da (sqlite) | — | **nu** |
| Împerechere cod + token revocabil, pagina `/profilul-meu/drs-starter` | da | da (PHP + integrare HTTP) | nu | nu |
| Confirmare Safety Car → program absolut 50 s / ±10 s, lead configurabil | da | da | nu | nu |
| Ratare → o reîncercare la coada cozii; a doua ratare → DNS doar cu dovezi / director | da | da | nu | nu |
| HOLD / reluare (decalare sigură) | da | da | nu | nu |
| Incidente plecare anticipată/întârziată/nealiniată/în HOLD/neautorizată (fără penalizare) | da | da | nu | nu |
| Panou „DRS Starter — start automat” în consola Race Control | da | parțial (endpointuri testate; interfața JS doar verificată manual în cod) | — | nu |
| Client CSP: sincronizare ceas, polling, GO doar cu date proaspete, retrimitere evenimente | da | da (LuaJIT, `web.request` simulat + integrare HTTP reală) | **nu** | nu |
| Safety Car în aplicație: confirmare în doi pași, HOLD, reluare | da | da (smoke + integrare) | **nu** | nu |
| Trimiterea forțată la boxe (teleport) | **nu** (nedovedit) | — | — | — |
| Plecarea detectată din timing-ul oficial (Node) | **nu** (agentul Node nu a fost modificat) | — | — | — |

Plecarea este acum stabilită din raportul aplicației sau din pornirea manuală de către operator în coadă; lipsa datelor duce la **revizuire**, nu la ratare sau DNS. Conectarea la ACSM (`RawTimingEvent`) este înregistrată ca dovadă suplimentară, nu ca decizie.

## 2. Configurare server (Laravel)

Nu am instalat nimic în producție. Pași pentru un mediu de test sau, ulterior, producție:

1. Copiază fișierele (lista în §7). Rulează `php artisan migrate`.
2. `php artisan db:seed --class=ReferenceDataSeeder` — adaugă permisiunea `confirm starter finish` (acordată `race_director`) și rolul `safety_car`. Seeder-ul este idempotent.
3. Acordă rolul `safety_car` contului pilotului Safety Car (din administrarea utilizatorilor existentă). Rolul nu are alte drepturi.
4. În consola Race Control, pe clasa respectivă, directorul setează **timpul de pregătire** (`lead`, 10–1800 s) și, opțional, timpul de reluare după HOLD și `auto_dns`. Fără `lead`, confirmarea Safety Car este refuzată.
5. Variabile `.env` opționale (au valori implicite sigure):

| Variabilă | Implicit | Sens |
|---|---|---|
| `STARTER_PAIRING_TTL_SECONDS` | 600 | valabilitatea codului de împerechere |
| `STARTER_TOKEN_TTL_DAYS` | 120 | expirarea tokenului de dispozitiv |
| `STARTER_POLL_IDLE_MS` / `STARTER_POLL_ACTIVE_MS` | 5000 / 1000 | ritmul de polling comunicat aplicației |
| `STARTER_STALE_AFTER_MS` | 4000 | după cât timp fără răspuns aplicația arată CONEXIUNE PIERDUTĂ |
| `STARTER_REPORT_GRACE_SECONDS` | 5 | întârzierea evaluării după închiderea ferestrei |

6. Serverul trebuie să fie pe **HTTPS**. Aplicația refuză `http://` pentru adrese publice.

Intervalul (50 s) și fereastra (±10 s) sunt coloane per clasă (`starter_interval_seconds`, `starter_window_*`), cu valorile confirmate ca implicite. Nu le-am expus în consolă, ca să nu fie schimbate accidental.

## 2b. Procedura între manșe (decizie organizator, 11 noiembrie 2026)

Safety Car coboară **doar după Run 2**. Între manșe piloții dau „back to pits” și pornesc Run 2. Programul Run 1 îl pornește Safety Car la sosirea la finish (DRS Organizer). Programul Run 2 îl pornește organizatorul din consola Race Control, cu butonul „Pornește programul de start (manșa 2)”. Ambele folosesc aceleași reguli (interval, ferestre, timp de pregătire) și nu pot crea două programe pentru aceeași manșă.

## 3. Împerechere (pilot și Safety Car)

1. În joc: DRS Starter → Setări → „Conectare Race Control”. Adresa serverului (de ex. `https://drs.example`) → **Împerechează**.
2. Aplicația afișează un cod `ABCD-EFGH` și adresa paginii.
3. Pe site, logat cu contul propriu: **Profilul meu → DRS Starter** → introduci codul → Aprobă.
4. În câteva secunde aplicația arată „Conectat” și numele pilotului. Tokenul rămâne salvat în `ac.storage`.
5. Revocare: aceeași pagină, butonul de lângă dispozitiv. Aplicația revine la starea „neîmperecheat”.
6. Pentru Safety Car se folosește contul care are rolul `safety_car`. Modul Safety Car arată butoanele doar dacă serverul confirmă dreptul (`can_confirm_finish`).

Modul demo local (Faza 1) rămâne disponibil: Setări → „Conectare Race Control” → „Demo local (fără rețea)”. „LIVE (Race Control)” activează sincronizarea.

## 4. Testul de integrare local (fără AC, fără ACSM)

Cerințe: `php` 8.2 cu extensia sqlite, `composer install` făcut în copia `drs_v2`, `luajit`, `curl`.

```bash
cd drs_start_app
tools/integration/run.sh /cale/catre/o/copie/drs_v2
```

Scriptul creează `database/starter_integration.sqlite` (refuză altă bază decât sqlite), pornește `php artisan serve` pe portul 8765, pregătește o etapă de test cu doi piloți și un Safety Car, cu timpi scurtați (lead 12 s, interval 16 s, fereastră 4/4 s), apoi rulează modulele reale ale clientului Lua (`client.lua`, `time_sync.lua`, `live_model.lua`) contra serverului. **Nu-l rula pe copia de producție.** Șterge apoi `database/starter_integration.sqlite`.

Testele automate:
```bash
cd drs_v2 && php artisan test                      # toată suita
cd drs_v2 && php artisan test tests/Feature/Starter # doar DRS Starter (19 teste)
cd drs_start_app && luajit tests/run.lua && luajit tests/live_run.lua && luajit tests/smoke_mock_csp.lua
```

## 5. Riscuri rămase

1. **Plecarea nu vine încă din timing-ul oficial.** Un pilot fără aplicație sau cu aplicația oprită ajunge în „În analiză”; operatorul îl rezolvă din consolă (sau îl pornește din coadă ca până acum). Integrarea cu agentul Node rămâne pentru o sesiune separată.
2. **Clientul nu este o sursă de încredere.** Un client modificat poate raporta date false. Rapoartele produc doar stări operaționale și incidente de verificat cu replay-ul, nu timpi, rezultate sau penalizări. DNS automat este dezactivat implicit.
3. **Trimiterea la boxe nu poate fi impusă.** Fallback: mesaj în aplicație, „zona liberă” afișată în consolă doar dacă aplicația o raportează, verificare vizuală și kick manual din ACSM.
4. **Rețea:** latență sau jitter mare la unii piloți. Măsuri: probe NTP cu RTT minim, probe cu RTT > 2 s respinse, CONEXIUNE PIERDUTĂ după 4 s. Abaterea reală între PC-uri nu este măsurată.
5. **Încărcare server:** ~1 cerere/s per pilot în apropierea ferestrei, 0,2/s altfel. Netestat la 30+ piloți.
6. **API CSP real:** `web.request` și restul API-urilor sunt verificate în SDK, dar nu au rulat pe CSP 0.3.1 / build 4302. Build-ul aprobat nu este încă confirmat de organizator.
7. **Fișiere comune `drs_v2`:** rutele, seeder-ul și două view-uri au primit doar adăugări. La integrarea cu ramura altor lucrări se verifică conflictele.

## 6. Checklist pentru testul complet viitor (multi-server, ACSM + Node)

1. Mediu de test (nu producție): `migrate`, `db:seed --class=ReferenceDataSeeder`, HTTPS valid, `php artisan test` verde.
2. Rol `safety_car` acordat; `lead` setat în consolă pentru clasă; coada manșei construită.
3. 3+ PC-uri cu CSP-ul aprobat, din rețele diferite; aplicația 0.2.0 instalată; toți împerecheați; în Setări → debug offset-ul de ceas și incertitudinea (< 100 ms).
4. Safety Car confirmă (doi pași) → toți piloții primesc ora; consola arată aceeași ordine ca `start_queue_items`.
5. Măsoară abaterea afișării „fereastră deschisă” între PC-uri (filmare cu ceas comun). Țintă ≤ 250 ms.
6. Pilot 1: aliniat, pleacă în fereastră → DEPARTED, coada `on_track`, timpul oficial vine din Node normal.
7. Pilot 2: nu pleacă, rămâne conectat → ratare confirmată → mesaj „eliberează zona” → a doua oră la coada cozii; după ieșirea din zonă consola arată „raportat de client”.
8. Pilot 2 ratează și a doua oară → `DNS în așteptare` (cu `auto_dns` oprit) → directorul confirmă DNS → rezultatele arată DNS doar la acea manșă.
9. Pilot 3: pleacă cu 3 s înainte de fereastră → incident „plecare anticipată”, fără penalizare, timpii neatinși.
10. Pilot 3 închide aplicația înainte de fereastră → „În analiză” la Race Control, nu ratare.
11. Deconectează rețeaua unui pilot în fereastră → aplicația arată CONEXIUNE PIERDUTĂ în ≤ 4 s, fără GO.
12. HOLD din aplicația Safety Car → toți văd HOLD în ≤ 2 s; nimeni nu e marcat ratat; reluare → orele se decalează, niciodată mai devreme.
13. Dublu clic / două confirmări simultane → o singură procedură (audit `starter.finish.duplicate`).
14. Revocă dispozitivul unui pilot → aplicația cere o nouă împerechere.
15. Manșa 2: confirmare nouă, fără efect asupra manșei 1.
16. Verifică `audit_logs` și că nicio dată personală (e-mail, GUID) nu apare în răspunsurile API.

## 7. Fișiere livrate în `drs_v2` (fără commit)

Noi: `config/starter.php`; `database/migrations/2026_11_18_000100_create_starter_sync_tables.php`; `app/Models/Starter{Device,Pairing,Procedure,Slot,Report}.php`; `app/Domain/Starter/{StarterPairingService,StarterProcedureService,StarterReportService,StarterStateService,StarterContextService,SystemActor}.php`; `app/Http/Middleware/AuthenticateStarterDevice.php`; `app/Http/Controllers/Api/StarterController.php`; `app/Http/Controllers/Admin/StarterController.php`; `app/Http/Controllers/AccountStarterController.php`; `resources/views/account/starter.blade.php`; `public/cuba/js/drs-starter-console.js`; `tests/Feature/Starter/StarterSyncTest.php`.

Modificate (doar adăugări): `routes/api.php`, `routes/web.php`, `database/seeders/ReferenceDataSeeder.php`, `resources/views/admin/race-control/console.blade.php`, `resources/views/account/show.blade.php`.
