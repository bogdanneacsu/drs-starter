-- Fereastra de setări (butonul ⚙ al ferestrei principale): mod, countdown local, calibrare, debug.
-- Widget-uri ImGui standard, ca în aplicațiile oficiale CSP.
local A = require('src/alignment')
local CP = require('src/car_probe')
local C = require('src/config')

local M = {}

local ROUTES = { { 'urcare', 'Urcare (sens normal)' }, { 'invers', 'Sens invers' }, { 'alt', 'Alt start' } }

local function slider(label, value, min, max, fmt)
  return ui.slider(label, value, min, max, fmt)
end

---@param app table obiectul aplicației din DRSStarter.lua
function M.draw(app)
  local st = app.storage

  ui.header('Mod interfață')
  if ui.radioButton('Pilot (Driver Mode)', st.mode == 'driver') then st.mode = 'driver' end
  ui.sameLine()
  if ui.radioButton('Safety Car', st.mode == 'safety') then st.mode = 'safety' end

  ui.separator()
  ui.header('Conectare Race Control (Faza 2)')
  if ui.radioButton('Demo local (fără rețea)', st.source ~= 'live') then st.source = 'demo' end
  ui.sameLine()
  if ui.radioButton('LIVE (Race Control)', st.source == 'live') then st.source = 'live'; app.client:pollNow() end
  local url, changed = ui.inputText('Adresa serverului DRS', st.serverUrl or '')
  if changed then st.serverUrl = url end
  local Client = require('src/live/client')
  if st.serverUrl ~= '' and not Client.validBaseUrl(st.serverUrl) then
    ui.textColored('Adresa trebuie să înceapă cu https:// (http doar pentru localhost / rețea locală).', rgbm(0.81, 0.13, 0.16, 1))
  end
  local c = app.client
  if c.pairing then
    if c.pairing.userCode then
      ui.text('Cod de împerechere:')
      ui.pushFont(ui.Font.Huge)
      ui.text(c.pairing.userCode)
      ui.popFont()
      ui.textWrapped('Pe site: Profilul meu → DRS Starter → introdu codul. Aplicația se conectează singură după confirmare.')
    else
      ui.text('Se cere un cod…')
    end
    if ui.button('Anulează împerecherea') then c:cancelPairing() end
  elseif c:paired() then
    ui.text('Dispozitiv împerecheat.' .. (c.state and c.state.identity and c.state.identity.driver and (' Pilot: ' .. c.state.identity.driver) or ''))
    if ui.button('Deconectează acest dispozitiv') then c:unpair() end
  else
    local name, ch = ui.inputText('Numele dispozitivului', st.deviceName or 'DRS Starter')
    if ch then st.deviceName = name end
    if ui.button('Împerechează') then c:startPairing(st.deviceName) end
  end
  if c.feedback and c.feedback.text then ui.textWrapped(c.feedback.text) end
  if c.lastError then ui.textColored('Ultima eroare: ' .. c.lastError, rgbm(0.98, 0.82, 0.07, 1)) end
  if st.mode == 'safety' and c.state and type(c.state.choices) == 'table' then
    ui.text('Clasa pentru Safety Car:')
    for _, ch2 in ipairs(c.state.choices) do
      local sel = tonumber(st.scEventId) == ch2.event_id and tonumber(st.scClassId) == ch2.class_id
      if ui.radioButton(string.format('%s (manșa %s, %s)##sc%d_%d', tostring(ch2.label), tostring(ch2.run), tostring(ch2.phase), ch2.event_id, ch2.class_id), sel) then
        st.scEventId, st.scClassId = ch2.event_id, ch2.class_id
        c:pollNow()
      end
    end
  end

  ui.separator()
  ui.header('Countdown local de test (nu este programul oficial)')
  if app.countdown.paused then
    if ui.button('Reia') then app:countdownResume() end
  else
    if ui.button('Pauză') then app:countdownPause() end
  end
  ui.sameLine()
  if ui.button('Repornește de la ' .. C.LOCAL_COUNTDOWN_S) then app:countdownReset() end

  ui.separator()
  ui.header('Calibrare linie de start')
  ui.text(string.format('Traseu: %s   Layout: %s', app.track.id, app.track.layout ~= '' and app.track.layout or '—'))
  local list = app.trackConfigs
  if #list == 0 then
    ui.textColored('Nicio configurație pentru acest traseu/layout.', rgbm(0.98, 0.82, 0.07, 1))
  else
    ui.text('Configurații disponibile (ruta activă):')
    if ui.radioButton('Automat (cea mai apropiată, în sensul mașinii)', st.preferredId == '') then
      st.preferredId = ''
      app:reloadConfigs()
    end
    for _, c in ipairs(list) do
      if ui.radioButton(c.label .. '  [' .. c.id .. ']##' .. c.id, app.activeCfg and app.activeCfg.id == c.id) then
        st.preferredId = c.id
        app:reloadConfigs()
      end
    end
  end
  for _, e in ipairs(app.configErrors) do ui.textColored('Eroare: ' .. e, rgbm(0.81, 0.13, 0.16, 1)) end

  ui.text('Rută pentru captura nouă:')
  for _, r in ipairs(ROUTES) do
    if ui.radioButton(r[2] .. '##route' .. r[1], st.captureRoute == r[1]) then st.captureRoute = r[1] end
    ui.sameLine()
  end
  ui.newLine()

  ui.textWrapped('Captură manuală: oprește mașina dreaptă, cu ROȚILE DIN FAȚĂ EXACT PE LINIA DE START, apoi apasă butonul. ' ..
    'Aplicația mediază poziția timp de ' .. C.CAPTURE_DURATION_S .. ' s. Ținta implicită este la 30 cm în spatele liniei.')
  if app.capture then
    ui.text(string.format('Captură în curs… %d eșantioane', #app.capture.samples))
  else
    if ui.button('Capturează linia (roți față pe linie)') then app:startCapture() end
    ui.sameLine()
    if ui.button('Propune din nodurile traseului') then app:lineFromTrackNodes() end
  end
  if app.calibrationMessage then ui.textWrapped(app.calibrationMessage) end

  local cfg = app.activeCfg
  if cfg then
    ui.separator()
    ui.header('Parametri pentru „' .. cfg.label .. '” (valori inițiale, de calibrat în joc; se salvează local)')
    local t, s = cfg.target, cfg.stationary
    local d = app.draft
    d.offset_m = slider('##off', d.offset_m * 100, -150, 50, 'Țintă față de linie: %.0f cm') / 100
    d.tol_back_m = slider('##tb', d.tol_back_m * 100, 2, 50, 'Toleranță în spate: %.0f cm') / 100
    d.tol_fwd_m = slider('##tf', d.tol_fwd_m * 100, 2, 50, 'Toleranță în față: %.0f cm') / 100
    d.max_heading_deg = slider('##hd', d.max_heading_deg, 2, 20, 'Orientare maximă: %.0f°')
    d.max_steer_deg = slider('##sd', d.max_steer_deg, 0, 45, 'Bracare maximă: %.0f (0 = dezactivat)')
    d.width_m = slider('##w', d.width_m, 2, 20, 'Lățime linie: %.1f m')
    if ui.button('Aplică și salvează') then app:applyDraft() end
    ui.sameLine()
    if ui.button('Șterge această calibrare locală') then app:deleteLocal(cfg.id) end
    ui.text(string.format('Actual: țintă %.0f cm, ±%.0f/%.0f cm, %.0f°, oprire < %.1f km/h timp de %.1f s',
      t.offset_m * 100, t.tol_back_m * 100, t.tol_fwd_m * 100, t.max_heading_deg, s.max_speed_kmh, s.hold_s))
  end
  ui.text('Fișier local: data/starts.local.json')

  ui.separator()
  if ui.checkbox('Desenează zona de start în lume', st.draw3D) then st.draw3D = not st.draw3D end
  if ui.checkbox('Arată panoul „Exemplu poziție” (Driver Mode)', st.showExample) then st.showExample = not st.showExample end
  if ui.checkbox('Date de debug', st.debug) then st.debug = not st.debug end
  if st.debug then
    local r, smp = app.result, app.sample
    ui.text('CSP build: ' .. tostring(app.cspBuild) .. ' (aprobat ' .. C.APPROVED_CSP_BUILD .. ')   App ' .. C.APP_VERSION)
    ui.text('Stare: ' .. tostring(r and r.state) .. '   referință: ' .. tostring(r and r.reference))
    if r and r.measure then
      local m = r.measure
      ui.text(string.format('d=%.3f m  față de linie=%.3f m  lateral=%.3f m  unghi=%.2f°  dist=%.1f m',
        m.d, m.alongLine, m.lateral, m.heading, m.distanceToLine))
    end
    if smp then
      ui.text(string.format('viteză=%.2f km/h  steer=%s  ampatament≈%s', smp.speedKmh or -1, tostring(smp.steerDeg),
        tostring(CP.wheelbase(smp) and string.format('%.3f m', CP.wheelbase(smp)) or '—')))
      if smp.frontContact then
        local a, b = smp.frontContact[1], smp.frontContact[2]
        ui.text(string.format('FL=(%.3f, %.3f, %.3f)  FR=(%.3f, %.3f, %.3f)', a.x, a.y, a.z, b.x, b.y, b.z))
      end
    end
    if CP.lastError then ui.textColored('car_probe: ' .. CP.lastError, rgbm(0.81, 0.13, 0.16, 1)) end
    local ts = app.client.timeSync
    ui.text(string.format('Race Control: offset ceas %s ms (±%s ms), evenimente netrimise %d, versiune program %s',
      ts.offsetMs and string.format('%.0f', ts.offsetMs) or '—', ts:uncertaintyMs() and string.format('%.0f', ts:uncertaintyMs()) or '—',
      #app.client.pending, tostring(app.client.state and app.client.state.procedure and app.client.state.procedure.schedule_version or '—')))
  end
end

M.ROUTES = ROUTES
return M
