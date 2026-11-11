-- DRS Starter — aplicație CSP Lua pentru alinierea la linia de start.
-- Modul DEMO LOCAL (Faza 1): countdown de 40 s doar pentru testul interfeței, fără rețea.
-- Modul LIVE (Faza 2): ore de start și ferestre DOAR de la Race Control (Laravel), sincronizate cu ora serverului.
-- Liniile de start vin în LIVE DOAR de pe site (admin → Linii de start): pilotul nu le poate muta și nu poate lărgi
-- zona verde. Safety Car și captura liniilor sunt în aplicația organizatorului (DRS Organizer).

local C = require('src/config')
local V = require('src/vec')
local Countdown = require('src/countdown')
local A = require('src/alignment')
local SC = require('src/start_config')
local CarProbe = require('src/car_probe')
local UiDriver = require('src/ui_driver')
local UiSettings = require('src/ui_settings')
local World = require('src/world_draw')
local Client = require('src/live/client')
local LiveModel = require('src/live/live_model')
local Departure = require('src/live/departure')
local Warm = require('src/warm_tyres')

local sim = ac.getSim()
local function now() return os.preciseClock() end

local SHIPPED_FILE = __dirname .. '/data/starts.json' -- doar pentru demo local

local storage = ac.storage({
  mode = 'driver',          -- doar 'driver' (Safety Car este în DRS Organizer)
  preferredId = '',
  anchor = -1,              -- ancora countdown-ului local (os.preciseClock), pentru reîncărcarea aplicației
  draw3D = true,
  showExample = true,       -- panoul „Exemplu poziție” din machetă
  debug = false,
  -- Faza 2 (Race Control). Tokenul dispozitivului nu se afișează niciodată.
  source = 'demo',          -- 'demo' (local, Faza 1) | 'live' (Race Control)
  serverUrl = '',           -- ex. https://<domeniul DRS>; http doar pentru dezvoltare locală
  token = '',
  deviceName = 'DRS Starter',
  eventSeq = 0, statusSeq = 0, pendingEvents = '',
})
storage.mode = 'driver' -- o instalare veche putea avea 'safety' salvat

local app = {
  storage = storage,
  track = { id = ac.getTrackID() or '', layout = ac.getTrackLayout() or '', name = ac.getTrackName and ac.getTrackName() or '' },
  cspBuild = ac.getPatchVersionCode and ac.getPatchVersionCode() or 0,
  configs = {}, trackConfigs = {}, configErrors = {}, activeCfg = nil,
  siteLines = nil,          -- {version, starts} primite de la Race Control (doar în memorie)
  tracker = A.newTracker(),
  result = { state = A.State.NO_CONFIG },
  warm = Warm.new(C.WARM_TYRES), warmState = 'off',
  onRun = false,            -- după plecare: interfața minimizată până la „back to pits”
  goFlashUntil = -1, lastGoAt = nil, departedAfterGo = false, alignedThisCycle = false, earlyMoveUntil = -1,
}

-- ───────────────────────── Configurații ─────────────────────────

local function readJson(path)
  if not io.fileExists(path) then return nil end
  local raw = io.load(path)
  if not raw or raw == '' then return nil end
  local ok, doc = pcall(JSON.parse, raw)
  if not ok then return nil, 'JSON invalid în ' .. path end
  return doc
end

--- Demo: liniile livrate cu aplicația. LIVE: DOAR liniile de pe site (fișierele locale sunt ignorate).
function app:reloadConfigs()
  self.configErrors = {}
  local list = {}
  if storage.source == 'live' then
    if self.siteLines then
      local errs
      list, errs = SC.parseDocument({ schema = 1, starts = self.siteLines.starts })
      for _, c in ipairs(list) do c.origin = 'site' end
      for _, e in ipairs(errs) do table.insert(self.configErrors, 'linie de pe site ' .. e) end
    end
  else
    local doc, err = readJson(SHIPPED_FILE)
    if err then table.insert(self.configErrors, err) end
    if doc then
      local errs
      list, errs = SC.parseDocument(doc)
      for _, c in ipairs(list) do c.source = c.source == 'unknown' and 'shipped' or c.source; c.origin = 'shipped' end
      for _, e in ipairs(errs) do table.insert(self.configErrors, 'starts.json ' .. e) end
    end
  end
  self.configs = list
  self.trackConfigs = SC.forTrack(self.configs, self.track.id, self.track.layout)
  local s = self.sample
  local point = s and A.referencePoint(s)
  self.activeCfg = SC.select(self.trackConfigs, storage.preferredId ~= '' and storage.preferredId or nil, point, s and s.look)
  self.tracker = A.newTracker()
  self.configSource = storage.source == 'live' and 'live' or 'demo'
end

-- ───────────────────────── Race Control (Faza 2) ─────────────────────────

app.client = Client.new({ storage = storage, now = now, json = JSON, appVersion = C.APP_VERSION, cspBuild = app.cspBuild, mode = 'driver' })
app.departure = Departure.new()
function app:isLive() return storage.source == 'live' end
app.client.linesProvider = function () return { track = app.track.id, layout = app.track.layout } end
app.client.onStartLines = function (lines)
  app.siteLines = lines
  app:reloadConfigs()
