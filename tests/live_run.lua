-- Teste automate pentru modulele LIVE (Faza 2): sincronizare ceas, model de afișare, detecție plecare,
-- client HTTP cu server simulat. Rulare: luajit tests/live_run.lua (din folderul proiectului).
-- Nu folosesc API-ul CSP și nu dovedesc comportamentul în joc.
package.path = './DRSStarter/?.lua;./tests/?.lua;' .. package.path

local TimeSync = require('src/live/time_sync')
local Model = require('src/live/live_model')
local Departure = require('src/live/departure')
local Client = require('src/live/client')
local JSONT = require('support/json')

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; print('  ok   ' .. name)
  else failed = failed + 1; print('  FAIL ' .. name .. '\n       ' .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or '') .. ' expected ' .. tostring(b) .. ', got ' .. tostring(a), 2) end end
local function near(a, b, eps, msg) if math.abs(a - b) > (eps or 1e-6) then error((msg or '') .. ' expected ~' .. b .. ', got ' .. a, 2) end end
local function truthy(v, msg) if not v then error(msg or 'expected truthy', 2) end end

local SERVER0 = 1795000000000 -- ms epoch de referință

-- ───────────────────────── Ceas ─────────────────────────
print('Sincronizare ceas')
test('offset corect cu latență simetrică', function()
  local s = TimeSync.new()
  -- ceas local 100 s ↔ server SERVER0; RTT 200 ms, procesare 10 ms
  truthy(s:add(100.000, SERVER0 + 95, SERVER0 + 105, 100.200))
  near(s:serverNowMs(100.200), SERVER0 + 200, 1)
  near(s:uncertaintyMs(), 95, 0.01)
end)
test('alege eșantionul cu întârzierea minimă (latență asimetrică / răspuns întârziat)', function()
  local s = TimeSync.new()
  s:add(100, SERVER0 + 900, SERVER0 + 910, 101.0)   -- răspuns lent (RTT 1 s, asimetric)
  s:add(102, SERVER0 + 2020, SERVER0 + 2030, 102.05) -- rapid
  near(s:serverNowMs(103), SERVER0 + 3000, 5)
end)
test('eșantioane absurde respinse (RTT > 2 s, timp invers, tipuri greșite)', function()
  local s = TimeSync.new()
  eq(s:add(100, SERVER0, SERVER0, 103), false)
  eq(s:add(100, SERVER0 + 10, SERVER0, 100.1), false)
  eq(s:add(100, 'x', SERVER0, 100.1), false)
  eq(s:ready(), false)
end)
test('drift: eșantioanele vechi expiră și estimarea urmează ceasul nou', function()
  local s = TimeSync.new()
  s:add(100, SERVER0 + 50, SERVER0 + 50, 100.1)
  -- 70 s mai târziu serverul e cu 300 ms „înainte” (drift de ceas)
  s:add(170, SERVER0 + 70000 + 350, SERVER0 + 70000 + 350, 170.1)
  near(s:serverNowMs(170.1), SERVER0 + 70000 + 400, 2)
end)

-- ───────────────────────── Model de afișare ─────────────────────────
print('Model LIVE')
local function syncAt(serverAtMono100)
  local s = TimeSync.new(); s:add(100, serverAtMono100, serverAtMono100, 100); return s
end
local function state(code, slot, proc, extra)
  local st = { schema = 1, server_time_ms = SERVER0, server_received_ms = SERVER0, stale_after_ms = 4000,
    procedure = proc == nil and { status = 'running', schedule_version = 1 } or proc, me = { code = code, slot = slot } }
  for k, v in pairs(extra or {}) do st[k] = v end
  return Model.validateState(st)
end
local slot = { id = 7, status = 'scheduled', scheduled_at_ms = SERVER0 + 30000, window_opens_at_ms = SERVER0 + 20000, window_closes_at_ms = SERVER0 + 40000 }
local function drive(code, t, opts)
  opts = opts or {}
  return Model.driver({ paired = true, state = state(code, opts.slot or slot, opts.proc), stateAt = opts.stateAt or t, now = t,
    sync = syncAt(SERVER0), aligned = opts.aligned })
