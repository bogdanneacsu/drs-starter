-- Calibrare: transformă eșantioane / noduri de traseu într-o configurație de start. Pur.
local V = require('src/vec')
local C = require('src/config')
local SC = require('src/start_config')

local M = {}

--- Captură mediată. samples = listă de {point=vec, look=vec, speedKmh=number, reference='contact'|'hub'|'bumper'}.
--- Cere: toate eșantioanele cu mașina oprită și cu referință pe roți (nu bara față).
---@return table|nil result {p0, forward, spreadM, count}, string|nil err
function M.average(samples)
  if type(samples) ~= 'table' or #samples < 5 then return nil, 'prea puține eșantioane' end
  local sum, look = V.new(), V.new()
  for _, s in ipairs(samples) do
    if s.reference == 'bumper' or not s.reference then return nil, 'roțile nu sunt disponibile (doar bara față)' end
    if s.speedKmh > C.DEFAULT_STATIONARY.max_speed_kmh then return nil, 'mașina s-a mișcat în timpul capturii' end
    sum = V.add(sum, s.point)
    look = V.add(look, V.flat(s.look))
  end
  local p0 = V.scale(sum, 1 / #samples)
  local f = V.normalize(look)
  if not f then return nil, 'direcție nedeterminată' end
  local spread = 0
  for _, s in ipairs(samples) do
    local d = V.len(V.sub(s.point, p0))
    if d > spread then spread = d end
  end
  return { p0 = p0, forward = f, spreadM = spread, count = #samples }
end

--- Linie din nodurile AC_AB_START_L / AC_AB_START_R. Sensul este ales după orientarea mașinii.
function M.lineFromNodes(left, right, carLook)
  if not V.isFinite(left) or not V.isFinite(right) then return nil, 'noduri invalide' end
  local across = V.flat(V.sub(right, left))
  local width = V.len(across)
  if width < 1 then return nil, 'noduri prea apropiate' end
  local f = V.normalize(V.new(across.z, 0, -across.x))
  if carLook and V.dot(V.flat(carLook), f) < 0 then f = V.scale(f, -1) end
  return { p0 = V.mid(left, right), forward = f, width_m = width }
end

--- Construiește intrarea de configurare (forma JSON) dintr-o linie capturată.
function M.buildEntry(args)
  local route = args.route or 'default'
  local e = {
    id = SC.makeId(args.track, args.layout, route),
    track = args.track, layout = args.layout or '', route = route,
    label = args.label or route,
    line = { p0 = V.toList(args.p0), forward = V.toList(args.forward), width_m = args.width_m or C.DEFAULT_LINE_WIDTH_M },
    target = args.target, stationary = args.stationary,
    approach_radius_m = args.approach_radius_m or C.DEFAULT_APPROACH_RADIUS_M,
    source = args.source, calibrated_at = args.calibrated_at, car = args.car, csp_build = args.csp_build,
  }
  return e
end

return M
