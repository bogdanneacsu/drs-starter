-- Configurații de start per traseu / layout / rută. Pur: primește tabele deja decodate din JSON.
local V = require('src/vec')
local C = require('src/config')

local M = {}

local function num(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge end

local function withDefaults(src, defaults)
  local out = {}
  for k, v in pairs(defaults) do out[k] = v end
  if type(src) == 'table' then for k, v in pairs(src) do out[k] = v end end
  return out
end

--- Validează și normalizează o intrare. Returnează (cfg) sau (nil, mesaj de eroare).
function M.validate(e)
  if type(e) ~= 'table' then return nil, 'intrare invalidă' end
  if type(e.id) ~= 'string' or e.id == '' then return nil, 'lipsește id' end
  if type(e.track) ~= 'string' or e.track == '' then return nil, e.id .. ': lipsește track' end
  local line = e.line
  if type(line) ~= 'table' then return nil, e.id .. ': lipsește line' end
  local p0, fw = V.from(line.p0), V.from(line.forward)
  if not p0 or not V.isFinite(p0) then return nil, e.id .. ': line.p0 invalid' end
  if not fw or not V.isFinite(fw) then return nil, e.id .. ': line.forward invalid' end
  local f = V.normalize(V.flat(fw))
  if not f then return nil, e.id .. ': line.forward este vertical sau zero' end
  local width = line.width_m or C.DEFAULT_LINE_WIDTH_M
  if not num(width) or width <= 0 then return nil, e.id .. ': line.width_m invalid' end

  local t = withDefaults(e.target, C.DEFAULT_TARGET)
  for _, k in ipairs({ 'offset_m', 'tol_back_m', 'tol_fwd_m', 'max_lateral_m', 'max_heading_deg', 'max_steer_deg' }) do
    if not num(t[k]) then return nil, e.id .. ': target.' .. k .. ' invalid' end
  end
  if t.tol_back_m <= 0 or t.tol_fwd_m <= 0 then return nil, e.id .. ': toleranțele trebuie să fie > 0' end
  if t.tol_back_m > 1 or t.tol_fwd_m > 1 then return nil, e.id .. ': toleranță > 1 m (refuzat)' end
  if t.max_heading_deg <= 0 or t.max_heading_deg > 45 then return nil, e.id .. ': max_heading_deg în afara 0…45' end
  if t.max_lateral_m <= 0 then return nil, e.id .. ': max_lateral_m trebuie să fie > 0' end
  if t.max_steer_deg < 0 then return nil, e.id .. ': max_steer_deg < 0' end

  local st = withDefaults(e.stationary, C.DEFAULT_STATIONARY)
  for _, k in ipairs({ 'max_speed_kmh', 'hold_s', 'max_drift_m' }) do
    if not num(st[k]) or st[k] <= 0 then return nil, e.id .. ': stationary.' .. k .. ' invalid' end
  end

  local radius = e.approach_radius_m or C.DEFAULT_APPROACH_RADIUS_M
  if not num(radius) or radius <= 0 then return nil, e.id .. ': approach_radius_m invalid' end

  return {
    id = e.id, track = e.track, layout = type(e.layout) == 'string' and e.layout or '',
    route = type(e.route) == 'string' and e.route or 'default', label = e.label or e.id,
    line = { p0 = p0, forward = f, width_m = width },
    target = t, stationary = st, approach_radius_m = radius,
    source = e.source or 'unknown', calibrated_at = e.calibrated_at, car = e.car, csp_build = e.csp_build,
  }
end

--- Parsează un document {schema=1, starts=[...]}. Returnează (lista validă, lista de erori).
function M.parseDocument(doc)
  local ok, errors = {}, {}
  if type(doc) ~= 'table' then return ok, { 'document invalid' } end
  if doc.schema ~= 1 then return ok, { 'schema necunoscută: ' .. tostring(doc.schema) } end
  if type(doc.starts) ~= 'table' then return ok, { 'lipsește lista starts' } end
  for i, e in ipairs(doc.starts) do
    local cfg, err = M.validate(e)
    if cfg then ok[#ok + 1] = cfg else errors[#errors + 1] = '#' .. i .. ' ' .. err end
  end
  return ok, errors
end

--- Combină listele: configurațiile locale (calibrate) înlocuiesc pe cele livrate cu același id.
function M.merge(shipped, localList)
  local byId, order = {}, {}
  for _, list in ipairs({ shipped or {}, localList or {} }) do
    for _, c in ipairs(list) do
      if not byId[c.id] then order[#order + 1] = c.id end
      byId[c.id] = c
    end
  end
  local out = {}
  for _, id in ipairs(order) do out[#out + 1] = byId[id] end
  return out
end

--- Configurațiile pentru traseul și layoutul curent.
function M.forTrack(list, track, layout)
  local out = {}
  for _, c in ipairs(list) do
    if c.track == track and c.layout == (layout or '') then out[#out + 1] = c end
  end
  return out
end

--- Alege configurația activă: preferința explicită (dacă e pe acest traseu), altfel linia cea mai apropiată
--- cu orientare compatibilă (sensul de mers al rutei cu cel al mașinii; acoperă rutele inverse).
function M.select(candidates, preferredId, point, look)
  if #candidates == 0 then return nil end
  if preferredId then
    for _, c in ipairs(candidates) do if c.id == preferredId then return c end end
  end
  if #candidates == 1 or not point or not look then return candidates[1] end
  local best, bestScore
  for _, c in ipairs(candidates) do
    local dist = V.len(V.flat(V.sub(point, c.line.p0)))
    local compatible = V.dot(V.flat(look), c.line.forward) > 0
    local score = dist + (compatible and 0 or 1e6)
    if not bestScore or score < bestScore then best, bestScore = c, score end
  end
  return best
end

--- Forma serializabilă (pentru salvare JSON).
function M.toPlain(c)
  return {
    id = c.id, track = c.track, layout = c.layout, route = c.route, label = c.label,
    line = { p0 = V.toList(c.line.p0), forward = V.toList(c.line.forward), width_m = c.line.width_m },
    target = c.target, stationary = c.stationary, approach_radius_m = c.approach_radius_m,
    source = c.source, calibrated_at = c.calibrated_at, car = c.car, csp_build = c.csp_build,
  }
end

function M.makeId(track, layout, route)
  return track .. '/' .. ((layout and layout ~= '') and layout or '-') .. '/' .. route
end

return M