end
test('countdown până la deschiderea ferestrei, din ora serverului', function()
  local m = drive('SCHEDULED', 105)
  eq(m.phase, 'SCHEDULED'); eq(m.countdownS, 15); eq(m.toStartS, 25); eq(m.authorized, false); eq(m.go, false)
end)
test('fereastră deschisă: autorizat; GO doar cu aliniere', function()
  local m = drive('SCHEDULED', 121) -- starea veche spunea SCHEDULED; ceasul spune deschis
  eq(m.phase, 'WINDOW_OPEN'); eq(m.authorized, true); eq(m.go, false); eq(m.countdownS, 19)
  local g = drive('WINDOW_OPEN', 121, { aligned = true })
  eq(g.go, true)
end)
test('după închidere: fără autorizare, clientul nu prelungește fereastra', function()
  local m = drive('WINDOW_OPEN', 141, { aligned = true })
  eq(m.phase, 'WINDOW_CLOSED'); eq(m.authorized, false); eq(m.go, false)
end)
test('stare veche (> stale_after_ms) → CONEXIUNE PIERDUTĂ, niciodată GO', function()
  local m = drive('WINDOW_OPEN', 125, { aligned = true, stateAt = 120.9 })
  eq(m.phase, 'STALE'); eq(m.go, false); eq(m.authorized, false); eq(m.connection, 'CONEXIUNE PIERDUTĂ')
end)
test('HOLD de la server → fără autorizare chiar în fereastră', function()
  local m = drive('WINDOW_OPEN', 125, { aligned = true, proc = { status = 'hold', schedule_version = 2 } })
  eq(m.phase, 'HOLD'); eq(m.go, false)
end)
test('fără sincronizare de ceas → tratat ca neautorizat', function()
  local m = Model.driver({ paired = true, state = state('WINDOW_OPEN', slot), stateAt = 125, now = 125, sync = TimeSync.new(), aligned = true })
  eq(m.phase, 'STALE'); eq(m.go, false)
end)
test('a doua șansă: countdown spre noua fereastră + instrucțiune de eliberare a zonei', function()
  local m = drive('MISSED_RETRY', 105)
  eq(m.phase, 'MISSED_RETRY'); eq(m.countdownS, 15)
  local t = Model.text('MISSED_RETRY'); truthy(t:find('RATAT'))
end)
test('stări retry/DNS/analiză afișate din codul serverului', function()
  for _, c in ipairs({ 'DNS', 'DNS_PENDING', 'IN_REVIEW', 'DEPARTED', 'WAITING_SAFETY_CAR', 'NO_CONTEXT' }) do
    local m = drive(c, 105, { slot = { id = 1, status = 'missed', scheduled_at_ms = SERVER0, window_opens_at_ms = SERVER0 - 10000, window_closes_at_ms = SERVER0 + 10000 } })
    eq(m.phase, c); eq(m.go, false)
  end
end)
test('răspunsuri malformate respinse fără excepții', function()
  eq(Model.validateState(nil), nil)
  eq(Model.validateState('x'), nil)
  eq(Model.validateState({ schema = 2, server_time_ms = 1, server_received_ms = 1 }), nil)
  eq(Model.validateState({ schema = 1 }), nil)
  local st = Model.validateState({ schema = 1, server_time_ms = 1, server_received_ms = 1, me = { code = 'SCHEDULED', slot = { status = 'scheduled', window_opens_at_ms = 10, window_closes_at_ms = 5, scheduled_at_ms = 7 } } })
  eq(st.me.slot, nil, 'fereastră inversată → slot eliminat')
  local m = Model.driver({ paired = true, state = st, stateAt = 100, now = 100, sync = syncAt(SERVER0) })
  eq(m.authorized, false)
end)
test('neîmperecheat / fără stare', function()
  eq(Model.driver({ paired = false, now = 1 }).phase, 'UNPAIRED')
  eq(Model.driver({ paired = true, now = 1, sync = TimeSync.new() }).phase, 'CONNECTING')
  eq(Model.driver({ paired = true, now = 1, sync = TimeSync.new(), error = 'x' }).phase, 'OFFLINE')
end)

