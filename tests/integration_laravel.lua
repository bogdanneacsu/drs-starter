-- Test de integrare LOCAL: modulele reale ale aplicației (client, sincronizare ceas, model LIVE)
-- contra Laravel real (php artisan serve + bază sqlite de dezvoltare). HTTP prin curl, sincron.
-- Pornit de tools/integration/run.sh. NU este un test în joc și nu atinge servere ACSM / producție.
package.path = './DRSStarter/?.lua;./tests/?.lua;' .. package.path
local ffi = require('ffi')
ffi.cdef [[
  typedef struct { long tv_sec; long tv_nsec; } ts_t;
  int clock_gettime(int clk, ts_t *tp);
  int usleep(unsigned int usec);
]]
local function mono() local t = ffi.new('ts_t'); ffi.C.clock_gettime(1, t); return tonumber(t.tv_sec) + tonumber(t.tv_nsec) / 1e9 end
local function sleep(s) ffi.C.usleep(math.floor(s * 1e6)) end

local JSONT = require('support/json')
local Client = require('src/live/client')
local Model = require('src/live/live_model')

local BASE, ROOT = os.getenv('BASE'), os.getenv('LARAVEL_ROOT')
local seed = JSONT.parse(os.getenv('SEED'))

local function sh(cmd) local p = io.popen(cmd); local out = p:read('*a'); p:close(); return out end
local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

