-- Overlay Safety Car Mode (Faza 1: LOCAL DEMO MODE). Acțiunile merg doar la adaptorul de procedură local.
local Style = require('src/style')
local U = require('src/ui_common')
local P = require('src/procedure_local')
local Col, F = Style.color, Style.font

local M = {}
M.BASE_W, M.BASE_H = 760, 346

local phaseText = {
  [P.Phase.SC_ON_COURSE] = { 'SAFETY CAR PE TRASEU', 'Confirmă când ajungi în zona de finish', Col.orange },
  [P.Phase.SC_AT_FINISH] = { 'SOSIRE CONFIRMATĂ (LOCAL)', 'Fără Race Control: nicio oră de start nu a fost creată', Col.ok },
  [P.Phase.HOLD] = { 'HOLD ACTIV (LOCAL)', 'Procedura demonstrativă este suspendată', Col.bad },
}

--- model = {ctx, procedure (adaptor), feedback = {text, ok, at}, now}
--- Returnează acțiunea apăsată: 'confirm' | 'hold' | 'release' | 'reset' | nil
function M.draw(model)
  local ws = ui.windowSize()
  U.setScale(ws.x / M.BASE_W)
  local W = M.BASE_W
  local snap = model.procedure:snapshot()
  local action

  U.topBar(W, model.ctx)
  -- Banda LOCAL DEMO MODE, vizibilă permanent.
  U.rect(0, 58, W, 30, Col.warn, Style.radius.sm)
  U.textBox('LOCAL DEMO MODE · FĂRĂ RACE CONTROL · NICIO ACȚIUNE OFICIALĂ', 16, 0, 58, W, 30, Col.black)

  local p = phaseText[snap.phase] or { snap.phase, '', Col.gray }
  U.panel(0, 96, 370, 140)
  U.text('SAFETY CAR · STARE PROCEDURĂ', 14, 12, 104, Col.white)
  U.text(p[1], 26, 12, 126, p[3])
  U.text(p[2], 12, 12, 162, Col.grayLight, F.body)
  if snap.confirmedAt then
    U.text(string.format('Confirmat local la %s', os.date('%H:%M:%S', model.wallAtConfirm or os.time())), 12, 12, 184, Col.gray, F.body)
  end
  if model.feedback and model.feedback.text then
    U.text(model.feedback.text, 12, 12, 208, model.feedback.ok and Col.white or Col.warn, F.bodyBold)
  end

  U.panel(380, 96, 380, 140)
  local canConfirm = snap.phase == P.Phase.SC_ON_COURSE
  if U.button('##confirm', 'CONFIRMĂ SOSIREA LA FINISH', 392, 108, 356, 52, 'primary', canConfirm) then action = 'confirm' end
  if snap.phase == P.Phase.HOLD then
    if U.button('##release', 'RELUARE', 392, 170, 172, 52, 'secondary') then action = 'release' end
  else
    if U.button('##hold', 'HOLD', 392, 170, 172, 52, 'danger') then action = 'hold' end
  end
  if U.button('##reset', 'RESET DEMO', 576, 170, 172, 52, 'secondary') then action = 'reset' end

  U.panel(0, 244, W, 102)
  U.text('JURNAL LOCAL (nu este trimis nicăieri)', 13, 12, 250, Col.white)
  for i = 1, math.min(3, #snap.log) do
    local e = snap.log[i]
    U.text(string.format('+%.0f s  %s', e.t - (snap.log[#snap.log].t or e.t), e.text), 12, 12, 250 + i * 22, Col.grayLight, F.body)
  end
  ui.setCursor(U.v(0, M.BASE_H))
  ui.dummy(vec2(1, 1))
  return action
end

return M
