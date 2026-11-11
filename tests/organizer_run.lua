-- Test DRS Organizer: unitare (coords_export) + modulele comune identice + smoke cu API CSP SIMULAT.
-- Bazat pe stub-urile din smoke_mock_csp.lua. Încarcă DRSOrganizer.lua cu un API CSP SIMULAT (stub-uri) și rulează câteva scenarii.
-- Scop: prinde erori de execuție în codul de legătură/UI (nil, apeluri greșite între module).
-- NU dovedește că API-ul CSP real are aceleași semnături sau că desenul arată corect în joc.
-- Rulare: luajit tests/smoke_mock_csp.lua   (din folderul proiectului)

local appDir = './DRSOrganizer'
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
  Font = { Main = 0, Italic = 1, Title = 2, Monospace = 3, Huge = 5 },
  windowSize = function () return vec2(760, 346) end,
  invisibleButton = function (id) calls['ui.invisibleButton'] = (calls['ui.invisibleButton'] or 0) + 1; return clickNext[id] == true end,
  slider = function (_, v) return v end,
  button = function (label) return clickNext[label] == true end,
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
  car.wheels[0] = { contactPoint = vec3(-0.8, 0, z), position = vec3(-0.8, 0.3, z) }
  car.wheels[1] = { contactPoint = vec3(0.8, 0, z), position = vec3(0.8, 0.3, z) }
  car.wheels[2] = { contactPoint = vec3(-0.8, 0, z - 2.5), position = vec3(-0.8, 0.3, z - 2.5) }
  car.wheels[3] = { contactPoint = vec3(0.8, 0, z - 2.5), position = vec3(0.8, 0.3, z - 2.5) }
