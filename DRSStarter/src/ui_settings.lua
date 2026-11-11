-- Fereastra de setări (butonul ⚙ al ferestrei principale): conectare, countdown local, ruta, debug.
-- Fără calibrare și fără toleranțe: linia și zona verde le stabilește organizatorul pe site (LIVE).
-- Widget-uri ImGui standard, ca în aplicațiile oficiale CSP.
local A = require('src/alignment')
local CP = require('src/car_probe')
local C = require('src/config')

local M = {}

---@param app table obiectul aplicației din DRSStarter.lua
function M.draw(app)
  local st = app.storage

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
  if st.source ~= 'live' then
    ui.separator()
    ui.header('Countdown local de test (nu este programul oficial)')
    if app.countdown.paused then
      if ui.button('Reia') then app:countdownResume() end
    else
      if ui.button('Pauză') then app:countdownPause() end
    end
    ui.sameLine()
    if ui.button('Repornește de la ' .. C.LOCAL_COUNTDOWN_S) then app:countdownReset() end
  end

  ui.separator()
  ui.header('Linia de start')
  ui.text(string.format('Traseu: %s   Layout: %s', app.track.id, app.track.layout ~= '' and app.track.layout or '—'))
  ui.textWrapped(st.source == 'live' and 'Linia și zona verde vin de la Race Control (stabilite de organizator). Nu se pot modifica din aplicație.'
    or 'Demo local: liniile livrate cu aplicația (data/starts.json). În LIVE se folosesc doar liniile de pe site.')
  local list = app.trackConfigs
  if #list == 0 then
    ui.textColored('Nicio linie de start pentru acest traseu/layout.', rgbm(0.98, 0.82, 0.07, 1))
  else
    ui.text('Rute disponibile (ruta activă):')
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

  local cfg = app.activeCfg
  if cfg then
    local t, s = cfg.target, cfg.stationary
    ui.text(string.format('Zona verde: țintă %.0f cm, −%.1f / +%.1f cm, orientare max. %.0f°, oprire < %.1f km/h timp de %.1f s',
      t.offset_m * 100, t.tol_back_m * 100, t.tol_fwd_m * 100, t.max_heading_deg, s.max_speed_kmh, s.hold_s))
  end

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

return M
