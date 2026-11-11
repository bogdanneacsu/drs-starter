# DRS Starter — Contract API v1 (Faza 2)

Data: 3 noiembrie 2026 · Implementare: `drs_v2` (Laravel 12), `app/Http/Controllers/Api/StarterController.php`, `app/Domain/Starter/*`
Client: `DRSStarter/src/live/client.lua`

JSON prin HTTPS (HTTP acceptat doar pentru `localhost`, `127.*`, `10.*`, `192.168.*`, pentru teste locale). Fără sesiune, fără CSRF. **Toate orele sunt milisecunde epoch ale serverului** (`*_ms`). Aplicația le convertește cu propriul offset de ceas și nu folosește niciodată ceasul Windows ca autoritate.

## 1. Autentificare

- `Authorization: Bearer drs_…` — token de dispozitiv emis o singură dată la împerechere. În baza de date se păstrează doar SHA-256 și ultimele 4 caractere (`token_hint`).
- Tokenul identifică **contul** (user → player → înscriere acceptată). Steam GUID nu este folosit ca dovadă.
- Refuz (`401 {"error":"unauthenticated"}`) dacă tokenul lipsește, e revocat, a expirat (implicit 120 de zile) sau contul nu mai este `active`. La 401 aplicația șterge tokenul și cere o nouă împerechere.
- Drepturi: pilotul nu are drepturi de procedură. `confirm-finish` cere permisiunea `confirm starter finish` (rolurile `safety_car` și `race_director`). `hold`/`resume` cer `confirm starter finish` sau `operate race control`.
- Limite: `pair` 10/min/IP, `pair/poll` 60/min/IP, restul 240/min/token (chei de throttle separate).

## 2. Împerechere (device flow)

| Pas | Cerere | Răspuns |
|---|---|---|
| 1 | `POST /api/starter/v1/pair` `{"device_name":"PC Bogdan"}` | `201 {"device_code":"<48>","user_code":"ABCD-EFGH","expires_in":600,"verify_url":"https://…/profilul-meu/drs-starter"}` |
| 2 | Pilotul, logat pe site, introduce `user_code` la `/profilul-meu/drs-starter` | codul e legat de contul lui (audit `starter.pairing.approved`) |
| 3 | `POST /api/starter/v1/pair/poll` `{"device_code":"…"}` la ~3 s | `{"status":"pending"}` … apoi o singură dată `{"status":"paired","token":"drs_…","device_id":7,"expires_at":"…"}`; apelurile următoare dau `consumed`; expirat → `expired`; necunoscut → `unknown` |

Revocare: din `/profilul-meu/drs-starter` (lista dispozitivelor, cu nume, ultima utilizare și ultimele 4 caractere ale tokenului). Codurile greșite se numără (maximum 5).

## 3. `POST /api/starter/v1/sync` — o cerere pe ciclu de polling

Cerere:
```json
{
  "mode": "driver | safety",
  "event_id": 3, "class_id": 5,
  "client": { "app_version": "0.2.0-phase2", "csp_build": 4302 },
  "status": { "seq": 812, "alignment": "ALIGNED", "aligned": true, "in_zone": true,
              "speed_kmh": 0.1, "d_m": -0.02, "track": "…", "mode": "driver" },
  "events": [ { "seq": 813, "type": "departure", "server_time_ms": 1793750400123,
                "slot_id": 41, "schedule_version": 2, "data": { "aligned": true, "speed_kmh": 4.2, "d_m": 1.6 } } ]
}
```
- `event_id`/`class_id` contează doar în modul `safety` (alegerea clasei; dacă e o singură clasă activă se alege automat). Pilotul este legat de înscrierea lui de către server.
- `status` = heartbeat. Se procesează doar dacă `seq` > ultimul `seq` primit de la acel dispozitiv (mesajele vechi sau reordonate se ignoră). Câmpurile sunt filtrate pe o listă albă și limitate.
- `events` (maximum 20): `departure`, `zone_left`. Idempotente pe `(dispozitiv, seq)`; un eveniment deja primit este confirmat din nou, fără efect. Aplicația păstrează evenimentele neconfirmate în `ac.storage` și le retrimite.
- `server_time_ms` din eveniment este ora serverului estimată de client. Se folosește doar dacă diferă cu cel mult 30 s de ora de primire; altfel se folosește ora de primire și se marchează `time_trusted:false`.