end
app.client.statusProvider = function ()
  local r, smp = app.result, app.sample
  return {
    mode = 'driver', alignment = r and r.state, aligned = r and r.state == A.State.ALIGNED or false,
    speed_kmh = smp and smp.speedKmh or nil, in_zone = app.departure.inZone, d_m = r and r.measure and r.measure.d or nil,
    track = app.track.id,
  }
end

function app:liveModel(t)
  return LiveModel.driver({
    paired = self.client:paired(), pairing = self.client.pairing, state = self.client.state, stateAt = self.client.stateAt,
    now = t, sync = self.client.timeSync, error = self.client.lastError, aligned = self.result.state == A.State.ALIGNED,
  })
end

-- ───────────────────────── Countdown local ─────────────────────────

do
  local t = now()
  local anchor = Countdown.isAnchorUsable(storage.anchor, t, C.LOCAL_ANCHOR_MAX_AGE_S) and storage.anchor or nil
  app.countdown = Countdown.new(C.LOCAL_COUNTDOWN_S, t, anchor)
  storage.anchor = app.countdown.anchor
end
function app:countdownPause() self.countdown:pause(now()) end
function app:countdownResume() self.countdown:resume(now()); storage.anchor = self.countdown.anchor end
function app:countdownReset() self.countdown:reset(now()); storage.anchor = self.countdown.anchor end

-- ───────────────────────── Ciclu de viață ─────────────────────────

app:reloadConfigs()

