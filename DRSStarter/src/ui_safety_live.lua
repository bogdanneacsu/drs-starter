-- Overlay Safety Car Mode LIVE (Faza 2). Acțiunile merg la Race Control (Laravel), care autentifică,
-- autorizează și decide. Succesul se afișează DOAR după confirmarea serverului.
local Style = require('src/style')
local U = require('src/ui_common')
local Col, F = Style.color, Style.font

local M = {}
M.BASE_W, M.BASE_H = 760, 346
M.ARM_S = 4 -- confirmarea sosirii cere două apăsări în 4 s (acțiune ireversibilă: generează programul)

local BLOCKERS = {
  run_not_active = 'Manșa nu este marcată ca activă în Race Control.',
  starter_lead_not_configured = 'Directorul nu a setat timpul până la primul start.',
  queue_empty = 'Coada de start este goală.',
  not_authorized = 'Contul nu are rolul Safety Car / director de cursă.',
}

local function clock(ms) return ms and os.date('%H:%M:%S', math.floor(ms / 1000)) or '—' end

--- model = {ctx, state, fresh, actionInFlight, feedback, armedUntil, now}
--- Returnează 'arm' | 'confirm' | 'hold' | 'resume' | nil
function M.draw(model)
  local ws = ui.windowSize()
  U.setScale(ws.x / M.BASE_W)
  local W = M.BASE_W
  local st, fresh = model.state, model.fresh
  local action

  U.topBar(W, model.ctx)
  U.rect(0, 58, W, 30, fresh and Col.okSoft or Col.badSoft, Style.radius.sm)
  U.textBox(fresh and 'LIVE · RACE CONTROL · ACȚIUNILE SUNT OFICIALE' or 'FĂRĂ CONEXIUNE VALIDĂ · ACȚIUNILE NU POT FI TRIMISE', 16, 0, 58, W, 30, Col.white)

  local proc = st and st.procedure
  local ctx = st and st.context
  U.panel(0, 96, 370, 140)
  U.text('SAFETY CAR · STARE PROCEDURĂ', 14, 12, 104, Col.white)
  local title, sub, col
  if not st then title, sub, col = 'SE CONECTEAZĂ', '', Col.gray
  elseif not ctx then title, sub, col = 'ALEGE CLASA', 'Setări → Conectare Race Control → clasa', Col.warn
  elseif not proc then title, sub, col = 'SAFETY CAR PE TRASEU', 'Confirmă când ajungi la finish', Col.orange
  elseif proc.status == 'hold' then title, sub, col = 'HOLD ACTIV', 'Starturile sunt oprite pentru toată clasa', Col.bad
  elseif proc.status == 'running' then title, sub, col = 'STARTURI ÎN DESFĂȘURARE', string.format('Program confirmat la %s', clock(proc.confirmed_at_ms)), Col.ok
  else title, sub, col = 'PROCEDURĂ ÎNCHEIATĂ', '', Col.gray end
  U.text(title, 24, 12, 126, col)
  U.text(sub, 12, 12, 158, Col.grayLight, F.body)
  if ctx then U.text(string.format('%s · %s · manșa %d', ctx.event, ctx.class, ctx.run), 12, 12, 178, Col.gray, F.body) end
  local fb = model.feedback
  if fb and fb.text then U.text(fb.text, 12, 12, 200, fb.ok and Col.white or Col.warn, F.bodyBold)
  elseif st and st.blockers and #st.blockers > 0 and not proc then U.text(BLOCKERS[st.blockers[1]] or st.blockers[1], 12, 12, 200, Col.warn, F.bodyBold) end

  U.panel(380, 96, 380, 140)
  local busy = model.actionInFlight
  local canConfirm = fresh and st and st.can_confirm_now and not busy
  local armed = model.armedUntil and model.now < model.armedUntil
  local label = busy == 'confirm' and 'SE TRIMITE…' or (armed and 'APASĂ DIN NOU: CONFIRM' or 'CONFIRMĂ SOSIREA LA FINISH')
  if U.button('##confirm', label, 392, 108, 356, 52, 'primary', canConfirm and true or false) then action = armed and 'confirm' or 'arm' end
  local canHold = fresh and proc and st.identity and st.identity.can_hold and not busy
  if proc and proc.status == 'hold' then
    if U.button('##resume', 'RELUARE', 392, 170, 356, 52, 'secondary', canHold and true or false) then action = 'resume' end
  else
    if U.button('##hold', 'HOLD', 392, 170, 356, 52, 'danger', (canHold and proc and proc.status == 'running') and true or false) then action = 'hold' end
  end

  U.panel(0, 244, W, 102)
  U.text('URMĂTORII LA START (ora serverului)', 13, 12, 250, Col.white)
  local q = st and st.queue or {}
  for i = 1, math.min(3, #q) do
    local e = q[i]
    local status = e.status == 'review' and 'ÎN ANALIZĂ' or (e.attempt == 2 and 'A DOUA ȘANSĂ' or '')
    U.text(string.format('%s  #%s %s  fereastră %s–%s  %s', clock(e.scheduled_at_ms), tostring(e.race_number or '—'), e.driver or '',
      clock(e.window_opens_at_ms), clock(e.window_closes_at_ms), status), 12, 12, 250 + i * 22, Col.grayLight, F.body)
  end
  ui.setCursor(U.v(0, M.BASE_H))
  ui.dummy(vec2(1, 1))
  return action
end

return M