Răspuns (comun):
```json
{
  "schema": 1,
  "server_received_ms": 1793750400050,
  "identity": { "driver": "Nume afișat", "can_confirm_finish": false, "can_hold": false, "device": "PC Bogdan" },
  "acks": [813],
  "stale_after_ms": 4000,
  "mode": "driver",
  "context": { "event_id": 3, "event": "…", "class_id": 5, "class": "…", "run": 1, "phase": "run1" },
  "procedure": { "id": 9, "status": "running | hold | completed", "run": 1, "schedule_version": 2,
                 "confirmed_at_ms": 0, "interval_s": 50, "window_before_s": 10, "window_after_s": 10,
                 "hold": null },
  "poll_after_ms": 1000,
  "server_time_ms": 1793750400061
}
```
`server_received_ms` (t1) și `server_time_ms` (t2, scris ultimul) formează, împreună cu t0/t3 din client, proba de ceas NTP.

Partea pilotului (`mode=driver`) — `me`:
```json
{ "entry_id": 12, "race_number": 27, "queue_position": 4, "queue_status": "waiting",
  "attempts_used": 0, "max_attempts": 2, "retry": false, "ahead": 3, "code": "SCHEDULED",
  "slot": { "id": 41, "attempt": 1, "sequence": 4, "status": "scheduled",
            "scheduled_at_ms": 0, "window_opens_at_ms": 0, "window_closes_at_ms": 0,
            "authorized_now": false, "dns_pending": false, "resolution": null } }
```
Coduri `me.code`: `NO_CONTEXT`, `NOT_IN_RUN`, `WAITING_SAFETY_CAR`, `SCHEDULED`, `WINDOW_OPEN`, `MISSED_RETRY`, `DEPARTED`, `IN_REVIEW`, `DNS_PENDING`, `DNS`, `RACE_CONTROL`, `HOLD`, `CANCELLED`, `PROCEDURE_COMPLETED`.

`authorized_now` este doar informativ (valabil la `server_time_ms`). Aplicația decide singură, cu ora serverului estimată, și afișează GO **numai** dacă: ultima stare validă e mai nouă de `stale_after_ms`, procedura este `running`, slotul este `scheduled`, ora curentă e în fereastră și alinierea locală este `ALIGNED`. Altfel: countdown, HOLD sau CONEXIUNE PIERDUTĂ.

Partea Safety Car (`mode=safety`): `choices` (clase active), `context`, `procedure` + `counts` (pe status de slot), `can_confirm_now`, `blockers` (`run_not_active`, `starter_lead_not_configured`, `queue_empty`, `not_authorized`), `queue` (următorii 6: pilot, număr, slot).

## 4. Comenzi de procedură (Safety Car / Race Control)

| Endpoint | Corp | Efect |
|---|---|---|
| `POST /procedure/confirm-finish` | `event_id`, `class_id`, `run` (1/2), `request_id` | Creează procedura și programul. Idempotent: a doua confirmare întoarce aceeași procedură cu `already_confirmed:true` (unic pe etapă+clasă+manșă, cu blocare pe rând și audit `starter.finish.duplicate`). |
| `POST /procedure/hold` | `event_id`, `class_id`, `reason?` | HOLD: nicio fereastră nu mai autorizează plecarea; `schedule_version++`. |
| `POST /procedure/resume` | `event_id`, `class_id` | Reluare: sloturile rămase se mută la ≥ `max(acum + resume_lead, slotul anterior + interval)`; niciodată mai devreme decât erau. |