-- ───────────────────────── Detecție plecare ─────────────────────────
print('Detecție plecare')
local ALIGNED = 'ALIGNED'
local function r(d, st) return { state = st or 'STABILIZING', measure = { d = d, lateral = 0 } } end
test('plecare după aliniere: un singur raport, aliniat = true', function()
  local det = Departure.new()
  eq(det:update(r(0, ALIGNED), 0, 10, ALIGNED), nil)
  eq(det:update(r(0.4, 'TOO_FAR_FORWARD'), 6, 10.8, ALIGNED), nil)
  local e = det:update(r(1.6, 'FAR'), 12, 11.2, ALIGNED)
  eq(e.type, 'departure'); eq(e.aligned, true)
  eq(det:update(r(5, 'FAR'), 30, 12, ALIGNED), nil, 'nu se repetă')
end)
test('plecare fără aliniere recentă → aliniat = false', function()
  local det = Departure.new()
  det:update(r(-2, 'TOO_FAR_BACK'), 0, 10, ALIGNED)
  local e = det:update(r(1.7, 'FAR'), 10, 14, ALIGNED)
  eq(e.type, 'departure'); eq(e.aligned, false)
end)
test('ieșire din zonă înapoi / teleport la boxe → zone_left', function()
  local det = Departure.new()
  det:update(r(0, ALIGNED), 0, 10, ALIGNED)
  eq(det:update(r(-6, 'FAR'), 3, 12, ALIGNED).type, 'zone_left')
  local det2 = Departure.new()
  det2:update(r(0, ALIGNED), 0, 10, ALIGNED)
  eq(det2:update({ state = 'NO_CAR' }, 0, 11, ALIGNED).type, 'zone_left')
end)
test('fără a sta în zonă nu se raportează plecare (trecere în viteză)', function()
  local det = Departure.new()
  eq(det:update(r(-20, 'FAR'), 80, 10, ALIGNED), nil)
  eq(det:update(r(2, 'FAR'), 80, 10.5, ALIGNED), nil)
end)

-- ───────────────────────── Client cu server simulat ─────────────────────────
print('Client Race Control (server simulat)')
local function fakeEnv()
  local env = { t = 100, store = { serverUrl = 'https://drs.example', token = '', mode = 'driver', eventSeq = 0, statusSeq = 0, pendingEvents = '' }, requests = {}, queue = {} }
  env.http = function (method, url, headers, body, cb) table.insert(env.requests, { url = url, headers = headers, body = body, cb = cb }) end
  env.client = Client.new({ storage = env.store, http = env.http, now = function () return env.t end, json = JSONT, appVersion = 'test', cspBuild = 4302 })
  function env.respond(code, tbl, err)
    local rq = table.remove(env.requests, 1)
    rq.cb(err, code, tbl and JSONT.stringify(tbl) or nil)
    return rq
  end
  return env
end
local function okState(extra)
  local s = { schema = 1, server_received_ms = SERVER0, server_time_ms = SERVER0 + 2, stale_after_ms = 4000, poll_after_ms = 1000, acks = {}, me = { code = 'WAITING_SAFETY_CAR' } }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end
