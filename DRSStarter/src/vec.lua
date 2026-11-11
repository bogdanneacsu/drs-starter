-- Vectori 3D minimali ca tabele {x, y, z}. Pur Lua, ca logica de aliniere să fie testabilă în afara jocului.
local V = {}

function V.new(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end

-- Acceptă tabele {x=,y=,z=}, liste {x, y, z} sau obiecte vec3 CSP (au câmpurile .x .y .z).
function V.from(v)
  if v == nil then return nil end
  if type(v) == 'table' and v.x == nil and v[1] ~= nil then return V.new(v[1], v[2], v[3]) end
  return V.new(v.x, v.y, v.z)
end

function V.toList(v) return { v.x, v.y, v.z } end
function V.add(a, b) return V.new(a.x + b.x, a.y + b.y, a.z + b.z) end
function V.sub(a, b) return V.new(a.x - b.x, a.y - b.y, a.z - b.z) end
function V.scale(a, k) return V.new(a.x * k, a.y * k, a.z * k) end
function V.mid(a, b) return V.new((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2) end
function V.dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
function V.len(a) return math.sqrt(V.dot(a, a)) end

-- Proiecție pe planul orizontal (Y este axa verticală în AC).
function V.flat(a) return V.new(a.x, 0, a.z) end

function V.normalize(a)
  local l = V.len(a)
  if l < 1e-9 then return nil end
  return V.scale(a, 1 / l)
end

function V.isFinite(v)
  if type(v) ~= 'table' then return false end
  for _, k in ipairs({ 'x', 'y', 'z' }) do
    local n = v[k]
    if type(n) ~= 'number' or n ~= n or n == math.huge or n == -math.huge then return false end
  end
  return true
end

-- Unghi în grade între doi vectori (presupuși nenuli).
function V.angleDeg(a, b)
  local na, nb = V.normalize(a), V.normalize(b)
  if not na or not nb then return 180 end
  local c = V.dot(na, nb)
  if c > 1 then c = 1 elseif c < -1 then c = -1 end
  return math.deg(math.acos(c))
end

return V