Erori `409 {"error": "...", "message": "...", "details": {...}}`: `context_not_active`, `run_mismatch`, `invalid_run`, `run_not_active`, `starter_lead_not_configured`, `queue_not_built`, `queue_empty`, `no_procedure`, plus erorile de stare ale procedurii. `403` fără permisiune. Aplicația consideră comanda reușită **doar la HTTP 200**.

## 5. Generarea programului

- `first = prima secundă întreagă ≥ confirmare + starter_lead_seconds` (setat per clasă în consola Race Control; fără valoare, confirmarea este refuzată: **nu există valoare implicită ascunsă**).
- `slot[i].scheduled = first + i × interval` (implicit 50 s), în ordinea oficială din `start_queue_items` (`waiting`).
- Fereastra `[scheduled − before, scheduled + after]` (implicit 10/10 s) → minimum 30 s între două plecări valide.
- Valorile sunt copiate în procedură la confirmare (schimbarea setărilor nu modifică o procedură în curs).

## 6. Evaluare, ratare, reîncercare, DNS

Evaluarea rulează la fiecare `sync`/consolă (maximum o dată pe secundă), după `închidere fereastră + 5 s`:

| Situație | Rezultat |
|---|---|
| Raport `departure` în fereastră sau operator a pornit pilotul în coadă | `departed`; coada trece pilotul `on_track` |
| Heartbeat-uri ≥ 50 % din fereastră, ultimul în ultimele 3 s, viteză ≤ 3 km/h, fără plecare | `missed` (`auto_confirmed_non_departure`) |
| Fără date client / client și server deconectați / date incomplete / mișcare fără raport | `review` (Race Control decide `departed` sau `missed`) |
| Prima ratare | slot `attempt=2` la primul loc liber după ultimul slot; pilotul mutat la coada cozii; mesaj „eliberează zona de start” |
| A doua ratare | DNS **doar** dacă directorul de cursă confirmă sau (setarea `auto_dns` activă **și** ratarea e confirmată automat de heartbeat-uri). Altfel `dns_pending` până la decizia directorului. Lipsa unui raport nu produce DNS. |
| HOLD | Ferestrele nu se evaluează ca ratări; la reluare se resetează dovezile de heartbeat |

Încercări maxime: 2 (unic pe `(queue_item, attempt)`). DNS se scrie prin `StartQueueService::setStatus('dns')` și ajunge în rezultate prin fluxul existent (o tură atribuită are prioritate față de DNS).

## 7. Incidente (fără penalizare)

Raportul `departure` este clasificat: `in_window`, `early`, `late`, `during_hold`, `no_authorization`, `after_resolution`, `duplicate_departure`, `outside_run`. Pentru `early`, `late`, `during_hold`, `no_authorization`, `after_resolution` și pentru plecarea nealiniată (`not_aligned`) se deschide un incident `open` legat de înscriere, unul per pilot/manșă/tip. Textul spune explicit că este un raport client, neverificat, **nu o penalizare automată** și nu modifică timpii. Timpii oficiali vin în continuare doar din agentul Node / ACSM.

## 8. Consola Race Control (web, sesiune, `operate race control`)

`GET /admin/race-control/events/{e}/classes/{c}/starter` (stare: setări, procedură, sloturi cu dovezi și `area_clear`), `POST …/starter/start` (`run`, `request_id`; cere `confirm starter finish`: pornește programul manșei curente din consolă, cu aceleași reguli și aceeași idempotență ca `confirm-finish`; folosit la Run 2, când Safety Car nu urcă între manșe), `POST …/starter/settings` (doar director: `lead_seconds` 10–1800, `resume_lead_seconds`, `auto_dns`, motiv obligatoriu), `POST …/starter/hold|resume`, `POST /admin/race-control/starter/slots/{s}/resolve` (`departed|missed` + motiv; a doua ratare cere directorul), `…/confirm-dns`, `…/dismiss-dns` (doar director). Toate sunt auditate.
