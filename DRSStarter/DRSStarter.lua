-- DRS Starter — aplicație CSP Lua pentru alinierea la linia de start.
-- Modul DEMO LOCAL (Faza 1): countdown de 40 s doar pentru testul interfeței, fără rețea.
-- Modul LIVE (Faza 2): ore de start și ferestre DOAR de la Race Control (Laravel), sincronizate cu ora serverului.

local C = require('src/config')
local V = require('src/vec')
local Countdown = require('src/countdown')
local A = require('src/alignment')
local SC = require('src/start_config')
local Cal = require('src/calibration')
local Procedure = require('src/procedure_local') -- Faza 2: înlocuit de un adaptor remote cu aceleași metode
local CarProbe = require('src/car_probe')
local TrackNodes = require('src/track_nodes')
local UiDriver = require('src/ui_driver')
local UiSafety = require('src/ui_safety')
local UiSettings = require('src/ui_settings')
local World = require('src/world_draw')
local Client = require('src/live/client')
local LiveModel = require('src/live/live_model')
local Departure = require('src/live/departure')
local UiSafetyLive = require('src/ui_safety_live')
local Warm = require('src/warm_tyres')

local sim = ac.getSim()
local function now() return os.preciseClock() end

local SHIPPED_FILE = __dirname .. '/data/starts.json'
local LOCAL_FILE = __dirname .. '/data/starts.local.json'

local storage = ac.storage({
  mode = 'driver',          -- 'driver' | 'safety'
  preferredId = '',
  captureRoute = 'urcare',
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
  scEventId = 0, scClassId = 0, -- clasa aleasă în modul Safety Car
})

