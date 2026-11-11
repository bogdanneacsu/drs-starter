-- Previzualizare de layout: rulează UI-ul cu un API CSP simulat care transformă apelurile de desen în SVG.
-- Doar pentru verificarea poziționării panourilor; randarea reală ImGui/DirectWrite din joc va diferi.
-- Rulare: luajit tests/preview_svg.lua <stare> > preview.svg   (stări: aligned | back | noconfig | safety)

local appDir = './DRSStarter'
package.path = appDir .. '/?.lua;' .. package.path
local scenario = arg[1] or 'aligned'
local H = (scenario == 'safety' or scenario == 'safety_live') and 346 or 446

local function mkvec(keys)
  local mt = {}
  local function new(...) local a = { ... }; local o = {}; for i, k in ipairs(keys) do o[k] = a[i] or 0 end; return setmetatable(o, mt) end
  local function op(f) return function (a, b) local o = {}; for _, k in ipairs(keys) do
    o[k] = f(type(a) == 'number' and a or a[k], type(b) == 'number' and b or b[k]) end; return setmetatable(o, mt) end end
  mt.__add, mt.__sub, mt.__mul, mt.__div = op(function (a, b) return a + b end), op(function (a, b) return a - b end),
    op(function (a, b) return a * b end), op(function (a, b) return a / b end)
  return new
