-- Countdown LOCAL repetitiv (Faza 1): 40 → 0 → 40 → …
-- Doar pentru testarea interfeței. NU este programul oficial de start și nu produce un semnal oficial.
-- Pur: timpul este primit ca parametru (secunde, ceas monoton), deci nu există drift și nici dependență de cadre.

local Countdown = {}
Countdown.__index = Countdown

---@param duration number? secunde, implicit 40
---@param now number timp monoton curent (os.preciseClock())
---@param anchor number? ancoră salvată (de ex. după reîncărcarea aplicației)
function Countdown.new(duration, now, anchor)
  duration = tonumber(duration) or 40
  if duration <= 0 then error('countdown duration must be > 0') end
  local self = setmetatable({ duration = duration, anchor = now, paused = false, pausedRemaining = nil,
    lastCycle = 0 }, Countdown)
  if anchor and anchor <= now then
    self.anchor = anchor
    self.lastCycle = math.floor((now - anchor) / duration)
  end
  return self
end

function Countdown:_elapsed(now)
  local e = now - self.anchor
  if e < 0 then
    -- Ceasul a mers înapoi (nu ar trebui la un ceas monoton): repornim curat.
    self.anchor = now
    self.lastCycle = 0
    e = 0
  end
  return e
end

--- Starea curentă. `cycleCompleted` este true o singură dată după fiecare trecere prin zero
--- (chiar dacă un cadru blocat a sărit peste mai multe cicluri, se raportează o singură dată, cu numărul lor).
function Countdown:update(now)
  if self.paused then
    local r = self.pausedRemaining
    return { remaining = r, display = math.max(1, math.ceil(r - 1e-9)), cycle = self.lastCycle,
      cycleCompleted = false, cyclesSkipped = 0, paused = true, duration = self.duration }
  end
  local e = self:_elapsed(now)
  local cycle = math.floor(e / self.duration)
  local phase = e - cycle * self.duration
  local remaining = self.duration - phase           -- în (0, duration]
  local completed = cycle > self.lastCycle
  local skipped = completed and (cycle - self.lastCycle - 1) or 0
  self.lastCycle = cycle
  return {
    remaining = remaining,
    display = math.max(1, math.ceil(remaining - 1e-9)),  -- 40 … 1; zero este semnalat prin cycleCompleted
    cycle = cycle,
    cycleCompleted = completed,
    cyclesSkipped = skipped,
    paused = false,
    duration = self.duration,
  }
end

function Countdown:pause(now)
  if self.paused then return end
  local s = self:update(now)
  self.paused = true
  self.pausedRemaining = s.remaining
end

function Countdown:resume(now)
  if not self.paused then return end
  -- Mutăm ancora astfel încât ciclul să continue din punctul de pauză.
  self.anchor = now - (self.duration - self.pausedRemaining) - self.lastCycle * self.duration
  self.paused = false
  self.pausedRemaining = nil
end

function Countdown:reset(now)
  self.anchor = now
  self.lastCycle = 0
  self.paused = false
  self.pausedRemaining = nil
end

--- Ancora poate fi păstrată și refolosită după o reîncărcare a aplicației, dacă e validă.
function Countdown.isAnchorUsable(anchor, now, maxAge)
  return type(anchor) == 'number' and anchor == anchor and anchor <= now and (now - anchor) <= (maxAge or 3600)
end

return Countdown