local app = {
  storage = storage,
  track = { id = ac.getTrackID() or '', layout = ac.getTrackLayout() or '', name = ac.getTrackName and ac.getTrackName() or '' },
  cspBuild = ac.getPatchVersionCode and ac.getPatchVersionCode() or 0,
  configs = {}, trackConfigs = {}, configErrors = {}, activeCfg = nil,
  localDoc = { schema = 1, starts = {} },
  tracker = A.newTracker(),
  procedure = Procedure.new(),
  result = { state = A.State.NO_CONFIG },
  draft = nil,
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

local function draftFrom(cfg)
  local t = cfg and cfg.target or C.DEFAULT_TARGET
  return { offset_m = t.offset_m, tol_back_m = t.tol_back_m, tol_fwd_m = t.tol_fwd_m, max_heading_deg = t.max_heading_deg,
    max_steer_deg = t.max_steer_deg, width_m = cfg and cfg.line.width_m or C.DEFAULT_LINE_WIDTH_M }
end

function app:reloadConfigs()
  self.configErrors = {}
  local shipped, local_ = {}, {}
  local doc, err = readJson(SHIPPED_FILE)
  if err then table.insert(self.configErrors, err) end
  if doc then
    local list, errs = SC.parseDocument(doc)
    for _, c in ipairs(list) do c.source = c.source == 'unknown' and 'shipped' or c.source; c.origin = 'shipped' end
    shipped = list
    for _, e in ipairs(errs) do table.insert(self.configErrors, 'starts.json ' .. e) end
  end
  local ldoc, lerr = readJson(LOCAL_FILE)
  if lerr then table.insert(self.configErrors, lerr) end
  if ldoc then
    self.localDoc = ldoc
    local list, errs = SC.parseDocument(ldoc)
    for _, c in ipairs(list) do c.origin = 'local' end
    local_ = list
    for _, e in ipairs(errs) do table.insert(self.configErrors, 'starts.local.json ' .. e) end
  end
  self.configs = SC.merge(shipped, local_)
  self.trackConfigs = SC.forTrack(self.configs, self.track.id, self.track.layout)
  local s = self.sample
  local point = s and A.referencePoint(s)
  self.activeCfg = SC.select(self.trackConfigs, storage.preferredId ~= '' and storage.preferredId or nil, point, s and s.look)
  self.draft = draftFrom(self.activeCfg)
  self.tracker = A.newTracker()
end

function app:saveLocal()
  local ok, err = pcall(function () io.save(LOCAL_FILE, JSON.stringify(self.localDoc)) end)
  if not ok then self.calibrationMessage = 'Salvare eșuată: ' .. tostring(err) end
  self:reloadConfigs()
end

local function upsertLocal(entry)
  local starts = app.localDoc.starts or {}
  app.localDoc.starts = starts
  for i, e in ipairs(starts) do
    if e.id == entry.id then starts[i] = entry; return end
  end
  starts[#starts + 1] = entry
end

local function newEntry(line, source)
  local route = storage.captureRoute
  return Cal.buildEntry({
    track = app.track.id, layout = app.track.layout, route = route,
    label = (route == 'urcare' and 'Urcare') or (route == 'invers' and 'Sens invers') or 'Alt start',
    p0 = line.p0, forward = line.forward, width_m = line.width_m,
    target = { offset_m = C.DEFAULT_TARGET.offset_m, tol_back_m = C.DEFAULT_TARGET.tol_back_m, tol_fwd_m = C.DEFAULT_TARGET.tol_fwd_m,
      max_lateral_m = C.DEFAULT_TARGET.max_lateral_m, max_heading_deg = C.DEFAULT_TARGET.max_heading_deg,
      max_steer_deg = C.DEFAULT_TARGET.max_steer_deg },
    stationary = { max_speed_kmh = C.DEFAULT_STATIONARY.max_speed_kmh, hold_s = C.DEFAULT_STATIONARY.hold_s,
      max_drift_m = C.DEFAULT_STATIONARY.max_drift_m },
    source = source, calibrated_at = os.date('!%Y-%m-%dT%H:%M:%SZ'), car = ac.getCarID(0), csp_build = app.cspBuild,
  })
end

function app:startCapture()
  if self.track.id == '' then self.calibrationMessage = 'Traseul nu este identificat.'; return end
  self.capture = { untilT = now() + C.CAPTURE_DURATION_S, samples = {} }
  self.calibrationMessage = nil
end

function app:finishCapture()
  local cap = self.capture
  self.capture = nil
  local res, err = Cal.average(cap.samples)
  if not res then self.calibrationMessage = 'Captură refuzată: ' .. err; return end
  local entry = newEntry({ p0 = res.p0, forward = res.forward, width_m = C.DEFAULT_LINE_WIDTH_M }, 'manual_capture')
  local cfg, verr = SC.validate(entry)
  if not cfg then self.calibrationMessage = 'Captură invalidă: ' .. verr; return end
  upsertLocal(entry)
  self.calibrationMessage = string.format('Salvat „%s” din %d eșantioane, dispersie %.1f cm.', entry.id, res.count, res.spreadM * 100)
  self:saveLocal()
end

function app:lineFromTrackNodes()
  local look = self.sample and self.sample.look
  local line, err = TrackNodes.startLine(look)
  if not line then self.calibrationMessage = 'Noduri indisponibile: ' .. err; return end
  local entry = newEntry(line, 'track_nodes')
  upsertLocal(entry)
  self.calibrationMessage = string.format('Propunere din AC_AB_START_L/R salvată ca „%s” (lățime %.1f m). Verifică vizual linia.',
    entry.id, line.width_m)
  self:saveLocal()
end

function app:applyDraft()
  local cfg = self.activeCfg
  if not cfg then return end
  local entry = SC.toPlain(cfg)
  local d = self.draft
  entry.target.offset_m, entry.target.tol_back_m, entry.target.tol_fwd_m = d.offset_m, d.tol_back_m, d.tol_fwd_m
  entry.target.max_heading_deg, entry.target.max_steer_deg, entry.line.width_m = d.max_heading_deg, d.max_steer_deg, d.width_m
  local ok, err = SC.validate(entry)
  if not ok then self.calibrationMessage = 'Valori respinse: ' .. err; return end
  upsertLocal(entry)
  self.calibrationMessage = 'Parametri salvați pentru „' .. entry.id .. '”.'
  self:saveLocal()
end

function app:deleteLocal(id)
  local starts = self.localDoc.starts or {}
  for i = #starts, 1, -1 do if starts[i].id == id then table.remove(starts, i) end end
  if storage.preferredId == id then storage.preferredId = '' end
  self.calibrationMessage = 'Calibrarea locală „' .. id .. '” a fost ștearsă.'
  self:saveLocal()
end

-- ───────────────────────── Race Control (Faza 2) ─────────────────────────

app.client = Client.new({ storage = storage, now = now, json = JSON, appVersion = C.APP_VERSION, cspBuild = app.cspBuild })
app.departure = Departure.new()
function app:isLive() return storage.source == 'live' end
app.client.statusProvider = function ()
  local r, smp = app.result, app.sample
  return {
    mode = storage.mode, alignment = r and r.state, aligned = r and r.state == A.State.ALIGNED or false,
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
  local errText = (#app.configErrors > 0 and #app.trackConfigs == 0) and app.configErrors[1] or nil
  app.result = app.tracker:evaluate(app.sample, app.activeCfg, t, { suspended = suspended, configError = errText })

  -- Fără rută aleasă explicit: re-selecție după proximitate și sens (rute multiple / sens invers), o dată pe secundă.
  if storage.preferredId == '' and #app.trackConfigs > 1 and t - (app.lastSelectAt or -10) > 1 then
    app.lastSelectAt = t
    local point = app.sample and A.referencePoint(app.sample)
    local sel = SC.select(app.trackConfigs, nil, point, app.sample and app.sample.look)
    if sel and sel ~= app.activeCfg then app.activeCfg, app.draft, app.tracker = sel, draftFrom(sel), A.newTracker() end
  end

  -- Captura de calibrare: eșantioane cu referința pe roți, doar cu mașina oprită (verificat în Cal.average).
  if app.capture and app.sample then
    local p, kind = A.referencePoint(app.sample)
    if p then
      table.insert(app.capture.samples, { point = p, look = app.sample.look, speedKmh = app.sample.speedKmh, reference = kind })
    end
    if t >= app.capture.untilT then app:finishCapture() end
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
    local ev = (not suspended and storage.mode == 'driver') and app.departure:update(app.result, speed, t, A.State.ALIGNED) or nil
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
  local route = (cfg and (' · ' .. cfg.label) or ' · necalibrat') .. (app.warmState ~= 'off' and (' · ' .. (Warm.LABEL[app.warmState] or '')) or '')
  if app:isLive() then
    local mode = storage.mode == 'safety' and 'SAFETY CAR · LIVE' or 'PILOT · LIVE'
    local connected = lv and lv.connection == 'CONECTAT'
    return { title = title .. layout, subtitle = mode .. route, rc = { label = lv and lv.connection or 'NECONECTAT', ok = connected } }
  end
  local mode = storage.mode == 'safety' and 'SAFETY CAR · LOCAL DEMO' or 'PILOT · DEMO LOCAL'
  return { title = title .. layout, subtitle = mode .. route }
end

local function safetyLive(t, lv)
  local c = app.client
  local st = c.state
  local fresh = lv.connection == 'CONECTAT'
  local action = UiSafetyLive.draw({ ctx = context(lv), state = st, fresh = fresh, actionInFlight = c.actionInFlight,
    feedback = c.feedback, armedUntil = app.armedUntil, now = t })
  if not action then return end
  local ctx = st and st.context
  if action == 'arm' then app.armedUntil = t + UiSafetyLive.ARM_S; return end
  app.armedUntil = nil
  if not ctx then return end
  if action == 'confirm' then
    c:action('confirm', { event_id = ctx.event_id, class_id = ctx.class_id, run = ctx.run,
      request_id = string.format('sc-%d-%d-%d-%d', ctx.event_id, ctx.class_id, ctx.run, math.floor(t * 1000)) }, function (ok, r)
      if ok then
        local n = 0
        for _, v in pairs(r.procedure and r.procedure.counts or {}) do n = n + v end
        c.feedback = { ok = true, text = r.already_confirmed and 'Sosirea era deja confirmată (server).'
          or string.format('Confirmat de server: %d starturi programate.', n) }
      end
    end)
  elseif action == 'hold' then
    c:action('hold', { event_id = ctx.event_id, class_id = ctx.class_id, reason = 'HOLD din Safety Car' }, function (ok)
      if ok then c.feedback = { ok = true, text = 'HOLD activ (confirmat de server).' } end
    end)
  elseif action == 'resume' then
    c:action('resume', { event_id = ctx.event_id, class_id = ctx.class_id }, function (ok)
      if ok then c.feedback = { ok = true, text = 'Procedura a fost reluată (confirmat de server).' } end
    end)
  end
end

local function compact(lv)
  local warm = Warm.LABEL[app.warmState] or ''
  local label = 'DRS · ÎN MANȘĂ'
  if lv and lv.phase == 'HOLD' then label = 'DRS · HOLD' end
  return { label = label, sub = 'Interfața revine la „back to pits” · ' .. warm, ok = not (lv and lv.phase == 'HOLD') }
end

function script.windowMain(dt)
  local t = now()
  if app.onRun and storage.mode == 'driver' then
    return UiDriver.drawCompact(compact(app:isLive() and app:liveModel(t) or nil))
  end
  if app:isLive() then
    local lv = app:liveModel(t)
    if storage.mode == 'safety' then return safetyLive(t, lv) end
    return UiDriver.draw({
      ctx = context(lv), result = app.result, cfg = app.activeCfg, sample = app.sample, live = lv,
      progressStep = LiveModel.progressStep(lv, app.result.state == A.State.ALIGNED), warning = liveWarning(lv),
      showExample = storage.showExample,
    })
  end
  if storage.mode == 'safety' then
    local action = UiSafety.draw({ ctx = context(), procedure = app.procedure, feedback = app.feedback, wallAtConfirm = app.wallAtConfirm })
    if action then
      local ok, msg
      if action == 'confirm' then ok, msg = app.procedure:confirmSafetyCarFinish(t); if ok then app.wallAtConfirm = os.time() end
      elseif action == 'hold' then ok, msg = app.procedure:hold(t)
      elseif action == 'release' then ok, msg = app.procedure:release(t)
      elseif action == 'reset' then ok, msg = app.procedure:resetDemo(t); app.wallAtConfirm = nil end
      app.feedback = { text = msg, ok = ok, at = t }
    end
    return
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
  if not storage.draw3D or storage.mode ~= 'driver' or not app.activeCfg then return end
  local m = app.result and app.result.measure
  if m and m.distanceToLine > 150 then return end
  World.draw(app.activeCfg, app.result)
end