end
vec2, vec3 = mkvec({ 'x', 'y' }), mkvec({ 'x', 'y', 'z' })
rgbm = setmetatable({}, { __call = function (_, r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end })

local out, cursor, fontStack = {}, vec2(0, 0), {}
local function col(c) if not c or not c.r then return 'none', 1 end
  local function ch(v) return math.floor(math.min(1, v) * 255 + 0.5) end
  return string.format('rgb(%d,%d,%d)', ch(c.r), ch(c.g), ch(c.b)), c.a end
local function esc(s) return (tostring(s):gsub('&', '&amp;'):gsub('<', '&lt;')) end
local function fontAttr()
  local f = fontStack[#fontStack] or {}
  local fam = f.family == 'Inter' and 'Inter' or 'Barlow Condensed'
  return string.format('font-family="%s" font-weight="%s" font-style="%s"', fam, f.family == 'Inter' and (f.w == 'SemiBold' and 600 or 400) or 800,
    f.italic and 'italic' or 'normal')
end
local Font = {}; Font.__index = Font
function Font:weight(w) self.w = w; return self end
function Font:style(s) self.italic = s == 'Italic'; return self end

ui = setmetatable({
  DWriteFont = setmetatable({ Weight = { UltraBold = 'UltraBold', Regular = 'Regular', SemiBold = 'SemiBold' }, Style = { Italic = 'Italic' } },
    { __call = function (_, name) return setmetatable({ family = name }, Font) end }),
  Alignment = { Start = -1, Center = 0, End = 1 },
  windowSize = function () return vec2(760, H) end,
  pushDWriteFont = function (f) fontStack[#fontStack + 1] = f end,
  popDWriteFont = function () fontStack[#fontStack] = nil end,
  setCursor = function (p) cursor = p end,
  invisibleButton = function () return false end, itemHovered = function () return false end,
  drawRectFilled = function (p1, p2, c, r) local f, a = col(c)
    out[#out + 1] = string.format('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" fill="%s" fill-opacity="%.2f"/>', p1.x, p1.y, p2.x - p1.x, p2.y - p1.y, r or 0, f, a) end,
  drawRect = function (p1, p2, c, r, _, t) local f, a = col(c)
    out[#out + 1] = string.format('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" fill="none" stroke="%s" stroke-opacity="%.2f" stroke-width="%s"/>', p1.x, p1.y, p2.x - p1.x, p2.y - p1.y, r or 0, f, a, t or 1) end,
  drawRectFilledMultiColor = function (p1, p2, c1, c2) local f1 = col(c1); local f2 = col(c2)
    local id = 'g' .. #out
    out[#out + 1] = string.format('<defs><linearGradient id="%s"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs><rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="url(#%s)"/>', id, f1, f2, p1.x, p1.y, p2.x - p1.x, p2.y - p1.y, id) end,
  drawCircleFilled = function (c, r, cc) local f, a = col(cc); out[#out + 1] = string.format('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" fill-opacity="%.2f"/>', c.x, c.y, r, f, a) end,
  drawCircle = function (c, r, cc, _, t) local f = col(cc); out[#out + 1] = string.format('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="none" stroke="%s" stroke-width="%s"/>', c.x, c.y, r, f, t or 1) end,
  drawLine = function (a, b, cc, t) local f = col(cc); out[#out + 1] = string.format('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="%s"/>', a.x, a.y, b.x, b.y, f, t or 1) end,
  drawImage = function (path, p1, p2) out[#out + 1] = string.format('<image href="%s" x="%.1f" y="%.1f" width="%.1f" height="%.1f"/>', path, p1.x, p1.y, p2.x - p1.x, p2.y - p1.y) end,
  dwriteDrawText = function (s, size, p, c) local f = col(c)
    out[#out + 1] = string.format('<text x="%.1f" y="%.1f" font-size="%d" fill="%s" %s dominant-baseline="hanging">%s</text>', p.x, p.y, size, f, fontAttr(), esc(s)) end,
  dwriteTextAligned = function (s, size, h, v, box, _, c) local f = col(c)
    local x = h == -1 and cursor.x or (h == 1 and cursor.x + box.x or cursor.x + box.x / 2)
    local anchor = h == -1 and 'start' or (h == 1 and 'end' or 'middle')
    out[#out + 1] = string.format('<text x="%.1f" y="%.1f" font-size="%d" fill="%s" %s text-anchor="%s" dominant-baseline="central">%s</text>', x, cursor.y + box.y / 2, size, f, fontAttr(), anchor, esc(s)) end,
}, { __index = function () return function () return false end end })
render = setmetatable({ BlendMode = {}, DepthMode = {}, GLPrimitiveType = {} }, { __index = function () return function () end end })

local clock = 5000
os.preciseClock = function () return clock end
local car = { position = vec3(0, 0, -2), look = vec3(0, 0, 1), speedKmh = 0, steer = 0, aabbSize = vec3(1.8, 1.3, 4.2), aabbCenter = vec3(0, 0.5, 0), wheels = {} }
local function front(z)
  for i, x in ipairs({ -0.8, 0.8, -0.8, 0.8 }) do local zz = i <= 2 and z or z - 2.5
    car.wheels[i - 1] = { contactPoint = vec3(x, 0, zz), position = vec3(x, 0.3, zz) } end
end
local store = {}
local files = {}
ac = { getSim = function () return {} end, getCar = function () return car end, getTrackID = function () return 'ranca_transalpina' end,
  getTrackLayout = function () return 'urcare' end, getTrackName = function () return 'Rânca – Transalpina' end,
  getPatchVersionCode = function () return 4302 end, getCarID = function () return 'car' end,
  storage = function (d) for k, v in pairs(d) do if store[k] == nil then store[k] = v end end; return store end,
  findNodes = function () return newproxy(false) end }
io.fileExists = function (p) return files[p] ~= nil end
io.load = function (p) return files[p] end
io.save = function (p, d) files[p] = d end
JSON = { stringify = function () return '' end, parse = function () return nil end }
__dirname = appDir
script = {}
web = { request = function () end } -- fără rețea în previzualizare
dofile(appDir .. '/DRSStarter.lua')

-- Configurație directă (fără JSON) pentru previzualizare.
local SC = require('src/start_config')
local UiSettings = require('src/ui_settings')
local app
local orig = UiSettings.draw
UiSettings.draw = function (a) app = a end
script.windowSettings(0)
UiSettings.draw = orig
if scenario ~= 'noconfig' then
  local cfg = assert(SC.validate({ id = 'r/u/urcare', track = 'ranca_transalpina', layout = 'urcare', label = 'Urcare',
    line = { p0 = { 0, 0, 0 }, forward = { 0, 0, 1 } } }))
  app.trackConfigs, app.activeCfg = { cfg }, cfg
end
if scenario == 'back' then front(-0.62) else front(-0.30) end
if scenario == 'safety' or scenario == 'safety_live' then store.mode = 'safety' end
local live = scenario:match('^live_') or scenario == 'safety_live'
if live then store.source, store.serverUrl, store.token = 'live', 'https://drs.example', 'drs_' .. string.rep('t', 56) end
for _ = 1, 100 do clock = clock + 0.016; script.update(0.016) end
clock = clock + 9.3; script.update(0)
if live then
  -- Stare injectată (ca după un răspuns /sync); ceasul serverului = 19:42:10 la momentul randării.
  local S0 = os.time({ year = 2026, month = 11, day = 20, hour = 19, min = 42, sec = 10 }) * 1000
  local c = app.client
  c.inFlight = true -- fără cereri reale în previzualizare
  c.timeSync:add(clock, S0, S0, clock)
  local slot = { id = 3, status = 'scheduled', attempt = 1, scheduled_at_ms = S0 + 6000, window_opens_at_ms = S0 - 4000, window_closes_at_ms = S0 + 16000 }
  local st = { schema = 1, server_time_ms = S0, server_received_ms = S0, stale_after_ms = 4000, identity = { can_confirm_finish = true, can_hold = true },
    context = { event_id = 1, class_id = 1, run = 1, event = 'Etapa 5 Rânca', class = 'Unlimited', phase = 'run1' },
    procedure = { status = scenario == 'live_hold' and 'hold' or 'running', schedule_version = 2, confirmed_at_ms = S0 - 90000 },
    me = { code = 'WINDOW_OPEN', slot = slot, queue_position = 3 } }
  if scenario == 'live_wait' then st.me.code = 'SCHEDULED'; slot.scheduled_at_ms, slot.window_opens_at_ms, slot.window_closes_at_ms = S0 + 37000, S0 + 27000, S0 + 47000 end
  if scenario == 'safety_live' then
    st.can_confirm_now, st.blockers = false, {}
    st.queue = { { driver = 'Andrei Popescu', race_number = 12, status = 'scheduled', attempt = 1, scheduled_at_ms = S0 + 6000, window_opens_at_ms = S0 - 4000, window_closes_at_ms = S0 + 16000 },
      { driver = 'Mihai Ionescu', race_number = 7, status = 'scheduled', attempt = 1, scheduled_at_ms = S0 + 56000, window_opens_at_ms = S0 + 46000, window_closes_at_ms = S0 + 66000 },
      { driver = 'Radu Stan', race_number = 31, status = 'scheduled', attempt = 2, scheduled_at_ms = S0 + 106000, window_opens_at_ms = S0 + 96000, window_closes_at_ms = S0 + 116000 } }
  end
  c.state, c.stateAt = st, clock
end
out = {}
script.windowMain(0)

io.write(string.format([[<svg xmlns="http://www.w3.org/2000/svg" width="760" height="%d" viewBox="0 0 760 %d">
<style>@font-face{font-family:"Barlow Condensed";font-weight:800;src:url(DRSStarter/fonts/BarlowCondensed-ExtraBold.ttf)}
@font-face{font-family:"Barlow Condensed";font-weight:800;font-style:italic;src:url(DRSStarter/fonts/BarlowCondensed-ExtraBoldItalic.ttf)}
@font-face{font-family:"Inter";src:url(DRSStarter/fonts/Inter.ttf)}</style>
<rect width="760" height="%d" fill="#5b6e7a"/>
%s
</svg>]], H, H, H, table.concat(out, '\n')))
