-- JSON minimal pentru teste (LuaJIT în afara jocului; în CSP se folosește JSON-ul global al CSP).
local M = {}

local function esc(s)
  return '"' .. s:gsub('[%c"\\]', function (c)
    local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
    return map[c] or string.format('\\u%04x', c:byte())
  end) .. '"'
end

local function isArray(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= 'number' or k < 1 or k % 1 ~= 0 then return false end
    n = n + 1
  end
  return n == #t
end

function M.stringify(v)
  local t = type(v)
  if v == nil then return 'null'
  elseif t == 'boolean' then return tostring(v)
  elseif t == 'number' then
    if v ~= v or v == math.huge or v == -math.huge then return 'null' end
    if v % 1 == 0 and math.abs(v) < 2^53 then return string.format('%d', v) end
    return string.format('%.6f', v)
  elseif t == 'string' then return esc(v)
  elseif t == 'table' then
    if next(v) == nil then return '[]' end
    local out = {}
    if isArray(v) then
      for i = 1, #v do out[i] = M.stringify(v[i]) end
      return '[' .. table.concat(out, ',') .. ']'
    end
    for k, x in pairs(v) do out[#out + 1] = esc(tostring(k)) .. ':' .. M.stringify(x) end
    return '{' .. table.concat(out, ',') .. '}'
  end
  error('cannot encode ' .. t)
end

function M.parse(s)
  local pos = 1
  local function ws() pos = s:find('[^ \t\r\n]', pos) or #s + 1 end
  local value
  local function str()
    local out, i = {}, pos + 1
    while true do
      local c = s:sub(i, i)
      if c == '' then error('unterminated string') end
      if c == '"' then pos = i + 1; return table.concat(out) end
      if c == '\\' then
        local n = s:sub(i + 1, i + 1)
        if n == 'u' then
          local code = tonumber(s:sub(i + 2, i + 5), 16)
          if code < 0x80 then out[#out + 1] = string.char(code)
          elseif code < 0x800 then out[#out + 1] = string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64)
          else out[#out + 1] = string.char(0xE0 + math.floor(code / 4096), 0x80 + math.floor(code / 64) % 64, 0x80 + code % 64) end
          i = i + 6
        else
          out[#out + 1] = ({ n = '\n', r = '\r', t = '\t', b = '\b', f = '\f' })[n] or n
          i = i + 2
        end
      else out[#out + 1] = c; i = i + 1 end
    end
  end
  function value()
    ws()
    local c = s:sub(pos, pos)
    if c == '{' then
      local o = {}; pos = pos + 1; ws()
      if s:sub(pos, pos) == '}' then pos = pos + 1; return o end
      while true do
        ws(); local k = str(); ws()
        assert(s:sub(pos, pos) == ':', 'expected :'); pos = pos + 1
        o[k] = value(); ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == '}' then return o end
        assert(d == ',', 'expected ,')
      end
    elseif c == '[' then
      local a = {}; pos = pos + 1; ws()
      if s:sub(pos, pos) == ']' then pos = pos + 1; return a end
      local i = 0
      while true do
        i = i + 1; a[i] = value(); ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == ']' then return a end
        assert(d == ',', 'expected , in array')
      end
    elseif c == '"' then return str()
    elseif s:sub(pos, pos + 3) == 'true' then pos = pos + 4; return true
    elseif s:sub(pos, pos + 4) == 'false' then pos = pos + 5; return false
    elseif s:sub(pos, pos + 3) == 'null' then pos = pos + 4; return nil
    else
      local num = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', pos)
      assert(num and #num > 0, 'unexpected character at ' .. pos)
      pos = pos + #num
      return tonumber(num)
    end
  end
  local v = value()
  ws()
  if pos <= #s then error('trailing data') end
  return v
end

return M
