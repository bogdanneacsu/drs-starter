-- Overlay Driver Mode, după macheta organizatorului. Doar desen: starea vine din DRSStarter.lua.
local Style = require('src/style')
local U = require('src/ui_common')
local A = require('src/alignment')
local Col, F = Style.color, Style.font
local S = A.State

local M = {}
M.BASE_W, M.BASE_H = 760, 346   -- fără panoul „Exemplu poziție”
M.EXAMPLE_H = 100                -- înălțimea suplimentară a panoului „Exemplu poziție” (8 spațiu + 92 panou)
function M.height(showExample) return M.BASE_H + (showExample and M.EXAMPLE_H or 0) end

local function cm(m) return string.format('%.0f cm', math.abs(m) * 100) end
local function meters(m) return string.format('%.2f m', math.abs(m)) end

--- Titlu, subtitlu, culoare pentru fiecare stare de aliniere.
local function headline(r, cfg)
  local st, m = r.state, r.measure
  if st == S.NO_CONFIG then return 'TRASEU NECALIBRAT', 'Deschide setările aplicației pentru calibrarea liniei de start', Col.warn end
  if st == S.INVALID_CONFIG then return 'CONFIGURAȚIE INVALIDĂ', tostring(r.error or ''), Col.bad end
  if st == S.NO_CAR then return 'DATE MAȘINĂ INDISPONIBILE', 'Poziția roților nu poate fi citită', Col.bad end
  if st == S.SUSPENDED then return 'PAUZĂ / REPLAY', 'Evaluarea alinierii este suspendată', Col.gray end
  if st == S.FAR then return 'DEPARTE DE START', 'Linia de start este la ' .. string.format('%.0f m', m.distanceToLine), Col.gray end
  if st == S.WRONG_DIRECTION then return 'DIRECȚIE GREȘITĂ', 'Mașina este orientată invers față de rută', Col.bad end
  if st == S.APPROACHING then return 'APROPIE-TE DE START', 'Mai ai ' .. string.format('%.1f m', -m.d) .. ' până la țintă', Col.orange end
  if st == S.OFF_LANE then return 'ÎN AFARA CULOARULUI', 'Centrează mașina pe linia de start', Col.bad end
  if st == S.TOO_FAR_BACK then return 'ÎNAINTEAZĂ', 'Mai ai ' .. cm(m.d) .. ' până la țintă', Col.warn end
  if st == S.TOO_FAR_FORWARD then return 'DĂ ÎNAPOI', 'Ai depășit ținta cu ' .. cm(m.d), Col.bad end
  if st == S.BAD_HEADING then return 'ÎNDREAPTĂ MAȘINA', string.format('Unghi %.1f° (maxim %.0f°)', m.heading, cfg.target.max_heading_deg), Col.warn end
  if st == S.STEER_NOT_STRAIGHT then return 'ÎNDREAPTĂ ROȚILE', 'Volanul trebuie să fie drept', Col.warn end
  if st == S.APPROX_REFERENCE then return 'REFERINȚĂ APROXIMATIVĂ', 'Roțile nu sunt disponibile; alinierea nu poate fi confirmată', Col.warn end
  if st == S.MOVING then return 'OPREȘTE MAȘINA', 'Roțile din față sunt în zona verde', Col.warn end
  if st == S.STABILIZING then return 'MENȚINE POZIȚIA', string.format('Stabilizare %.1f s', math.max(0, cfg.stationary.hold_s - (r.stableFor or 0))), Col.orange end
  if st == S.ALIGNED then return 'POZIȚIE CORECTĂ', 'Roțile din față în zona verde', Col.ok end
  return tostring(st), '', Col.gray
end

--- Cele trei verificări din panoul „Stare aliniere”.
local function checks(r, cfg, sample)
  local m = r.measure
  if not m or not cfg then return false, false, false end
  local t = cfg.target
  local inZone = m.d >= -t.tol_back_m and m.d <= t.tol_fwd_m and math.abs(m.lateral) <= t.max_lateral_m
  local still = sample and sample.speedKmh <= cfg.stationary.max_speed_kmh
  local dirOk = m.heading <= t.max_heading_deg
  return inZone, still, dirOk
end

