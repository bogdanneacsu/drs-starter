-- Model de afișare pentru modul LIVE (Faza 2), calculat din ultima stare validă primită de la Race Control.
-- Pur (fără API CSP): testabil. Reguli de siguranță:
--   • fereastra și autorizarea vin DOAR din timestampurile serverului; clientul nu extinde și nu inventează ferestre;
--   • dacă starea e mai veche decât `stale_after_ms` sau ceasul nu e sincronizat → CONEXIUNE PIERDUTĂ (tratat ca HOLD);
--   • GO / „POȚI PLECA” cere: stare proaspătă, procedură în desfășurare, slot programat, ora serverului în fereastră
--     și aliniere validă locală. Altfel nu se afișează niciodată.
local M = {}

M.DEFAULT_STALE_MS = 4000

local function num(v) return type(v) == 'number' and v == v and v or nil end

--- Validează forma unui slot venit de la server; nil dacă e inutilizabil.
function M.validSlot(s)
  if type(s) ~= 'table' then return nil end
  local opens, closes, at = num(s.window_opens_at_ms), num(s.window_closes_at_ms), num(s.scheduled_at_ms)
  if not opens or not closes or not at or opens >= closes or at < opens or at > closes then return nil end
  if type(s.status) ~= 'string' then return nil end
  return s
end

--- Validează un răspuns /sync. Returnează (state) sau (nil, motiv). Nu aruncă erori.
function M.validateState(st)
  if type(st) ~= 'table' then return nil, 'răspuns gol' end
  if st.schema ~= 1 then return nil, 'versiune de protocol necunoscută' end
  if not num(st.server_time_ms) or not num(st.server_received_ms) then return nil, 'lipsește ora serverului' end
  if st.procedure ~= nil and type(st.procedure) ~= 'table' then return nil, 'procedură invalidă' end
  if st.me ~= nil then
    if type(st.me) ~= 'table' then return nil, 'stare pilot invalidă' end
    if st.me.slot ~= nil then st.me.slot = M.validSlot(st.me.slot) end -- slot inutilizabil = fără autorizare
  end
  return st
end

local function ceilS(ms) return math.max(0, math.ceil(ms / 1000 - 1e-6)) end

---@param p {paired:boolean, pairing:table?, state:table?, stateAt:number?, now:number, sync:table, error:string?, aligned:boolean}
function M.driver(p)
  local out = { authorized = false, go = false, connection = 'NECONECTAT', live = true }
  if not p.paired then
    out.phase, out.connection = 'UNPAIRED', p.pairing and 'ÎMPERECHERE' or 'NEÎMPERECHEAT'
    return out
  end
  local st = p.state
  local staleMs = st and num(st.stale_after_ms) or M.DEFAULT_STALE_MS
  local ageMs = p.stateAt and (p.now - p.stateAt) * 1000 or math.huge
  local serverNow = p.sync and p.sync:serverNowMs(p.now)
  if not st then
    out.phase, out.connection = p.error and 'OFFLINE' or 'CONNECTING', p.error and 'FĂRĂ CONEXIUNE' or 'SE CONECTEAZĂ'
    return out
  end
  out.context, out.procedure, out.me = st.context, st.procedure, st.me
  if ageMs > staleMs or not serverNow then
    out.phase, out.connection = 'STALE', 'CONEXIUNE PIERDUTĂ'
    out.staleS = ageMs ~= math.huge and math.floor(ageMs / 1000) or nil
    return out
  end
  out.connection, out.serverNowMs = 'CONECTAT', serverNow
  local me = st.me or {}
  local code = me.code or 'NO_CONTEXT'
  local proc = st.procedure
  if proc and proc.status == 'hold' then out.phase = 'HOLD'; return out end
  local slot = me.slot
  if code == 'SCHEDULED' or code == 'WINDOW_OPEN' or (code == 'MISSED_RETRY' and slot and slot.status == 'scheduled') then
    if not slot or slot.status ~= 'scheduled' or not proc or proc.status ~= 'running' then out.phase = 'RACE_CONTROL'; return out end
    out.slot = slot
    if serverNow < slot.window_opens_at_ms then
      out.phase = code == 'MISSED_RETRY' and 'MISSED_RETRY' or 'SCHEDULED'
      out.countdownS = ceilS(slot.window_opens_at_ms - serverNow)
      out.toStartS = ceilS(slot.scheduled_at_ms - serverNow)
    elseif serverNow <= slot.window_closes_at_ms then
      out.phase = 'WINDOW_OPEN'
      out.authorized = true
      out.go = p.aligned == true
      out.countdownS = ceilS(slot.window_closes_at_ms - serverNow)
      out.toStartS = math.floor((slot.scheduled_at_ms - serverNow) / 1000)
    else
      out.phase = 'WINDOW_CLOSED' -- așteaptă decizia serverului; clientul nu prelungește fereastra
    end
    return out
  end
  out.slot = slot
  out.phase = code
  return out