test('URL: doar https (http numai local)', function()
  eq(Client.validBaseUrl('https://x.ro/'), 'https://x.ro')
  eq(Client.validBaseUrl('http://x.ro'), nil)
  eq(Client.validBaseUrl('http://127.0.0.1:8000'), 'http://127.0.0.1:8000')
  eq(Client.validBaseUrl('ftp://x'), nil)
end)
test('împerechere: cod → token salvat, fără token în cereri publice', function()
  local e = fakeEnv()
  e.client:startPairing('Rig')
  local rq = e.respond(201, { device_code = string.rep('d', 48), user_code = 'ABCD-EFGH', expires_in = 600 })
  eq(rq.headers.Authorization, nil)
  eq(e.client.pairing.userCode, 'ABCD-EFGH')
  e.t = 104; e.client:update()
  e.respond(200, { status = 'pending' })
  e.t = 108; e.client:update()
  e.respond(200, { status = 'paired', token = 'drs_' .. string.rep('x', 56) })
  truthy(e.client:paired()); eq(e.client.pairing, nil)
end)
test('sincronizare: o cerere în zbor, Bearer, offset ceas, poll_after', function()
  local e = fakeEnv(); e.store.token = 'drs_' .. string.rep('t', 56)
  e.client:update(); e.client:update()
  eq(#e.requests, 1, 'o singură cerere simultană')
  eq(e.requests[1].headers.Authorization, 'Bearer ' .. e.store.token)
  e.t = 100.1
  e.respond(200, okState())
  truthy(e.client.timeSync:ready())
  near(e.client.timeSync:serverNowMs(100.1), SERVER0 + 51, 1)
  near(e.client.nextPollAt, 101.1, 0.001)
end)
test('evenimente: retrimise până la confirmare, secvențe monotone și persistente', function()
  local e = fakeEnv(); e.store.token = 'drs_' .. string.rep('t', 56)
  e.client:update(); e.t = 100.05; e.respond(200, okState())
  local ev = e.client:queueEvent('departure', { aligned = true }, { id = 7 }, 3)
  truthy(ev.server_time_ms, 'ora serverului estimată')
  e.client:update()
  local body = JSONT.parse(e.requests[1].body)
  eq(body.events[1].seq, ev.seq); eq(body.events[1].slot_id, 7)
  e.respond(0, nil, 'timeout') -- răspuns pierdut
  eq(#e.client.pending, 1, 'păstrat după eșec')
  truthy(e.store.pendingEvents ~= '', 'persistat pentru reîncărcare')
  e.t = 102; e.client:update()
  e.respond(200, okState({ acks = { ev.seq } }))
  eq(#e.client.pending, 0); eq(e.store.pendingEvents, '')
  -- Reîncărcare: secvențele continuă peste valorile rezervate.
  local c2 = Client.new({ storage = e.store, http = e.http, now = function () return e.t end, json = JSONT, appVersion = 't', cspBuild = 1 })
  truthy(c2:_nextSeq('eventSeq') > ev.seq)
end)
test('401 → token șters, mesaj de reîmperechere; rețea → backoff', function()
  local e = fakeEnv(); e.store.token = 'drs_' .. string.rep('t', 56)
  e.client:update(); e.respond(0, nil, 'no route')
  eq(e.client.failures, 1); near(e.client.nextPollAt, 101, 0.001)
  e.t = 101; e.client:update(); e.respond(0, nil, 'no route')
  near(e.client.nextPollAt, 103, 0.001)
  e.t = 103; e.client:update(); e.respond(401, { error = 'unauthenticated' })
  eq(e.client:paired(), false); truthy(e.client.lastError:find('revocat'))
end)
test('răspuns malformat: starea anterioară păstrată, devine STALE în timp', function()
  local e = fakeEnv(); e.store.token = 'drs_' .. string.rep('t', 56)
  e.client:update(); e.respond(200, okState({ me = { code = 'SCHEDULED', slot = slot } }))
  e.t = 101; e.client:update()
  local rq = table.remove(e.requests, 1); rq.cb(nil, 200, '{"schema":1,')
  eq(e.client.state.me.code, 'SCHEDULED')
  truthy(e.client.lastError:find('invalid'))
  local m = Model.driver({ paired = true, state = e.client.state, stateAt = e.client.stateAt, now = 105, sync = e.client.timeSync })
  eq(m.phase, 'STALE')
end)
test('acțiune Safety Car: succes doar la 200 de la server', function()
  local e = fakeEnv(); e.store.token = 'drs_' .. string.rep('t', 56); e.store.mode = 'safety'
  local got
  truthy(e.client:action('confirm', { event_id = 1, class_id = 2, run = 1 }, function (ok) got = ok end))
  eq(e.client:action('hold', {}), false, 'o singură acțiune în zbor')
  e.respond(0, nil, 'timeout')
  eq(got, false); truthy(e.client.feedback.text:find('NU a fost'))
  e.client:action('confirm', { event_id = 1, class_id = 2, run = 1 }, function (ok) got = ok end)
  e.respond(403, { message = 'Contul nu are rolul Safety Car / director de cursă.' })
  eq(got, false); truthy(e.client.feedback.text:find('rolul'))
  e.client:action('confirm', { event_id = 1, class_id = 2, run = 1 }, function (ok) got = ok end)
  e.respond(200, { created = true, procedure = { status = 'running' } })
  eq(got, true)
end)

test('cerere fără callback: abandonată după 15 s, răspunsul întârziat ignorat', function()
  local e = fakeEnv(); e.store.token = 'drs_' .. string.rep('t', 56)
  e.client:update()
  local stuck = table.remove(e.requests, 1)
  e.t = 116; e.client:update()
  eq(#e.requests, 0, 'backoff după timeout')
  e.t = 118; e.client:update()
  eq(#e.requests, 1, 'cerere nouă')
  stuck.cb(nil, 200, JSONT.stringify(okState({ me = { code = 'DNS' } })))
  eq(e.client.state, nil, 'răspunsul vechi nu schimbă starea')
  e.respond(200, okState())
  eq(e.client.state.me.code, 'WAITING_SAFETY_CAR')
end)

print(string.format('\n%d trecute, %d eșuate', passed, failed))
os.exit(failed == 0 and 0 or 1)
