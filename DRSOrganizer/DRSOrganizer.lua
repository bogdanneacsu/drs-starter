-- DRS Organizer — aplicație CSP Lua locală, DOAR pentru organizator (nu se distribuie piloților).
--  • Fereastra „Coordonate start”: captează linia de start cu mașina oprită (roțile față pe linie) sau din nodurile
--    traseului, verifică alinierea față de ea și copiază textele pentru serverul ACSM (warm_tyres) și pentru site.
--  • Fereastra „Safety Car”: Confirmă sosirea la finish / HOLD / Reluare, autentificat la Race Control (Laravel).

local C = require('src/config')
local V = require('src/vec')
local A = require('src/alignment')
local SC = require('src/start_config')
local Cal = require('src/calibration')
local CarProbe = require('src/car_probe')
local TrackNodes = require('src/track_nodes')
local World = require('src/world_draw')
local Client = require('src/live/client')
local LiveModel = require('src/live/live_model')
local UiSafetyLive = require('src/ui_safety_live')
local X = require('src/coords_export')

local ORGANIZER_VERSION = '0.1.0'
local HISTORY_FILE = __dirname .. '/data/captures.json'
local sim = ac.getSim()
local function now() return os.preciseClock() end

local storage = ac.storage({
  route = 'urcare',
  draw3D = true,
  scriptUrl = 'https://raw.githubusercontent.com/bogdanneacsu/drs-starter/v1.0.0/online/warm_tyres.lua', -- versiune fixă (tag)
  stopRadius = 20, tempOffset = 0,
  -- Race Control. Tokenul dispozitivului nu se afișează niciodată.
  mode = 'safety',
  serverUrl = '', token = '', deviceName = 'DRS Organizer',
  eventSeq = 0, statusSeq = 0, pendingEvents = '',
  scEventId = 0, scClassId = 0,
})
storage.mode = 'safety' -- aplicația organizatorului nu are mod de pilot

local app = {
  track = { id = ac.getTrackID() or '', layout = ac.getTrackLayout() or '', name = ac.getTrackName and ac.getTrackName() or '' },
  cspBuild = ac.getPatchVersionCode and ac.getPatchVersionCode() or 0,
  tracker = A.newTracker(),
  result = nil, sample = nil, capture = nil, last = nil, message = nil, history = {},
}

-- ───────────────────────── Istoric capturi ─────────────────────────

local function loadHistory()
  if not io.fileExists(HISTORY_FILE) then return end
  local ok, doc = pcall(JSON.parse, io.load(HISTORY_FILE) or '')
  if ok and type(doc) == 'table' and type(doc.captures) == 'table' then app.history = doc.captures end
end

local function saveHistory()
  local ok, err = pcall(function () io.save(HISTORY_FILE, JSON.stringify({ schema = 1, captures = app.history })) end)
  if not ok then app.message = { ok = false, text = 'Istoricul nu a putut fi salvat: ' .. tostring(err) } end
end

local function routeLabel(r) return (r == 'urcare' and 'Urcare') or (r == 'invers' and 'Sens invers') or 'Alt start' end

--- Construiește intrarea de configurare (aceeași formă ca DRS Starter / starts.json) și o reține ca „ultima captură”.
local function accept(line, source, stats)
  local entry = Cal.buildEntry({
    track = app.track.id, layout = app.track.layout, route = storage.route, label = routeLabel(storage.route),
    p0 = line.p0, forward = line.forward, width_m = line.width_m or C.DEFAULT_LINE_WIDTH_M,
    target = { offset_m = C.DEFAULT_TARGET.offset_m, tol_back_m = C.DEFAULT_TARGET.tol_back_m, tol_fwd_m = C.DEFAULT_TARGET.tol_fwd_m,
      max_lateral_m = C.DEFAULT_TARGET.max_lateral_m, max_heading_deg = C.DEFAULT_TARGET.max_heading_deg,
      max_steer_deg = C.DEFAULT_TARGET.max_steer_deg },
    stationary = { max_speed_kmh = C.DEFAULT_STATIONARY.max_speed_kmh, hold_s = C.DEFAULT_STATIONARY.hold_s,
      max_drift_m = C.DEFAULT_STATIONARY.max_drift_m },
    source = source, calibrated_at = os.date('!%Y-%m-%dT%H:%M:%SZ'), car = ac.getCarID(0), csp_build = app.cspBuild,
  })
  local cfg, err = SC.validate(entry)
  if not cfg then app.message = { ok = false, text = 'Linie invalidă: ' .. tostring(err) }; return end
  local capture = { p0 = line.p0, forward = line.forward, width_m = entry.line.width_m, spreadM = stats and stats.spreadM, count = stats and stats.count }
  app.last = { entry = entry, cfg = cfg, capture = capture }
  app.tracker = A.newTracker()
  app.history = X.pushHistory(app.history, X.historyItem(entry, capture, entry.calibrated_at))
  saveHistory()
  app.message = { ok = true, text = 'Captură salvată: ' .. X.summary(capture) ..
    (stats and string.format(' · %d eșantioane, dispersie %.1f cm', stats.count, stats.spreadM * 100) or '') }