end

-- Texte pentru overlay (fără :upper(), diacritice păstrate). level: ok | info | warn | bad
local TEXT = {
  UNPAIRED = { 'APLICAȚIE NEÎMPERECHEATĂ', 'Setări → Conectare Race Control → Împerechează.', 'warn' },
  CONNECTING = { 'SE CONECTEAZĂ LA RACE CONTROL', 'Nu porni: nu există încă o autorizare de start.', 'info' },
  OFFLINE = { 'FĂRĂ CONEXIUNE LA RACE CONTROL', 'Nu porni. Anunță Race Control pe Discord.', 'bad' },
  STALE = { 'CONEXIUNE PIERDUTĂ — HOLD', 'Nu porni până nu revine conexiunea. Fereastra nu se prelungește.', 'bad' },
  NO_CONTEXT = { 'NICIO ÎNSCRIERE ACTIVĂ', 'Contul nu are o înscriere acceptată la o etapă cu Race Control activ.', 'info' },
  NOT_IN_RUN = { 'NU EȘTI ÎN COADA MANȘEI', 'Contactează Race Control.', 'warn' },
  WAITING_SAFETY_CAR = { 'AȘTEAPTĂ PROGRAMUL DE START', 'Ora de start apare când Race Control pornește programul (Safety Car la finish sau organizatorul).', 'info' },
  SCHEDULED = { 'ORĂ DE START PRIMITĂ', 'Aliniază-te. Fereastra se deschide cu 10 s înainte de ora programată.', 'info' },
  WINDOW_OPEN = { 'FEREASTRĂ DESCHISĂ', 'Poți pleca acum, doar aliniat.', 'ok' },
  WINDOW_CLOSED = { 'FEREASTRA S-A ÎNCHIS', 'Nu pleca. Așteaptă decizia Race Control.', 'bad' },
  DEPARTED = { 'PLECARE ÎNREGISTRATĂ', 'Raport trimis. Timpul oficial vine din sistemul de timing.', 'ok' },
  MISSED_RETRY = { 'START RATAT — A DOUA ȘANSĂ', 'Eliberează zona de start (mergi la boxe). Ai primit o nouă oră, la finalul cozii.', 'bad' },
  IN_REVIEW = { 'START ÎN ANALIZĂ', 'Race Control verifică fereastra ta. Nu pleca fără instrucțiuni.', 'warn' },
  DNS_PENDING = { 'A DOUA FEREASTRĂ RATATĂ', 'Directorul de cursă decide (DNS pentru această manșă). Eliberează zona.', 'bad' },
  DNS = { 'DNS — MANȘA CURENTĂ', 'Nu ai plecat în cele două ferestre. Celelalte manșe nu sunt afectate.', 'bad' },
  RACE_CONTROL = { 'AȘTEAPTĂ RACE CONTROL', 'Nu pleca fără instrucțiuni.', 'warn' },
  HOLD = { 'HOLD — STARTURI OPRITE', 'Nu pleca. Orele se recalculează la reluare.', 'bad' },
  CANCELLED = { 'STARTUL TĂU A FOST ANULAT', 'Race Control a modificat coada. Așteaptă instrucțiuni.', 'warn' },
  PROCEDURE_COMPLETED = { 'PROCEDURA DE START S-A ÎNCHEIAT', '', 'info' },
}
M.TEXT = TEXT

function M.text(phase)
  local t = TEXT[phase] or { phase or '', '', 'info' }
  return t[1], t[2], t[3]
end

--- Pasul din bara de progres (1 Aliniere, 2 Countdown, 3 Start, 4 Pe traseu).
function M.progressStep(model, aligned)
  if model.phase == 'DEPARTED' then return 4 end
  if model.phase == 'WINDOW_OPEN' then return 3 end
  if model.phase == 'SCHEDULED' and aligned then return 2 end
  return 1
end

return M
