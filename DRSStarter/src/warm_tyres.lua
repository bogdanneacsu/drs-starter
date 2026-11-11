-- Încălzirea anvelopelor până la linia de start (logica scriptului warm_tyres.lua al organizatorului, integrată).
-- Pur: aplicarea temperaturii este injectată (`apply`), ca logica să fie testabilă în afara jocului.
-- Diferență față de scriptul original: fără linie de start configurată NU se încălzește (altfel ar încălzi și în tura cronometrată).
local V = require('src/vec')

local M = {}

local W = {}
W.__index = W

--- opts = {stop_radius_m, temp_offset_c, interval_s, enabled}
function M.new(opts)
  return setmetatable({ opts = opts, armed = true, active = false, timer = 0, failed = false, error = nil }, W)
end

--- sample: eșantionul CarProbe (isInPit, position, tyreOptimum[0..3]); startP0: punctul liniei de start (sau nil).
--- apply(wheelIndex 0..3, temp) aplică temperatura; dacă aruncă o eroare, încălzirea se oprește definitiv (API indisponibil).
--- Returnează starea: 'off' | 'pit' | 'warming' | 'stopped' | 'no_start' | 'unavailable'
function W:update(dt, sample, startP0, apply)
  self.active = false
  if not self.opts.enabled then return 'off' end
  if self.failed then return 'unavailable' end
  if not sample then return 'stopped' end
  if sample.isInPit then self.armed = true end
  if not startP0 then return 'no_start' end
  if self.armed and V.isFinite(sample.position) and V.len(V.sub(sample.position, startP0)) < self.opts.stop_radius_m then
    self.armed = false
  end
  if not self.armed then return 'stopped' end
  self.active = true
  self.timer = self.timer + (dt or 0)
  if self.timer < self.opts.interval_s then return sample.isInPit and 'pit' or 'warming' end
  self.timer = 0
  for i = 0, 3 do
    local opt = sample.tyreOptimum and sample.tyreOptimum[i]
    if opt then
      local ok, err = pcall(apply, i, opt + self.opts.temp_offset_c)
      if not ok then
        self.failed, self.error, self.active = true, tostring(err), false
        return 'unavailable'
      end
    end
  end
  return sample.isInPit and 'pit' or 'warming'
end

--- Aplicarea reală în CSP (aceeași funcție ca în scriptul original).
local WHEELS
function M.cspApply(i, temp)
  WHEELS = WHEELS or { [0] = ac.Wheel.FrontLeft, ac.Wheel.FrontRight, ac.Wheel.RearLeft, ac.Wheel.RearRight }
  physics.setTyresTemperature(0, WHEELS[i], temp)
end

M.LABEL = {
  off = 'ÎNCĂLZIRE DEZACTIVATĂ', pit = 'ÎNCĂLZIRE ACTIVĂ (BOXE)', warming = 'ANVELOPE ÎNCĂLZITE', stopped = 'ÎNCĂLZIRE OPRITĂ',
  no_start = 'ÎNCĂLZIRE: TRASEU NECALIBRAT', unavailable = 'ÎNCĂLZIRE INDISPONIBILĂ PE ACEST SERVER',
}

return M
