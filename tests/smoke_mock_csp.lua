-- Test de fum: încarcă DRSStarter.lua cu un API CSP SIMULAT (stub-uri) și rulează câteva scenarii.
-- Scop: prinde erori de execuție în codul de legătură/UI (nil, apeluri greșite între module).
-- NU dovedește că API-ul CSP real are aceleași semnături sau că desenul arată corect în joc.
-- Rulare: luajit tests/smoke_mock_csp.lua   (din folderul proiectului)

local appDir = './DRSStarter'
package.path = appDir .. '/?.lua;' .. package.path

-- ── vec2 / vec3 / rgbm minimale ──
local function mkvec(n)
  local mt = {}
  local keys = n == 2 and { 'x', 'y' } or { 'x', 'y', 'z' }
  local function new(...)
    local a = { ... }
    local o = {}
    for i, k in ipairs(keys) do o[k] = a[i] or 0 end
    return setmetatable(o, mt)
  end
  local function op(f) return function (a, b)
    local o = {}
    for _, k in ipairs(keys) do
      local av = type(a) == 'number' and a or a[k]
      local bv = type(b) == 'number' and b or b[k]
      o[k] = f(av, bv)
    end
    return setmetatable(o, mt)
  end end
  mt.__add = op(function (a, b) return a + b end)
  mt.__sub = op(function (a, b) return a - b end)
  mt.__mul = op(function (a, b) return a * b end)
  mt.__div = op(function (a, b) return a / b end)
  mt.__index = {}
  return new
end
vec2, vec3 = mkvec(2), mkvec(3)
rgbm = setmetatable({ colors = { white = {}, black = {}, transparent = {} } }, { __call = function (_, r, g, b, a) return { r, g, b, a } end })

-- ── ui / render: orice funcție necunoscută este un stub care înregistrează apelul ──
local calls = {}
local function stubTable(name, overrides)
  return setmetatable(overrides or {}, { __index = function (t, k)
    local f = function (...) calls[name .. '.' .. k] = (calls[name .. '.' .. k] or 0) + 1; return false end
    rawset(t, k, f)
    return f
  end })
end
local fontObj = {}
fontObj.__index = fontObj
function fontObj:weight() return self end
function fontObj:style() return self end
local clickNext = {}
ui = stubTable('ui', {
  DWriteFont = setmetatable({ Weight = { UltraBold = 'UltraBold', Regular = 'Regular', SemiBold = 'SemiBold' }, Style = { Italic = 'Italic' } },
    { __call = function () return setmetatable({}, fontObj) end }),
  Alignment = { Start = -1, Center = 0, End = 1 },
  windowSize = function () return vec2(760, 346) end,
  invisibleButton = function (id) calls['ui.invisibleButton'] = (calls['ui.invisibleButton'] or 0) + 1; return clickNext[id] == true end,
  slider = function (_, v) return v end,
})
render = stubTable('render', {
  BlendMode = { AlphaBlend = 1, Opaque = 0 }, DepthMode = { ReadOnlyLessEqual = 4, Normal = 0 }, GLPrimitiveType = { Quads = 3 },
})

-- ── ac / sim / mașină simulată ──
local clock = 1000
os.preciseClock = function () return clock end
local car = {
  position = vec3(0, 0, -1.5), look = vec3(0, 0, 1), speedKmh = 0, steer = 0,
  aabbSize = vec3(1.8, 1.3, 4.2), aabbCenter = vec3(0, 0.5, 0),
  wheels = {},
}
local function placeFront(z)
  car.wheels = car.wheels or {}
  car.wheels[0] = { contactPoint = vec3(-0.8, 0, z), position = vec3(-0.8, 0.3, z), tyreOptimumTemperature = 80 }
  car.wheels[1] = { contactPoint = vec3(0.8, 0, z), position = vec3(0.8, 0.3, z), tyreOptimumTemperature = 80 }
  car.wheels[2] = { contactPoint = vec3(-0.8, 0, z - 2.5), position = vec3(-0.8, 0.3, z - 2.5), tyreOptimumTemperature = 75 }
  car.wheels[3] = { contactPoint = vec3(0.8, 0, z - 2.5), position = vec3(0.8, 0.3, z - 2.5), tyreOptimumTemperature = 75 }
