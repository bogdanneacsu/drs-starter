-- Caută nodurile de start A→B din KN5 (AC_AB_START_L / AC_AB_START_R), ca în modul oficial CSP „Rally Stage”.
-- Rezultatul este doar o PROPUNERE de calibrare; organizatorul o confirmă vizual.
local V = require('src/vec')
local Cal = require('src/calibration')

local M = {}

local function nodePos(name)
  local ok, ref = pcall(ac.findNodes, name)
  if not ok or ref == nil or #ref == 0 then return nil end
  local ok2, pos = pcall(function () return ref:getPosition() end)
  if not ok2 or pos == nil then return nil end
  return V.from(pos)
end

--- Returnează (line {p0, forward, width_m}) sau (nil, motiv).
function M.startLine(carLook)
  local l, r = nodePos('AC_AB_START_L'), nodePos('AC_AB_START_R')
  if not l or not r then return nil, 'traseul nu are nodurile AC_AB_START_L/R' end
  return Cal.lineFromNodes(l, r, carLook)
end

return M
