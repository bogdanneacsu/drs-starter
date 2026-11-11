-- Citește starea mașinii proprii din CSP și o transformă într-un eșantion simplu pentru alignment.lua.
-- Câmpurile folosite apar în cod oficial CSP (vezi RESEARCH.md §0.2); accesul este protejat cu pcall,
-- ca un câmp lipsă într-o altă versiune CSP să ducă la NO_CAR, nu la eroare.
local V = require('src/vec')

local M = {}

local function read()
  local car = ac.getCar(0)
  if not car then return nil end
  local s = {
    look = V.from(car.look),
    position = V.from(car.position),
    speedKmh = car.speedKmh,
    steerDeg = car.steer,                 -- unitatea exactă de verificat în joc (vezi checklist)
  }
  local w = car.wheels
  if w ~= nil then
    local fl, fr = w[0], w[1]            -- ac.Wheel.FrontLeft = 0, FrontRight = 1
    if fl and fr then
      s.frontContact = { V.from(fl.contactPoint), V.from(fr.contactPoint) }
      s.frontHub = { V.from(fl.position), V.from(fr.position) }
      s.rearContact = { V.from(w[2].contactPoint), V.from(w[3].contactPoint) }
    end
  end
  if car.aabbSize and car.aabbCenter then
    s.bumper = V.from(car.position + car.look * (car.aabbSize.z / 2 - car.aabbCenter.z))
  end
  return s
end

M.lastError = nil

function M.sample()
  local ok, res = pcall(read)
  if not ok then
    M.lastError = tostring(res)
    return nil
  end
  M.lastError = nil
  return res
end

--- Ampatament estimat (diagnostic), din contactele față/spate.
function M.wheelbase(s)
  if not s or not s.frontContact or not s.rearContact then return nil end
  if not (V.isFinite(s.frontContact[1]) and V.isFinite(s.rearContact[1])) then return nil end
  return V.len(V.flat(V.sub(V.mid(s.frontContact[1], s.frontContact[2]), V.mid(s.rearContact[1], s.rearContact[2]))))
end

return M
