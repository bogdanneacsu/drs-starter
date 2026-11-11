-- Detecția locală a plecării din zona de start (Faza 2). Rezultatul este un RAPORT (dovadă), nu timing oficial.
-- Plecare = mașina a stat în zona de start (aproape de linie, aproape oprită), apoi a trecut de linie
-- cu ≥ PAST_LINE_M în fața țintei, cu viteză. Se raportează o singură dată; se re-armează la revenirea în zonă.
local M = {}

M.AREA_BACK_M = 5.0        -- zona de start: până la 5 m în spatele țintei…
M.AREA_FWD_M = 0.5         -- …și 0,5 m în fața ei
M.PAST_LINE_M = 1.5        -- plecare: axa față la ≥ 1,5 m în fața țintei (linia e la 30 cm în fața țintei)
M.MIN_SPEED_KMH = 2.0
M.ALIGNED_MEMORY_S = 2.0   -- „aliniat la plecare” = ALIGNED în ultimele 2 s înainte de mișcare

local D = {}
D.__index = D

function M.new() return setmetatable({ armed = false, lastAlignedAt = nil, inZone = false }, D) end

--- r = rezultatul alinierii (Tracker:evaluate), speed km/h, t secunde monotone.
--- Returnează (eveniment|nil); eveniment = {type='departure'|'zone_left', aligned=bool}
function D:update(r, speed, t, alignedState)
  local m = r and r.measure
  if not m then
    -- Fără măsurătoare (ex. teleport la boxe, fără configurație): zona a fost părăsită dacă era ocupată.
    if self.inZone then self.inZone = false; return { type = 'zone_left' } end
    return nil
  end
  local lateralOk = math.abs(m.lateral or 0) <= 4
  local inZone = lateralOk and m.d >= -M.AREA_BACK_M and m.d <= M.AREA_FWD_M
  if r.state == alignedState then self.lastAlignedAt = t end
  local event
  if inZone and (speed or 0) < M.MIN_SPEED_KMH then self.armed = true end
  if self.armed and m.d >= M.PAST_LINE_M and (speed or 0) >= M.MIN_SPEED_KMH and lateralOk then
    self.armed = false
    event = { type = 'departure', aligned = self.lastAlignedAt ~= nil and t - self.lastAlignedAt <= M.ALIGNED_MEMORY_S }
  elseif self.inZone and not inZone and not (m.d >= M.PAST_LINE_M and (speed or 0) >= M.MIN_SPEED_KMH) then
    event = { type = 'zone_left' } -- a ieșit din zonă fără să plece (înapoi, spre boxe sau teleportat la boxe)
  end
  self.inZone = inZone
  return event
end

return M
