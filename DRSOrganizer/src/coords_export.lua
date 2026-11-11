-- DRS Organizer: transformă o linie de start capturată în texte gata de copiat
-- (configul ACSM pentru warm_tyres și intrarea JSON pentru site / starts.json). Pur, testabil în LuaJIT.
local V = require('src/vec')

local M = {}

M.HISTORY_MAX = 50

local function n3(x) return string.format('%.3f', x) end
local function vecText(p) return n3(p.x) .. ', ' .. n3(p.y) .. ', ' .. n3(p.z) end
M.vecText = vecText

--- Unghiul de orientare (grade, 0 = +Z, sens orar spre +X), doar informativ.
function M.headingDeg(forward)
  local d = math.deg(math.atan2(forward.x, forward.z))
  if d < 0 then d = d + 360 end
  return d
end

--- Bloc pentru csp_extra_options.ini al serverului ACSM (scriptul online de încălzire a roților).
---@param capture table {p0, forward}
---@param opts table|nil {scriptUrl, stopRadius, tempOffset}
function M.acsmBlock(capture, opts)
  opts = opts or {}
  local lines = {
    '[SCRIPT_...]',
    'SCRIPT = ' .. (opts.scriptUrl and opts.scriptUrl ~= '' and opts.scriptUrl or '<link către warm_tyres.lua, versiune fixă>'),
    'startPos = ' .. vecText(capture.p0),
    'stopRadius = ' .. tostring(opts.stopRadius or 20),
    'tempOffset = ' .. tostring(opts.tempOffset or 0),
  }
  return table.concat(lines, '\n')
end

--- Rezumat lizibil pentru organizator.
function M.summary(capture)
  return string.format('Linie start: %s · orientare %.1f° · lățime %.1f m', vecText(capture.p0), M.headingDeg(capture.forward),
    capture.width_m or 0)
end

--- Adaugă o captură în istoric (cele mai noi primele), fără duplicate de id + moment.
function M.pushHistory(history, item)
  history = type(history) == 'table' and history or {}
  table.insert(history, 1, item)
  while #history > M.HISTORY_MAX do table.remove(history) end
  return history
end

--- Elementul de istoric salvat în data/captures.json.
function M.historyItem(entry, capture, when)
  return {
    id = entry.id, track = entry.track, layout = entry.layout, route = entry.route, label = entry.label,
    p0 = V.toList(capture.p0), forward = V.toList(capture.forward), width_m = entry.line.width_m,
    spread_cm = capture.spreadM and math.floor(capture.spreadM * 1000 + 0.5) / 10 or nil,
    samples = capture.count, source = entry.source, at = when, entry = entry,
  }
end

return M