local function guidePanel(x, y, w, h, r, cfg)
  U.panel(x, y, w, h)
  U.text('GHID DE ALINIERE', 15, x + 12, y + 8, Col.white)
  local cx, top, bottom = x + w / 2, y + 32, y + h - 26
  local pxPerM = 110                                  -- scară vedere de sus: 1 m = 110 px (de bază)
  local y0 = top + 46                                 -- poziția țintei pe ecran
  for i = 0, 5 do U.rect(cx - 62, top + i * 19, 2, 10, Col.grayLight); U.rect(cx + 60, top + i * 19, 2, 10, Col.grayLight) end
  if cfg then
    local t = cfg.target
    local zTop, zBot = y0 - t.tol_fwd_m * pxPerM, y0 + t.tol_back_m * pxPerM
    U.rect(cx - 58, zTop, 116, zBot - zTop, Col.okSoft)
    U.outline(cx - 58, zTop, 116, zBot - zTop, Col.ok, 0, 2)
    local lineY = y0 + t.offset_m * pxPerM            -- offset negativ → linia este înaintea țintei (mai sus)
    if lineY > top - 6 then U.rect(cx - 64, lineY - 1, 128, 3, Col.white) end
    U.text('LINIE', 10, cx + 66, math.max(top - 6, lineY - 7), Col.gray)
  end
  -- Mașina (vedere de sus): axa față la y0 − d, limitată la panou.
  if r.measure then
    local fy = math.max(top, math.min(bottom - 24, y0 - r.measure.d * pxPerM))
    local lat = math.max(-40, math.min(40, r.measure.lateral * 25))
    local carCol = r.state == A.State.ALIGNED and Col.ok or (r.state == A.State.TOO_FAR_FORWARD and Col.bad or Col.grayLight)
    local len = math.max(16, math.min(60, bottom - fy))
    U.rect(cx - 18 + lat, fy - 8, 36, len + 8, carCol, 6)
    U.rect(cx - 24 + lat, fy - 6, 6, 12, Col.black, 2)
    U.rect(cx + 18 + lat, fy - 6, 6, 12, Col.black, 2)
    U.rect(cx - 24 + lat, fy - 1, 48, 2, Col.orange)  -- axa față
  end
  U.textBox('Roțile din față în zona verde', 12, x + 6, y + h - 24, w - 12, 20, Col.gray, F.body)
end

local function countdownPanel(x, y, w, h, cd, goFlash)
  local edge = goFlash and Col.ok or Col.orange
  U.panel(x, y, w, h, Col.panel, edge)
  U.textBox(goFlash and 'START (DEMO)' or (cd.paused and 'PAUZĂ' or 'START ÎN'), 18, x, y + 8, w, 24, Col.white)
  if goFlash then
    U.textBox('GO', 84, x, y + 30, w, 90, Col.ok, F.number)
  else
    U.textBox(tostring(cd.display), 84, x, y + 30, w, 90, Col.orange, F.number)
  end
  U.textBox(goFlash and '0 · DEMO' or 'SECUNDE', 16, x, y + 116, w, 20, Col.white)
  U.rect(x + 10, y + h - 28, w - 20, 20, Col.warn, Style.radius.sm)
  U.textBox('DEMO LOCAL · NU E START OFICIAL', 12, x + 10, y + h - 28, w - 20, 20, Col.black)
end

local function clock(ms) return ms and os.date('%H:%M:%S', math.floor(ms / 1000)) or '—' end

local SHORT = {
  UNPAIRED = 'NEÎMPERECHEAT', CONNECTING = 'SE CONECTEAZĂ', OFFLINE = 'FĂRĂ CONEXIUNE', NO_CONTEXT = 'FĂRĂ ÎNSCRIERE',
  NOT_IN_RUN = 'NU EȘTI ÎN COADĂ', WAITING_SAFETY_CAR = 'AȘTEAPTĂ PROGRAMUL', WINDOW_CLOSED = 'FEREASTRĂ ÎNCHISĂ',
  MISSED_RETRY = 'A DOUA ȘANSĂ', IN_REVIEW = 'ÎN ANALIZĂ', DNS_PENDING = 'DECIDE DIRECTORUL', DNS = 'DNS',
  RACE_CONTROL = 'AȘTEAPTĂ RC', CANCELLED = 'ANULAT', PROCEDURE_COMPLETED = 'ÎNCHEIAT',
}