function script.update(dt)
  local t = now()
  app.cd = app.countdown:update(t)
  if app.cd.cycleCompleted then
    app.goFlashUntil = t + C.LOCAL_GO_FLASH_S
    app.lastGoAt, app.departedAfterGo, app.alignedThisCycle = t, false, false
  end

  local suspended = sim.isReplayActive or sim.isPaused or sim.isInMainMenu
  app.sample = CarProbe.sample()
  if app.configSource ~= (app:isLive() and 'live' or 'demo') then app:reloadConfigs() end -- comutare demo ↔ LIVE
  local errText = (#app.configErrors > 0 and #app.trackConfigs == 0) and app.configErrors[1] or nil
  if not errText and #app.trackConfigs == 0 and app:isLive() then
    errText = app.siteLines and 'Race Control nu are o linie de start pentru acest traseu.'
      or (app.client:paired() and 'Aștept linia de start de la Race Control…' or 'Conectează aplicația la Race Control (⚙ Setări) ca să primești linia de start.')
  end
  app.result = app.tracker:evaluate(app.sample, app.activeCfg, t, { suspended = suspended, configError = errText })

  -- Fără rută aleasă explicit: re-selecție după proximitate și sens (rute multiple / sens invers), o dată pe secundă.
  if storage.preferredId == '' and #app.trackConfigs > 1 and t - (app.lastSelectAt or -10) > 1 then
    app.lastSelectAt = t
    local point = app.sample and A.referencePoint(app.sample)
    local sel = SC.select(app.trackConfigs, nil, point, app.sample and app.sample.look)
    if sel and sel ~= app.activeCfg then app.activeCfg, app.tracker = sel, A.newTracker() end
  end

  local speed = app.sample and app.sample.speedKmh or 0

  -- Încălzirea anvelopelor până la linia de start activă (aceeași linie ca alinierea).
  local startP0 = app.activeCfg and app.activeCfg.line.p0 or nil
  if not suspended then app.warmState = app.warm:update(dt, app.sample, startP0, Warm.cspApply) end

  -- Minimizare în manșă: după ce a trecut de linie cu viteză; revine mare în boxe.
  local m = app.result and app.result.measure
  if app.sample and app.sample.isInPit then app.onRun = false
  elseif not app.onRun and m and m.alongLine >= C.ON_RUN_PAST_LINE_M and speed >= C.ON_RUN_MIN_SPEED_KMH and math.abs(m.lateral or 0) <= 6 then
    app.onRun = true
  end

  if app:isLive() then
    app.client:update()
    -- Plecare / ieșire din zonă: raport (dovadă) trimis la Race Control; nu este timing oficial.
    local ev = (not suspended) and app.departure:update(app.result, speed, t, A.State.ALIGNED) or nil
    if ev and app.client:paired() then
      local st = app.client.state
      local me, proc = st and st.me, st and st.procedure
      app.client:queueEvent(ev.type, { aligned = ev.aligned, alignment = app.result.state, speed_kmh = speed,
        d_m = app.result.measure and app.result.measure.d or nil }, me and me.slot, proc and proc.schedule_version)
      if ev.type == 'departure' then app.lastDepartureAt = t end
    end
    return
  end

  -- Stări demonstrative locale (nu sunt raportate nicăieri).
  if app.result.state == A.State.ALIGNED then app.alignedThisCycle = true end
  if app.alignedThisCycle and not app.cd.paused and speed > 2 and t >= app.goFlashUntil and app.cd.remaining > 0.2 then
    app.earlyMoveUntil = t + 5
    app.alignedThisCycle = false
  end
  if app.lastGoAt and t - app.lastGoAt < 15 and speed > 5 then app.departedAfterGo = true end
end

local function progressStep(t)
  if app.lastGoAt and app.departedAfterGo and t - app.lastGoAt < 60 then return 4 end
  if t < app.goFlashUntil then return 3 end
  if app.result.state == A.State.ALIGNED then return 2 end
  return 1
end

local function liveWarning(lv)
  local title, text, level = LiveModel.text(lv.phase)
  if level == 'bad' then return { level = 'bad', title = title, text = text } end
  if app.result.alignmentLost then
    return { level = 'bad', title = 'AI IEȘIT DIN POZIȚIE', text = 'Revino cu roțile din față în zona verde și oprește.' }
  end
  if lv.phase == 'WINDOW_OPEN' and not lv.go then
    return { level = 'warn', title = 'FEREASTRĂ DESCHISĂ — NU EȘTI ALINIAT', text = 'Pleacă doar cu roțile din față în zona verde, oprit.' }
  end
  if app.cspBuild ~= C.APPROVED_CSP_BUILD then
    return { level = 'warn', title = 'VERSIUNE CSP NEAPROBATĂ', text = string.format('Build %s instalat; aprobat: %d (%s).',
      tostring(app.cspBuild), C.APPROVED_CSP_BUILD, C.APPROVED_CSP_LABEL) }
  end
  return { level = level == 'ok' and 'info' or level, title = title, text = text }
end

local function warning(t)
  if t < app.earlyMoveUntil then
    return { level = 'bad', title = 'AI PLECAT ÎNAINTE DE GO (DEMO)', text = 'Detecție locală demonstrativă. Nu este raportată și nu este o penalizare.' }
  end
  if app.result.alignmentLost then
    return { level = 'bad', title = 'AI IEȘIT DIN POZIȚIE', text = 'Revino cu roțile din față în zona verde și oprește.' }
  end
  if app.cspBuild ~= C.APPROVED_CSP_BUILD then
    return { level = 'warn', title = 'VERSIUNE CSP NEAPROBATĂ', text = string.format('Build %s instalat; aprobat: %d (%s).',
      tostring(app.cspBuild), C.APPROVED_CSP_BUILD, C.APPROVED_CSP_LABEL) }
  end
  return { level = 'info', title = 'NU PORNI ÎNAINTE DE START', text = 'Demo local: startul oficial îl dă organizatorul.' }
end

local function context(lv)
  local cfg = app.activeCfg
  -- Fără :upper(): string.upper din Lua nu tratează diacriticele (UTF-8).
  local title = app.track.name ~= '' and app.track.name or app.track.id
  local layout = app.track.layout ~= '' and (' · ' .. app.track.layout) or ''
  local route = (cfg and (' · ' .. cfg.label) or ' · fără linie de start') .. (app.warmState ~= 'off' and (' · ' .. (Warm.LABEL[app.warmState] or '')) or '')
  if app:isLive() then
    local mode = 'PILOT · LIVE'
    local connected = lv and lv.connection == 'CONECTAT'
    return { title = title .. layout, subtitle = mode .. route, rc = { label = lv and lv.connection or 'NECONECTAT', ok = connected } }
  end
  local mode = 'PILOT · DEMO LOCAL'
  return { title = title .. layout, subtitle = mode .. route }
end

local function compact(lv)
  local warm = Warm.LABEL[app.warmState] or ''
  local label = 'DRS · ÎN MANȘĂ'
  if lv and lv.phase == 'HOLD' then label = 'DRS · HOLD' end
  return { label = label, sub = 'Interfața revine la „back to pits” · ' .. warm, ok = not (lv and lv.phase == 'HOLD') }
end

function script.windowMain(dt)
  local t = now()
  if app.onRun then
    return UiDriver.drawCompact(compact(app:isLive() and app:liveModel(t) or nil))
  end
  if app:isLive() then
    local lv = app:liveModel(t)
    return UiDriver.draw({
      ctx = context(lv), result = app.result, cfg = app.activeCfg, sample = app.sample, live = lv,
      progressStep = LiveModel.progressStep(lv, app.result.state == A.State.ALIGNED), warning = liveWarning(lv),
      showExample = storage.showExample,
    })
  end
  UiDriver.draw({
    ctx = context(), result = app.result, cfg = app.activeCfg, sample = app.sample,
    countdown = app.cd or app.countdown:update(t), goFlash = t < app.goFlashUntil,
    progressStep = progressStep(t), warning = warning(t), showExample = storage.showExample,
  })
end

function script.windowSettings(dt)
  UiSettings.draw(app)
end

function script.draw3D()
  if not storage.draw3D or not app.activeCfg then return end
  local m = app.result and app.result.measure
  if m and m.distanceToLine > 150 then return end
  World.draw(app.activeCfg, app.result)
end