end
placeFront(-5)
local tyreCalls = {}
physics = { setTyresTemperature = function (carIndex, wheel, temp) table.insert(tyreCalls, { carIndex, wheel, temp }) end }
local simState = { isReplayActive = false, isPaused = false, isInMainMenu = false }
local files, store = {}, {}
ac = {
  Wheel = { FrontLeft = 1, FrontRight = 2, RearLeft = 4, RearRight = 8 },
  getSim = function () return simState end,
  getCar = function (i) return i == 0 and car or nil end,
  getTrackID = function () return 'test_hillclimb' end,
  getTrackLayout = function () return '' end,
  getTrackName = function () return 'Test Hillclimb' end,
  getPatchVersionCode = function () return 4302 end,
  getCarID = function () return 'test_car' end,
  storage = function (defaults) for k, v in pairs(defaults) do if store[k] == nil then store[k] = v end end; return store end,
  findNodes = function (name)
    local p = name == 'AC_AB_START_L' and vec3(-4, 0, 0) or vec3(4, 0, 0)
    -- În CSP rezultatul este cdata (FFI), unde __len funcționează; în Lua 5.1 tabelele ignoră __len, deci folosim un proxy userdata.
    local u = newproxy(true)
    getmetatable(u).__len = function () return 1 end
    getmetatable(u).__index = { getPosition = function () return p end }
    return u
  end,
}
io.fileExists = function (p) return files[p] ~= nil end
io.load = function (p) return files[p] end
io.save = function (p, data) files[p] = data end
-- JSON simplu (doar pentru test): serializăm cu un encoder minimal și decodăm prin load().
local function enc(v)
  local t = type(v)
  if t == 'table' then
    if #v > 0 or next(v) == nil then
      local out = {}; for i = 1, #v do out[i] = enc(v[i]) end; return '{' .. table.concat(out, ',') .. '}'
    end
    local out = {}
    for k, x in pairs(v) do out[#out + 1] = '[' .. string.format('%q', k) .. ']=' .. enc(x) end
    return '{' .. table.concat(out, ',') .. '}'
  elseif t == 'string' then return string.format('%q', v)
  else return tostring(v) end
end
JSON = { stringify = enc, parse = function (s) return assert(loadstring('return ' .. s))() end }
__dirname = appDir
script = {}

-- ── Încărcare aplicație ──
dofile(appDir .. '/DRSStarter.lua')

local A = require('src/alignment')
local failures = 0
local function check(cond, msg) if cond then print('  ok   ' .. msg) else failures = failures + 1; print('  FAIL ' .. msg) end end
local function frames(n, dt)
  for _ = 1, n do clock = clock + (dt or 0.016); script.update(0.016); script.windowMain(0.016); script.draw3D() end
end

print('Smoke test (API CSP simulat)')
frames(5)
-- Fără configurație.
script.windowSettings(0.016)
check(true, 'fără configurație: update/windowMain/settings/draw3D rulează fără erori')

-- Calibrare din nodurile traseului (linie la z = 0), apoi aliniere cu axa față la z = -0.30.
clickNext = {}
local appRef
-- Accesăm obiectul aplicației prin setările UI (UiSettings primește app): îl capturăm cu un wrapper.
local UiSettings = require('src/ui_settings')
local origDraw = UiSettings.draw
UiSettings.draw = function (app) appRef = app; return origDraw(app) end
script.windowSettings(0.016)
check(appRef ~= nil, 'obiectul aplicației accesibil')
appRef:lineFromTrackNodes()
check(appRef.activeCfg ~= nil and appRef.activeCfg.source == 'track_nodes', 'configurație din AC_AB_START_L/R creată și activă')
check(files[appDir .. '/data/starts.local.json'] ~= nil, 'calibrarea salvată în data/starts.local.json')

placeFront(-0.30)
frames(90)
check(appRef.result.state == A.State.ALIGNED, 'aliniat după ~1,4 s (stare: ' .. tostring(appRef.result.state) .. ')')
placeFront(-0.05)
frames(2)
check(appRef.result.state == A.State.TOO_FAR_FORWARD and appRef.result.alignmentLost, 'prea în față + avertisment pierdere aliniere')

-- Captură manuală: roți pe linie la z = 2 → ținta la z = 1.70.
placeFront(2.0)
store.captureRoute = 'invers'
appRef:startCapture()
frames(80)
check(appRef.capture == nil and appRef.activeCfg.source == 'manual_capture', 'captură manuală finalizată: ' .. tostring(appRef.calibrationMessage))
placeFront(1.70)
frames(90)
check(appRef.result.state == A.State.ALIGNED, 'aliniat pe linia capturată manual')

-- Countdown: salt de 95 s.
clock = clock + 95
frames(1)
check(appRef.cd.display >= 1 and appRef.cd.display <= 40, 'countdown valid după salt mare (' .. appRef.cd.display .. ')')

-- Safety Car Mode: confirmare.
store.mode = 'safety'
clickNext = { ['##confirm'] = true }
frames(1)
clickNext = {}
check(appRef.procedure:snapshot().phase == 'SC_AT_FINISH', 'Safety Car: confirmare locală înregistrată')
clickNext = { ['##hold'] = true }; frames(1); clickNext = {}
check(appRef.procedure:snapshot().phase == 'HOLD', 'Safety Car: HOLD local')
store.mode = 'driver'

-- Replay → suspendat.
simState.isReplayActive = true; frames(1)
check(appRef.result.state == A.State.SUSPENDED, 'replay → evaluare suspendată')
simState.isReplayActive = false

-- Câmp lipsă în API (wheels = nil) → fără crash, referință aproximativă.
car.wheels = nil; frames(3)
check(appRef.result.state ~= A.State.ALIGNED, 'fără roți → niciodată verde (stare: ' .. tostring(appRef.result.state) .. ')')

-- ── Încălzire anvelope + interfață minimizată în manșă ──
local UiDriver = require('src/ui_driver')
local compactCalls = 0
local origCompact = UiDriver.drawCompact
UiDriver.drawCompact = function (m) compactCalls = compactCalls + 1; return origCompact(m) end
local p0z = appRef.activeCfg.line.p0.z
car.isInPit, car.speedKmh = true, 0
car.position = vec3(0, 0, p0z - 300); placeFront(p0z - 298)
frames(30)
local n1 = #tyreCalls
check(appRef.warmState == 'pit' and n1 >= 4 and tyreCalls[1][1] == 0 and tyreCalls[1][3] == 80, 'boxe: încălzire activă, temperatura optimă aplicată mașinii proprii (' .. tostring(appRef.warmState) .. ')')
car.isInPit = false
car.position = vec3(0, 0, p0z - 10); placeFront(p0z - 8)
frames(10)
local n2 = #tyreCalls
frames(20)
check(appRef.warmState == 'stopped' and #tyreCalls == n2, 'la 10 m de start: încălzirea oprită')
car.speedKmh = 80
car.position = vec3(0, 0, p0z + 28); placeFront(p0z + 30)
frames(3)
check(appRef.onRun and compactCalls > 0, 'după start cu viteză: interfața minimizată')
car.speedKmh = 0; car.isInPit = true
car.position = vec3(0, 0, p0z - 300); placeFront(p0z - 298)
local c0 = compactCalls
frames(20)
check(not appRef.onRun and compactCalls == c0 and appRef.warmState == 'pit' and #tyreCalls > n2, 'back to pits: interfața revine mare, încălzirea repornește (Run 2)')
car.isInPit = false
physics.setTyresTemperature = function () error('restricționat') end
frames(20)
check(true, 'API de fizică indisponibil: fără eroare în aplicație')
physics.setTyresTemperature = function (carIndex, wheel, temp) table.insert(tyreCalls, { carIndex, wheel, temp }) end

-- ── Faza 2: mod LIVE cu server simulat (web.request din CSP înlocuit) ──
local reqs = {}
web = { request = function (method, url, headers, body, cb) table.insert(reqs, { method = method, url = url, headers = headers, body = body, cb = cb }) end }
local SMS = 1795000000000
local function respond(code, tbl) local r = table.remove(reqs, 1); r.cb(nil, { status = code, body = JSON.stringify(tbl), headers = {} }); return r end
local function serverState(code, extra)
  local st = { schema = 1, server_received_ms = SMS, server_time_ms = SMS, stale_after_ms = 4000, poll_after_ms = 1000, acks = {},
    procedure = { status = 'running', schedule_version = 1 },
    me = { code = code, slot = { id = 5, status = 'scheduled', attempt = 1, scheduled_at_ms = SMS + 15000, window_opens_at_ms = SMS + 5000, window_closes_at_ms = SMS + 25000 } } }
  for k, v in pairs(extra or {}) do st[k] = v end
  return st
end
car.wheels = {}
placeFront(1.70)
car.speedKmh = 0
store.source, store.serverUrl, store.token, store.mode = 'live', 'https://drs.example', 'drs_' .. string.rep('t', 56), 'driver'
frames(1)
check(#reqs == 1 and reqs[1].url:find('/api/starter/v1/sync', 1, true) and reqs[1].headers.Authorization:find('Bearer', 1, true), 'live: o cerere /sync cu token, fără blocare')
local t0 = clock
respond(200, serverState('SCHEDULED'))
frames(90)
local lv = appRef:liveModel(clock)
check(lv.phase == 'SCHEDULED' and lv.countdownS and lv.countdownS > 0 and not lv.go, 'live: countdown spre fereastră (' .. tostring(lv.countdownS) .. ' s), fără GO')
-- Serverul răspunde la fiecare cerere; ceasul local avansează în fereastră.
local function serve(code, n, extra) for _ = 1, n do frames(10); while #reqs > 0 do respond(200, serverState(code, extra)) end end end
clock = t0 + 6
serve('WINDOW_OPEN', 3)
lv = appRef:liveModel(clock)
check(lv.phase == 'WINDOW_OPEN' and lv.go == true and appRef.result.state == A.State.ALIGNED, 'live: fereastră deschisă + aliniat → GO')
-- Plecare: mașina trece de linie cu viteză → raport în următoarea cerere.
car.speedKmh = 12
placeFront(1.70 + 1.8)
frames(12)
local sent = reqs[1] and reqs[1].body or ''
check(sent:find('departure', 1, true) ~= nil, 'live: raportul de plecare este trimis la server')
while #reqs > 0 do respond(200, serverState('DEPARTED')) end
-- Conexiune pierdută: fără răspunsuri > 4 s → STALE, niciodată GO.
car.speedKmh = 0; placeFront(1.70); frames(90)
clock = clock + 5
frames(1)
lv = appRef:liveModel(clock)
check(lv.phase == 'STALE' and not lv.go, 'live: fără răspuns 5 s → CONEXIUNE PIERDUTĂ (' .. lv.phase .. ')')
-- Cererea rămasă fără răspuns e abandonată după 15 s; sincronizarea repornește.
reqs = {}
clock = clock + 16
frames(2)
clock = clock + 3
frames(2)
check(#reqs == 1, 'live: cerere blocată abandonată după timeout, sincronizarea repornește')
-- Safety Car LIVE: confirmare în doi pași, trimisă la server.
store.mode = 'safety'
frames(12)
while #reqs > 0 do respond(200, { schema = 1, server_received_ms = SMS, server_time_ms = SMS + 9000, stale_after_ms = 4000, poll_after_ms = 1000, acks = {},
  mode = 'safety', identity = { can_confirm_finish = true, can_hold = true }, context = { event_id = 1, class_id = 2, run = 1, event = 'E', class = 'C', phase = 'run1' },
  can_confirm_now = true, blockers = {}, queue = {}, choices = {} }) end
clickNext = { ['##confirm'] = true }; frames(1); clickNext = {}
check(#reqs == 0 or not reqs[#reqs].url:find('confirm-finish', 1, true), 'Safety Car: primul clic doar armează confirmarea')
clickNext = { ['##confirm'] = true }; frames(1); clickNext = {}
local conf
for _, r in ipairs(reqs) do if r.url:find('confirm-finish', 1, true) then conf = r end end
check(conf ~= nil, 'Safety Car: al doilea clic trimite confirmarea la server')
store.mode, store.source = 'driver', 'demo'
frames(2)
check(true, 'revenire la modul demo local fără erori')

print(failures == 0 and '\nSMOKE OK' or ('\nSMOKE: ' .. failures .. ' eșecuri'))
os.exit(failures == 0 and 0 or 1)