--- Countdown LIVE: doar din ora serverului (model din src/live/live_model.lua). Fără date proaspete → fără GO.
local function liveCountdownPanel(x, y, w, h, lv)
  local ph = lv.phase
  local open, go = ph == 'WINDOW_OPEN', lv.go == true
  local bad = ph == 'HOLD' or ph == 'STALE' or ph == 'OFFLINE' or ph == 'WINDOW_CLOSED' or ph == 'DNS' or ph == 'DNS_PENDING' or ph == 'MISSED_RETRY'
  U.panel(x, y, w, h, Col.panel, go and Col.ok or (bad and Col.bad or Col.orange))
  local title, big, bigCol, sub
  if (ph == 'SCHEDULED' or ph == 'MISSED_RETRY') and lv.countdownS then
    title, big, bigCol = ph == 'MISSED_RETRY' and 'A DOUA ȘANSĂ ÎN' or 'FEREASTRA ÎN', tostring(lv.countdownS), ph == 'MISSED_RETRY' and Col.warn or Col.orange
    sub = 'START ' .. clock(lv.slot and lv.slot.scheduled_at_ms)
  elseif open and go then
    title, big, bigCol, sub = 'POȚI PLECA', 'GO', Col.ok, string.format('SE ÎNCHIDE ÎN %d s', lv.countdownS or 0)
  elseif open then
    title, big, bigCol, sub = 'FEREASTRĂ DESCHISĂ', tostring(lv.countdownS), Col.warn, 'ALINIAZĂ-TE ÎNTÂI'
  elseif ph == 'HOLD' or ph == 'STALE' then
    title, big, bigCol, sub = ph == 'HOLD' and 'STARTURI OPRITE' or 'CONEXIUNE PIERDUTĂ', 'HOLD', Col.bad, 'NU PLECA'
  elseif ph == 'DEPARTED' then
    title, big, bigCol, sub = 'PLECARE', 'OK', Col.ok, 'RAPORT TRIMIS'
  else
    title, big, bigCol, sub = 'START', '—', bad and Col.bad or Col.gray, SHORT[ph] or ph
  end
  U.textBox(title, 18, x, y + 8, w, 24, Col.white)
  U.textBox(big, big == 'HOLD' and 56 or 84, x, y + 30, w, 90, bigCol, F.number)
  U.textBox(sub, 14, x, y + 116, w, 20, Col.white)
  local live = lv.connection == 'CONECTAT'
  U.rect(x + 10, y + h - 28, w - 20, 20, live and Col.okSoft or Col.badSoft, Style.radius.sm)
  U.textBox(live and 'LIVE · ORA SERVERULUI' or 'FĂRĂ AUTORIZARE VALIDĂ', 12, x + 10, y + h - 28, w - 20, 20, Col.white)
end

local function distancePanel(x, y, w, h, r, color)
  U.panel(x, y, w, h)
  U.text('DISTANȚĂ PÂNĂ LA ȚINTĂ', 14, x + 12, y + 8, Col.white)
  local m = r.measure
  local value, hint = '—', ''
  if m and r.state ~= S.FAR then
    value = meters(m.d)
    hint = m.d < 0 and 'ÎNAINTE' or (m.d > 0 and 'ÎNAPOI' or '')
    if r.state == S.ALIGNED then hint = 'POZIȚIE CORECTĂ' end
  elseif m then
    value = string.format('%.0f m', m.distanceToLine)
  end
  U.text(value, 40, x + 12, y + 26, color, F.number)
  U.textBox(hint, 16, x + w - 160, y + 40, 148, 24, Col.white, F.display, ui.Alignment.End)
  if r.state == S.ALIGNED then U.check(x + w - 26, y + 18, 11, true) end
end

local function statusPanel(x, y, w, h, r, cfg, sample, title, color)
  U.panel(x, y, w, h)
  U.text('STARE ALINIERE', 14, x + 12, y + 8, Col.white)
  U.text(title, 20, x + 12, y + 32, color)
  local a, b, c = checks(r, cfg, sample)
  local items = { { 'Roți față în zonă', a }, { 'Poziție staționară', b }, { 'Direcție corectă', c } }
  for i, it in ipairs(items) do
    local iy = y + 10 + (i - 1) * 25
    U.check(x + 192, iy + 9, 8, it[2] and true or false)
    U.text(it[1], 12, x + 206, iy + 2, Col.white, F.body)
  end
end

local function warningPanel(x, y, w, h, warn)
  local isBad = warn.level == 'bad'
  U.panel(x, y, w, h, isBad and Col.badSoft or Col.panel, isBad and Col.bad or Col.edge)
  U.text(warn.title, 15, x + 12, y + 8, isBad and Col.white or (warn.level == 'warn' and Col.warn or Col.orange))
  U.text(warn.text, 11, x + 12, y + 30, Col.white, F.body)
end

