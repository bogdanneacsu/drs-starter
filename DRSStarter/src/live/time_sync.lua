-- Estimarea decalajului dintre ceasul serverului (epoch ms) și ceasul monoton local (os.preciseClock).
-- NTP simplificat: t0 trimitere, t1 primire pe server, t2 răspuns pe server, t3 primire locală.
--   offset = ((t1 − t0) + (t2 − t3)) / 2,   întârziere = (t3 − t0) − (t2 − t1)
-- Se păstrează eșantionul cu întârzierea minimă dintr-o fereastră recentă (cel mai puțin afectat de rețea).
-- Între sincronizări, ora serverului = ceas monoton + offset: fără drift de cadre, fără ceasul Windows.
local M = {}

M.MAX_DELAY_MS = 2000      -- eșantioane mai lente sunt ignorate
M.WINDOW_S = 60            -- eșantioanele mai vechi ies din calcul (urmărește driftul ceasului)
M.MAX_SAMPLES = 12

local Sync = {}
Sync.__index = Sync

function M.new() return setmetatable({ samples = {}, offsetMs = nil, delayMs = nil, updatedAt = nil }, Sync) end

--- t0/t3 în secunde monotone locale; t1/t2 în ms epoch server. Returnează true dacă eșantionul e acceptat.
function Sync:add(t0, t1, t2, t3)
  if type(t0) ~= 'number' or type(t1) ~= 'number' or type(t2) ~= 'number' or type(t3) ~= 'number' then return false end
  if t3 < t0 or t2 < t1 then return false end
  local a, d = t0 * 1000, t3 * 1000
  local delay = (d - a) - (t2 - t1)
  if delay < 0 then delay = 0 end
  if delay > M.MAX_DELAY_MS then return false end
  local offset = ((t1 - a) + (t2 - d)) / 2
  table.insert(self.samples, { offset = offset, delay = delay, at = t3 })
  while #self.samples > M.MAX_SAMPLES do table.remove(self.samples, 1) end
  self:_recompute(t3)
  return true
end

function Sync:_recompute(now)
  local best
  for i = #self.samples, 1, -1 do
    local s = self.samples[i]
    if now - s.at > M.WINDOW_S then table.remove(self.samples, i)
    elseif not best or s.delay < best.delay then best = s end
  end
  if best then self.offsetMs, self.delayMs, self.updatedAt = best.offset, best.delay, now end
end

function Sync:ready() return self.offsetMs ~= nil end

--- Ora serverului estimată (ms epoch) la momentul monoton `t` (secunde).
function Sync:serverNowMs(t)
  if not self.offsetMs then return nil end
  return t * 1000 + self.offsetMs
end

--- Incertitudinea estimării (± ms): jumătate din întârzierea eșantionului folosit.
function Sync:uncertaintyMs() return self.delayMs and self.delayMs / 2 or nil end

function Sync:reset() self.samples, self.offsetMs, self.delayMs, self.updatedAt = {}, nil, nil, nil end

return M
