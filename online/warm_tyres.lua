-- warm_tyres.lua
-- Script online CSP: tine anvelopele la temperatura optima de la iesirea din pit
-- pana cand masina ajunge langa linia de start (hillclimb).
-- Se incarca din csp_extra_options.ini al serverului, sectiunea [SCRIPT_...].

local cfg = ac.configValues({
  startPos = vec3(),   -- coordonatele liniei de start (X, Y, Z), luate din Objects Inspector
  stopRadius = 20,     -- la ce distanta (m) de start nu mai incalzim anvelopele
  tempOffset = 0,      -- grade in plus/minus fata de temperatura optima
  interval = 0.25,     -- la cate secunde reaplicam temperatura
})

local WHEELS = {
  ac.Wheel.FrontLeft,
  ac.Wheel.FrontRight,
  ac.Wheel.RearLeft,
  ac.Wheel.RearRight,
}

local hasStart = cfg.startPos:length() > 0
local armed = true  -- activ la intrarea pe server (masina e in pit)
local timer = 0

function script.update(dt)
  local car = ac.getCar(0)  -- 0 = masina jucatorului local
  if not car then return end

  -- Reactivam cand masina e din nou parcata in boxa (dupa "back to pits" / teleport)
  if car.isInPit then
    armed = true
  end

  -- Ne oprim inainte de linia de start, ca sa nu afectam tura cronometrata
  if armed and hasStart and car.position:distance(cfg.startPos) < cfg.stopRadius then
    armed = false
  end

  if not armed then return end

  timer = timer + dt
  if timer < cfg.interval then return end
  timer = 0

  for i = 0, 3 do
    local wheel = car.wheels[i]
    physics.setTyresTemperature(0, WHEELS[i + 1], wheel.tyreOptimumTemperature + cfg.tempOffset)
  end
end