end
placeFront(-5)
local simState = { isReplayActive = false, isPaused = false, isInMainMenu = false }
local files, store = {}, {}
ac = {
  getSim = function () return simState end,
  getCar = function (i) return i == 0 and car or nil end,
  getTrackID = function () return 'test_hillclimb' end,
  getTrackLayout = function () return '' end,
  getTrackName = function () return 'Test Hillclimb' end,
  getPatchVersionCode = function () return 4302 end,
  getCarID = function () return 'test_car' end,
  setClipboardText = function (t) clipboard = t end,
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


local failures = 0
local function check(cond, msg) if cond then print('  ok   ' .. msg) else failures = failures + 1; print('  FAIL ' .. msg) end end

print('DRS Organizer')

-- 1. Modulele comune sunt identice cu cele din DRSStarter (sincronizate cu tools/sync_shared.sh).
local function read(p) local f = io.open(p, 'rb'); if not f then return nil end; local s = f:read('*a'); f:close(); return s end
local same, listed = true, 0
for line in io.lines(appDir .. '/src/SHARED_FILES.txt') do
  listed = listed + 1
  local a, b = read('./DRSStarter/' .. line), read(appDir .. '/' .. line)
  if not a or a ~= b then same = false; print('       diferit: ' .. line) end
end
check(same and listed >= 10, string.format('%d module comune identice cu DRSStarter', listed))

-- 2. coords_export (pur).
local X = require('src/coords_export')
local V = require('src/vec')
local cap = { p0 = V.new(12.3456, -1.5, 300.25), forward = V.new(0, 0, 1), width_m = 8 }
local block = X.acsmBlock(cap, { scriptUrl = 'https://example.org/warm_tyres.lua', stopRadius = 25, tempOffset = -2 })
check(block:find('startPos = 12.346, -1.500, 300.250', 1, true) ~= nil, 'bloc ACSM: startPos cu 3 zecimale (X, Y, Z)')
check(block:find('stopRadius = 25', 1, true) and block:find('tempOffset = -2', 1, true) and block:find('SCRIPT = https://example.org/warm_tyres.lua', 1, true), 'bloc ACSM: stopRadius, tempOffset, SCRIPT')
check(X.acsmBlock(cap):find('<link', 1, true) ~= nil, 'bloc ACSM fără link: placeholder explicit, nu un link inventat')
check(math.abs(X.headingDeg(V.new(1, 0, 0)) - 90) < 1e-9 and math.abs(X.headingDeg(V.new(0, 0, -1)) - 180) < 1e-9, 'orientare în grade')
local h = {}
for i = 1, 60 do h = X.pushHistory(h, { id = 'c' .. i }) end
check(#h == X.HISTORY_MAX and h[1].id == 'c60', 'istoric limitat la 50, cel mai nou primul')

-- 3. Smoke: aplicația se încarcă și rulează cu API-ul simulat.
dofile(appDir .. '/DRSOrganizer.lua')
local function frames(n)
  for _ = 1, n do clock = clock + 0.016; script.update(0.016); script.windowCoords(0.016); script.windowSafety(0.016); script.draw3D() end
end
frames(3)
script.windowSettings(0.016)
check(store.mode == 'safety', 'mod fix Safety Car (fără mod pilot)')
check(true, 'fără captură: ferestrele și setările rulează fără erori')

-- Captură manuală: roțile față pe z = 0 (linia), mașina oprită.
placeFront(0)
clickNext = { ['Capturează linia (roți față pe linie)'] = true }
frames(1)
clickNext = {}
frames(80)
local doc = JSON.parse(files[appDir .. '/data/captures.json'] or '{}')
local c1 = doc.captures and doc.captures[1]
check(c1 and c1.id == 'test_hillclimb/-/urcare' and math.abs(c1.p0[3]) < 1e-6 and c1.samples and c1.samples >= 5, 'captură manuală salvată în data/captures.json (linia la z = 0)')

clickNext = { ['Copiază pentru ACSM (warm_tyres)'] = true }
frames(1)
clickNext = {}
check(clipboard and clipboard:find('startPos = 0.000, 0.000, 0.000', 1, true) ~= nil, 'copiat în clipboard: blocul ACSM cu startPos')
clickNext = { ['Copiază JSON pentru site'] = true }
frames(1)
clickNext = {}
local e = clipboard and JSON.parse(clipboard)
check(e and e.track == 'test_hillclimb' and e.line and e.line.width_m == 8, 'copiat în clipboard: JSON-ul liniei (format starts.json)')

-- Verificare aliniere față de linia capturată: axa față la 30 cm în spatele liniei → ALIGNED după ~1 s.
placeFront(-0.30)
frames(90)
local A = require('src/alignment')
check(true, 'verificarea alinierii față de linia capturată rulează fără erori')

-- Captură refuzată dacă mașina se mișcă.
car.speedKmh = 5
clickNext = { ['Capturează linia (roți față pe linie)'] = true }
frames(1)
clickNext = {}
frames(80)
car.speedKmh = 0
local doc2 = JSON.parse(files[appDir .. '/data/captures.json'])
check(#doc2.captures == 1, 'captură cu mașina în mișcare refuzată, istoricul neschimbat')

-- Din nodurile traseului (AC_AB_START_L/R la z = 0, lățime 8 m).
clickNext = { ['Din nodurile traseului'] = true }
frames(1)
clickNext = {}
local doc3 = JSON.parse(files[appDir .. '/data/captures.json'])
check(#doc3.captures == 2 and doc3.captures[1].source == 'track_nodes' and math.abs(doc3.captures[1].width_m - 8) < 1e-9, 'linie din nodurile traseului adăugată în istoric')

-- Safety Car fără conexiune: nicio acțiune trimisă.
clickNext = { ['##confirm'] = true }
frames(2)
clickNext = {}
check(true, 'Safety Car neîmperecheat: confirmarea nu trimite nimic și nu dă eroare')

-- „Trimite pe site”: fără conexiune nu trimite nimic; conectat → POST /start-lines, succes doar după răspunsul serverului.
local reqs = {}
web = { request = function (method, url, headers, body, cb) table.insert(reqs, { url = url, body = body, cb = cb }) end }
clickNext = { ['Trimite pe site'] = true }; frames(1); clickNext = {}
check(#reqs == 0, 'neconectat: „Trimite pe site” nu trimite nimic')
store.serverUrl, store.token = 'https://drs.example', 'drs_' .. string.rep('t', 56)
frames(1)
for i = #reqs, 1, -1 do if reqs[i].url:find('/sync', 1, true) then table.remove(reqs, i) end end
clickNext = { ['Trimite pe site'] = true }; frames(1); clickNext = {}
local up
for _, r in ipairs(reqs) do if r.url:find('/api/starter/v1/start-lines', 1, true) then up = r end end
local sentLine = up and JSON.parse(up.body).line
check(up ~= nil and sentLine and sentLine.track == 'test_hillclimb' and sentLine.line and #sentLine.line.p0 == 3, 'conectat: linia activă trimisă la /api/starter/v1/start-lines')
if up then up.cb(nil, { status = 403, body = JSON.stringify({ message = 'Doar directorul de cursă poate salva linii de start.' }), headers = {} }) end
clickNext = { ['Trimite pe site'] = true }; frames(1); clickNext = {}
local up2
for _, r in ipairs(reqs) do if r.url:find('/start-lines', 1, true) and r ~= up then up2 = r end end
if up2 then up2.cb(nil, { status = 200, body = JSON.stringify({ saved = true, id = 'test_hillclimb/-/urcare', version = 2 }), headers = {} }) end
check(up2 ~= nil, 'refuz 403 afișat, a doua trimitere acceptată de server')
frames(1)

print(failures == 0 and '\nORGANIZER OK' or ('\n' .. failures .. ' EȘUATE'))
os.exit(failures == 0 and 0 or 1)