local function progressPanel(x, y, w, h, step, live)
  U.panel(x, y, w, h)
  U.text(live and 'PROGRES START' or 'PROGRES START · DEMO', 13, x + 12, y + 6, Col.white)
  local labels = { 'Aliniere', 'Countdown', 'Start', 'Pe traseu' }
  local sx, ex, cy = x + 50, x + w - 50, y + 32
  U.rect(sx, cy - 1, ex - sx, 2, Col.edge)
  for i, l in ipairs(labels) do
    local px = sx + (ex - sx) * (i - 1) / 3
    local done, active = i < step, i == step
    if done or active then ui.drawCircleFilled(U.v(px, cy), 7 * U.k, active and Col.ok or Col.okSoft, 20)
    else ui.drawCircle(U.v(px, cy), 7 * U.k, Col.gray, 20, 1.5) end
    U.textBox(l, 12, px - 40, cy + 8, 80, 16, (done or active) and Col.white or Col.gray, F.body)
  end
end

--- Panoul „Exemplu poziție” din machetă: trei cazuri statice, ilustrative (nu depind de mașina reală).
local EXAMPLES = {
  { 'PREA ÎN SPATE', 'Înaintează până în zona verde', false, 22 },
  { 'POZIȚIE CORECTĂ', 'Roțile din față în zona verde', true, 0 },
  { 'PREA ÎN FAȚĂ', 'Ai depășit ținta, dă înapoi', false, -24 },
}

local function exampleCard(x, y, w, h, title, text, ok, shift)
  U.panel(x, y, w, h, Col.panel, ok and Col.ok or Col.edge)
  -- Mini vedere de sus: linia albă, zona verde, mașina cu axa față deplasată cu `shift` px.
  local cx, zoneY = x + 46, y + 40
  U.rect(cx - 28, zoneY - 7, 56, 14, Col.okSoft)
  U.outline(cx - 28, zoneY - 7, 56, 14, Col.ok, 0, 1.5)
  U.rect(cx - 32, zoneY - 17, 64, 3, Col.white)
  local fy = zoneY + shift
  local carCol = ok and Col.ok or (shift < 0 and Col.bad or Col.grayLight)
  U.rect(cx - 12, fy - 5, 24, math.max(12, y + h - 6 - (fy - 5)), carCol, 4)
  U.rect(cx - 16, fy - 4, 4, 8, Col.black, 1)
  U.rect(cx + 12, fy - 4, 4, 8, Col.black, 1)
  U.rect(cx - 16, fy - 1, 32, 2, Col.orange)
  U.text(title, 18, x + 94, y + 18, ok and Col.ok or Col.bad)
  U.textBox(text, 11, x + 94, y + 46, w - 104, 30, Col.grayLight, F.body, ui.Alignment.Start, ui.Alignment.Start)
  U.check(x + w - 20, y + 20, 10, ok)
end

local function examplePanel(x, y, w, h)
  local gap = 6
  local cw = (w - 2 * gap) / 3
  for i, e in ipairs(EXAMPLES) do exampleCard(x + (i - 1) * (cw + gap), y, cw, h, e[1], e[2], e[3], e[4]) end
  U.rect(x + 10, y - 3, 96, 14, Col.panel, Style.radius.sm)
  U.text('EXEMPLU POZIȚIE', 11, x + 14, y - 2, Col.gray)
end

--- model = {ctx, result, cfg, sample, countdown, goFlash, progressStep, warning, showExample, live?}
--- `live` (Faza 2) = modelul din src/live/live_model.lua; absent = modul demo local din Faza 1.
function M.draw(model)
  local ws = ui.windowSize()
  local k = ws.x / M.BASE_W
  U.setScale(k)
  local W = M.BASE_W
  local r, cfg = model.result, model.cfg
  local title, subtitle, color = headline(r, cfg)

  U.topBar(W, model.ctx)
  U.panel(150, 58, 460, 46)
  U.textBox(r.state == S.ALIGNED and 'POZIȚIONAT LA LINIA DE START' or 'POZIȚIONEAZĂ-TE LA LINIA DE START', 20, 150, 60, 460, 24, Col.white)
  U.textBox(subtitle, 13, 150, 82, 460, 18, Col.grayLight, F.body)

  guidePanel(0, 112, 210, 170, r, cfg)
  if model.live then liveCountdownPanel(220, 112, 200, 170, model.live) else countdownPanel(220, 112, 200, 170, model.countdown, model.goFlash) end
  distancePanel(430, 112, 330, 76, r, color)
  statusPanel(430, 194, 330, 88, r, cfg, model.sample, title, color)
  warningPanel(0, 290, 370, 56, model.warning)
  progressPanel(380, 290, 380, 56, model.progressStep, model.live ~= nil)
  if model.showExample then examplePanel(0, M.BASE_H + 8, W, M.EXAMPLE_H - 8) end
  -- Rezervă înălțimea pentru ImGui (fereastra nu se taie).
  ui.setCursor(U.v(0, M.height(model.showExample)))
  ui.dummy(vec2(1, 1))
end

return M