-- HTTP sincron prin curl (în joc: web.request asincron din CSP).
local function curlHttp(method, url, headers, body, cb)
  local args = { 'curl -s -m 10 -X ' .. method, '-w', q('\n%{http_code}') }
  for k, v in pairs(headers or {}) do args[#args + 1] = '-H ' .. q(k .. ': ' .. v) end
  if body then args[#args + 1] = '--data-binary ' .. q(body) end
  args[#args + 1] = q(url)
  local out = sh(table.concat(args, ' '))
  local resp, code = out:match('^(.*)\n(%d+)$')
  if not code then cb('curl failed', 0, nil) else cb(nil, tonumber(code), resp) end
end

local failures = 0
local function check(cond, msg) print((cond and '  ok   ' or '  FAIL ') .. msg); if not cond then failures = failures + 1 end end

local function newClient(mode)
  local store = { serverUrl = BASE, token = '', mode = mode, eventSeq = 0, statusSeq = 0, pendingEvents = '', scEventId = seed.event_id, scClassId = seed.class_id }
  local c = Client.new({ storage = store, http = curlHttp, now = mono, json = JSONT, appVersion = 'integration', cspBuild = 4302 })
  return c, store
end

local function pair(c, email)
  c:startPairing('integration ' .. email)
  assert(c.pairing and c.pairing.userCode, 'pairing did not start: ' .. tostring(c.feedback and c.feedback.text))
  sh('php tools/integration/laravel.php ' .. q(ROOT) .. ' approve ' .. q(c.pairing.userCode) .. ' ' .. q(email))
  c.pairing.nextAt = 0
  c:update()
  return c:paired()
end

local function poll(c, status)
  c.statusProvider = function () return status or { alignment = 'ALIGNED', aligned = true, speed_kmh = 0, in_zone = true } end
  c.nextPollAt = 0
  c:update()
  return c.state
end

print('Integrare Laravel ↔ client DRS Starter (local, ' .. BASE .. ')')
local sc = newClient('safety')
local a = newClient('driver')
local b = newClient('driver')
local intruder = newClient('driver')
check(pair(sc, 'sc@int.test'), 'Safety Car împerecheat prin cod (device flow)')
check(pair(a, 'pilot-a@int.test'), 'Pilot A împerecheat')
check(pair(b, 'pilot-b@int.test'), 'Pilot B împerecheat')
check(pair(intruder, 'pilot-a@int.test'), 'al doilea dispozitiv al pilotului A')

local s = poll(a)
check(s and s.me.code == 'WAITING_SAFETY_CAR', 'pilot: așteaptă Safety Car (' .. tostring(s and s.me.code) .. ')')
check(a.timeSync:ready() and math.abs(a.timeSync.offsetMs) > 0, string.format('offset ceas estimat (±%.0f ms)', a.timeSync:uncertaintyMs() or -1))

-- Un pilot nu poate confirma sosirea.
local denied
intruder.storage.mode = 'safety'
intruder:action('confirm', { event_id = seed.event_id, class_id = seed.class_id, run = 1 }, function (ok) denied = not ok end)
check(denied, 'confirmarea cu tokenul unui pilot este refuzată (403)')

local st = poll(sc)
check(st and st.can_confirm_now == true, 'Safety Car: confirmarea este permisă')
local created
sc:action('confirm', { event_id = seed.event_id, class_id = seed.class_id, run = 1, request_id = 'int-1' }, function (ok, r) created = ok and r.created end)
check(created == true, 'Safety Car: sosire confirmată, program generat de server')
local dup
sc:action('confirm', { event_id = seed.event_id, class_id = seed.class_id, run = 1, request_id = 'int-2' }, function (ok, r) dup = ok and r.already_confirmed end)
check(dup == true, 'a doua confirmare este idempotentă')

s = poll(a)
local slotA = s.me.slot
check(slotA and slotA.attempt == 1 and s.me.code == 'SCHEDULED', 'pilot A: oră de start primită')
local m = Model.driver({ paired = true, state = a.state, stateAt = a.stateAt, now = mono(), sync = a.timeSync, aligned = true })
check(m.phase == 'SCHEDULED' and m.countdownS and m.countdownS > 0 and not m.go, 'model: countdown spre fereastră, fără GO (' .. tostring(m.countdownS) .. ' s)')

-- Așteaptă deschiderea ferestrei A pe ceasul serverului estimat local.
while a.timeSync:serverNowMs(mono()) < slotA.window_opens_at_ms + 300 do poll(b); poll(a); sleep(0.5) end
poll(a)
m = Model.driver({ paired = true, state = a.state, stateAt = a.stateAt, now = mono(), sync = a.timeSync, aligned = true })
check(m.phase == 'WINDOW_OPEN' and m.go, 'fereastră deschisă + aliniat → GO (din ora serverului)')
local mNo = Model.driver({ paired = true, state = a.state, stateAt = a.stateAt, now = mono(), sync = a.timeSync, aligned = false })
check(mNo.phase == 'WINDOW_OPEN' and not mNo.go, 'fereastră deschisă, nealiniat → fără GO')
local mStale = Model.driver({ paired = true, state = a.state, stateAt = a.stateAt, now = mono() + 5, sync = a.timeSync, aligned = true })
check(mStale.phase == 'STALE' and not mStale.go, 'fără răspuns > 4 s → CONEXIUNE PIERDUTĂ, fără GO')

a:queueEvent('departure', { aligned = true, alignment = 'ALIGNED', speed_kmh = 9 }, slotA, a.state.procedure.schedule_version)
s = poll(a)
check(#a.pending == 0, 'raportul de plecare confirmat (ack) de server')
check(s.me.code == 'DEPARTED', 'pilot A: plecare înregistrată (' .. tostring(s.me.code) .. ')')

-- Pilotul B nu trimite nimic în fereastra lui (aplicație oprită) → analiză, nu ratare automată.
local slotB = poll(b).me.slot
while a.timeSync:serverNowMs(mono()) < slotB.window_closes_at_ms + 6500 do poll(a); sleep(0.5) end
poll(sc)
s = poll(b)
check(s.me.code == 'IN_REVIEW', 'pilot B fără date în fereastră → ÎN ANALIZĂ la Race Control (' .. tostring(s.me.code) .. ')')

-- HOLD din Safety Car, apoi reluare.
local held
sc:action('hold', { event_id = seed.event_id, class_id = seed.class_id, reason = 'test integrare' }, function (ok, r) held = ok and r.procedure.status == 'hold' end)
check(held, 'HOLD confirmat de server')
-- (B este în analiză; procedura e încă deschisă)
s = poll(a)
check(s.procedure.status == 'hold', 'piloții văd HOLD')
local resumed
sc:action('resume', { event_id = seed.event_id, class_id = seed.class_id }, function (ok, r) resumed = ok and r.procedure.status == 'running' end)
check(resumed, 'reluare confirmată de server')

print(failures == 0 and '\nINTEGRARE OK' or ('\nINTEGRARE: ' .. failures .. ' eșecuri'))
os.exit(failures == 0 and 0 or 1)