end

function app:startCapture()
  if self.track.id == '' then self.message = { ok = false, text = 'Traseul nu este identificat.' }; return end
  self.capture = { untilT = now() + C.CAPTURE_DURATION_S, samples = {} }
  self.message = nil
end

function app:fromTrackNodes()
  local line, err = TrackNodes.startLine(self.sample and self.sample.look)
  if not line then self.message = { ok = false, text = 'Noduri indisponibile: ' .. tostring(err) }; return end
  accept(line, 'track_nodes')
end

function app:restore(item)
  local cfg = SC.validate(item.entry)
  if not cfg then self.message = { ok = false, text = 'Captura din istoric este invalidă.' }; return end
  self.last = { entry = item.entry, cfg = cfg, capture = { p0 = V.new(item.p0[1], item.p0[2], item.p0[3]),
    forward = V.new(item.forward[1], item.forward[2], item.forward[3]), width_m = item.width_m } }
  self.tracker = A.newTracker()
  self.message = { ok = true, text = 'Captura „' .. item.id .. '” din ' .. tostring(item.at) .. ' este activă.' }
end

function app:copy(kind)
  if not self.last then return end
  local text = kind == 'acsm' and X.acsmBlock(self.last.capture, { scriptUrl = storage.scriptUrl, stopRadius = storage.stopRadius, tempOffset = storage.tempOffset })
    or JSON.stringify(self.last.entry)
  local ok = pcall(ac.setClipboardText, text)
  if not ok then self.message = { ok = false, text = 'Copierea în clipboard a eșuat; textul e afișat mai jos.' }; return end
  self.message = { ok = true, text = kind == 'acsm' and 'Blocul pentru csp_extra_options.ini a fost copiat.' or 'JSON-ul liniei de start a fost copiat.' }
end

-- ───────────────────────── Race Control ─────────────────────────

--- „Trimite pe site”: salvează linia activă în admin → Linii de start (doar cont de director de cursă).
--- Succes afișat DOAR după confirmarea serverului; aplicațiile piloților o primesc la următoarea sincronizare.
function app:sendToSite()
  if not self.last then return end
  local c = self.client
  if not c:paired() or not c:baseUrl() then self.message = { ok = false, text = 'Conectează mai întâi aplicația la site (⚙ Setări).' }; return end
  local sent = c:action('start_line', { line = self.last.entry, reason = 'trimis din DRS Organizer' }, function (ok, r)
    if ok then
      self.message = { ok = true, text = string.format('Linia „%s” este pe site (versiunea %s).', tostring(r.id), tostring(r.version)) }
    else
      self.message = { ok = false, text = 'Linia NU a fost salvată pe site: ' .. tostring(c.feedback and c.feedback.text or 'eroare') }
    end
  end)
  if sent then self.message = { ok = true, text = 'Se trimite linia pe site…' } end
end

app.client = Client.new({ storage = storage, now = now, json = JSON, appVersion = 'organizer-' .. ORGANIZER_VERSION, cspBuild = app.cspBuild, mode = 'safety' })
app.client.statusProvider = function () return { mode = 'safety', track = app.track.id } end

-- ───────────────────────── Ciclu de viață ─────────────────────────

loadHistory()

function script.update(dt)
  local t = now()
  app.sample = CarProbe.sample()
  local suspended = sim.isReplayActive or sim.isPaused or sim.isInMainMenu
  if app.last then
    app.result = app.tracker:evaluate(app.sample, app.last.cfg, t, { suspended = suspended })
  end
  if app.capture then
    local s = app.sample
    local p, kind
    if s then p, kind = A.referencePoint(s) end
    if p then table.insert(app.capture.samples, { point = p, look = s.look, speedKmh = s.speedKmh, reference = kind }) end
    if t >= app.capture.untilT then
      local cap = app.capture
      app.capture = nil
      local res, err = Cal.average(cap.samples)
      if res then accept({ p0 = res.p0, forward = res.forward, width_m = C.DEFAULT_LINE_WIDTH_M }, 'manual_capture', res)
      else app.message = { ok = false, text = 'Captură refuzată: ' .. tostring(err) } end
    end
  end
  app.client:update()
end

-- ───────────────────────── Fereastra „Coordonate start” ─────────────────────────

local RED, YELLOW, GREEN = rgbm(0.81, 0.13, 0.16, 1), rgbm(0.98, 0.82, 0.07, 1), rgbm(0.30, 0.80, 0.45, 1)

function script.windowCoords(dt)
  ui.text(string.format('Traseu: %s   Layout: %s', app.track.id ~= '' and app.track.id or '—', app.track.layout ~= '' and app.track.layout or '—'))
  local s = app.sample
  local p, kind
  if s then p, kind = A.referencePoint(s) end
  if p then
    ui.text('Roți față (' .. tostring(kind) .. '): ' .. X.vecText(p))
    ui.text(string.format('Orientare: %.1f°   Viteză: %.1f km/h', X.headingDeg(V.flat(s.look)), s.speedKmh or 0))
    if kind == 'bumper' then ui.textColored('Roțile nu sunt citite: captura va fi refuzată.', RED) end
  else
    ui.textColored('Mașina nu este disponibilă.', YELLOW)
  end

  ui.separator()
  ui.text('Ruta capturii:')
  ui.sameLine()
  for _, r in ipairs({ 'urcare', 'invers', 'alt' }) do
    if ui.radioButton(routeLabel(r) .. '##route' .. r, storage.route == r) then storage.route = r end
    ui.sameLine()
  end
  ui.newLine()
  ui.textWrapped('Oprește mașina dreaptă, cu ROȚILE DIN FAȚĂ EXACT PE LINIA DE START, apoi apasă „Capturează”. Captura durează 1 s.')
  if app.capture then
    ui.text(string.format('Captură în curs… %d eșantioane', #app.capture.samples))
  else
    if ui.button('Capturează linia (roți față pe linie)') then app:startCapture() end
    ui.sameLine()
    if ui.button('Din nodurile traseului') then app:fromTrackNodes() end
  end
  if app.message then ui.textColored(app.message.text, app.message.ok and GREEN or RED) end

  ui.separator()
  local last = app.last
  if not last then
    ui.textColored('Nicio captură activă.', YELLOW)
  else
    ui.text('Captura activă: ' .. last.entry.id)
    ui.text(X.summary(last.capture))
    local r = app.result
    if r and r.measure then
      local col = r.state == A.State.ALIGNED and GREEN or YELLOW
      ui.textColored(string.format('Verificare aliniere: %s · d = %+.1f cm față de țintă · lateral %.2f m', tostring(r.state), r.measure.d * 100, r.measure.lateral or 0), col)
    end
    if ui.button('Copiază pentru ACSM (warm_tyres)') then app:copy('acsm') end
    ui.sameLine()
    if ui.button('Copiază JSON pentru site') then app:copy('json') end
    ui.sameLine()
    if ui.button(app.client.actionInFlight == 'start_line' and 'Se trimite…' or 'Trimite pe site') and not app.client.actionInFlight then app:sendToSite() end
    ui.pushFont(ui.Font.Monospace)
    ui.textWrapped(X.acsmBlock(last.capture, { scriptUrl = storage.scriptUrl, stopRadius = storage.stopRadius, tempOffset = storage.tempOffset }))
    ui.popFont()
  end

  ui.separator()
  if ui.checkbox('Desenează linia capturată în lume', storage.draw3D) then storage.draw3D = not storage.draw3D end
  if #app.history > 0 then
    ui.treeNode(string.format('Istoric capturi (%d)###history', #app.history), function ()
      for i, h in ipairs(app.history) do
        if i > 15 then break end
        ui.text(string.format('%s · %s · %s', tostring(h.at), tostring(h.id), h.spread_cm and (h.spread_cm .. ' cm') or tostring(h.source)))
        ui.sameLine()
        if ui.button('Folosește##h' .. i) then app:restore(h) end
      end
    end)
  end
end

-- ───────────────────────── Fereastra „Safety Car” ─────────────────────────

local function scContext(lv)
  local title = app.track.name ~= '' and app.track.name or app.track.id
  return { title = title, subtitle = 'ORGANIZATOR · SAFETY CAR · LIVE', rc = { label = lv.connection or 'NECONECTAT', ok = lv.connection == 'CONECTAT' } }
end

function script.windowSafety(dt)
  local t = now()
  local c = app.client
  local lv = LiveModel.driver({ paired = c:paired(), pairing = c.pairing, state = c.state, stateAt = c.stateAt, now = t, sync = c.timeSync, error = c.lastError, aligned = false })
  local st = c.state
  local action = UiSafetyLive.draw({ ctx = scContext(lv), state = st, fresh = lv.connection == 'CONECTAT', actionInFlight = c.actionInFlight,
    feedback = c.feedback, armedUntil = app.armedUntil, now = t })
  if not action then return end
  if action == 'arm' then app.armedUntil = t + UiSafetyLive.ARM_S; return end
  app.armedUntil = nil
  local ctx = st and st.context
  if not ctx then return end
  if action == 'confirm' then
    c:action('confirm', { event_id = ctx.event_id, class_id = ctx.class_id, run = ctx.run,
      request_id = string.format('org-%d-%d-%d-%d', ctx.event_id, ctx.class_id, ctx.run, math.floor(t * 1000)) }, function (ok, r)
      if ok then
        local n = 0
        for _, v in pairs(r.procedure and r.procedure.counts or {}) do n = n + v end
        c.feedback = { ok = true, text = r.already_confirmed and 'Sosirea era deja confirmată (server).' or string.format('Confirmat de server: %d starturi programate.', n) }
      end
    end)
  elseif action == 'hold' then
    c:action('hold', { event_id = ctx.event_id, class_id = ctx.class_id, reason = 'HOLD din DRS Organizer' }, function (ok)
      if ok then c.feedback = { ok = true, text = 'HOLD activ (confirmat de server).' } end
    end)
  elseif action == 'resume' then
    c:action('resume', { event_id = ctx.event_id, class_id = ctx.class_id }, function (ok)
      if ok then c.feedback = { ok = true, text = 'Procedura a fost reluată (confirmat de server).' } end
    end)
  end
end

-- ───────────────────────── Setări (conexiune, clasă, valori ACSM) ─────────────────────────

function script.windowSettings(dt)
  ui.header('Conectare Race Control')
  local url, changed = ui.inputText('Adresa serverului DRS', storage.serverUrl or '')
  if changed then storage.serverUrl = url end
  if storage.serverUrl ~= '' and not Client.validBaseUrl(storage.serverUrl) then
    ui.textColored('Adresa trebuie să înceapă cu https:// (http doar pentru localhost / rețea locală).', RED)
  end
  local c = app.client
  if c.pairing then
    if c.pairing.userCode then
      ui.text('Cod de împerechere:')
      ui.pushFont(ui.Font.Huge); ui.text(c.pairing.userCode); ui.popFont()
      ui.textWrapped('Pe site, cu contul de organizator: Profilul meu → DRS Starter → introdu codul.')
    else
      ui.text('Se cere un cod…')
    end
    if ui.button('Anulează împerecherea') then c:cancelPairing() end
  elseif c:paired() then
    ui.text('Dispozitiv împerecheat.' .. (c.state and c.state.identity and c.state.identity.driver and (' Cont: ' .. c.state.identity.driver) or ''))
    if c.state and c.state.identity and not c.state.identity.can_confirm_finish then
      ui.textColored('Contul nu are rolul Safety Car / director de cursă.', YELLOW)
    end
    if ui.button('Deconectează acest dispozitiv') then c:unpair() end
  else
    local name, ch = ui.inputText('Numele dispozitivului', storage.deviceName or 'DRS Organizer')
    if ch then storage.deviceName = name end
    if ui.button('Împerechează') then c:startPairing(storage.deviceName) end
  end
  if c.feedback and c.feedback.text then ui.textWrapped(c.feedback.text) end
  if c.lastError then ui.textColored('Ultima eroare: ' .. c.lastError, YELLOW) end
  if c.state and type(c.state.choices) == 'table' then
    ui.text('Clasa pentru Safety Car:')
    for _, ch2 in ipairs(c.state.choices) do
      local sel = tonumber(storage.scEventId) == ch2.event_id and tonumber(storage.scClassId) == ch2.class_id
      if ui.radioButton(string.format('%s (manșa %s, %s)##sc%d_%d', tostring(ch2.label), tostring(ch2.run), tostring(ch2.phase), ch2.event_id, ch2.class_id), sel) then
        storage.scEventId, storage.scClassId = ch2.event_id, ch2.class_id
        c:pollNow()
      end
    end
  end

  ui.separator()
  ui.header('Valori pentru blocul ACSM (warm_tyres)')
  local su, sch = ui.inputText('Link script (versiune fixă)', storage.scriptUrl or '')
  if sch then storage.scriptUrl = su end
  local r = ui.slider('##stopRadius', storage.stopRadius, 5, 100, 'Oprire încălzire la %.0f m de start')
  if r ~= storage.stopRadius then storage.stopRadius = math.floor(r + 0.5) end
  local o = ui.slider('##tempOffset', storage.tempOffset, -20, 20, 'Abatere temperatură %.0f °C')
  if o ~= storage.tempOffset then storage.tempOffset = math.floor(o + 0.5) end
  ui.separator()
  ui.text(string.format('DRS Organizer %s · CSP build %s (aprobat %d)', ORGANIZER_VERSION, tostring(app.cspBuild), C.APPROVED_CSP_BUILD))
end

function script.draw3D()
  if storage.draw3D and app.last then World.draw(app.last.cfg, app.result) end
end
