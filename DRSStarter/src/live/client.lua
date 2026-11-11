-- Client Race Control (Faza 2): împerechere, sincronizare periodică, acțiuni Safety Car.
-- Toate cererile sunt asincrone (web.request din CSP, max. 2 simultan): nu blochează randarea.
-- O singură cerere /sync în zbor; o singură acțiune în zbor. Tokenul nu apare niciodată în UI sau în log.
local TimeSync = require('src/live/time_sync')
local Model = require('src/live/live_model')

local M = {}

M.PAIR_POLL_S = 3
M.MAX_BACKOFF_S = 10
M.SEQ_BLOCK = 200
M.REQUEST_TIMEOUT_S = 15 -- plasă de siguranță dacă un callback nu mai vine (CSP are propriile timeout-uri)

local Client = {}
Client.__index = Client

--- Implementarea implicită peste API-ul CSP `web.request` (verificat în acc-lua-sdk, common/ac_web.lua).
function M.cspHttp(method, url, headers, body, cb)
  web.request(method, url, headers, body, function (err, response)
    if err then cb(tostring(err), 0, nil) else cb(nil, response.status, response.body) end
  end)
end

--- URL acceptat: https://…, sau http:// doar pentru dezvoltare locală (localhost, 127.x, 10.x, 192.168.x).
function M.validBaseUrl(u)
  if type(u) ~= 'string' then return nil end
  u = u:gsub('%s+', ''):gsub('/+$', '')
  if u:match('^https://[%w%.%-]+[:%d]*') then return u end
  local host = u:match('^http://([%w%.%-]+)')
  if host and (host == 'localhost' or host:match('^127%.') or host:match('^10%.') or host:match('^192%.168%.')) then return u end
  return nil
end

---@param o {storage:table, http:function?, now:function, json:table, appVersion:string, cspBuild:number}
function M.new(o)
  local c = setmetatable({
    storage = o.storage, http = o.http or M.cspHttp, now = o.now, json = o.json,
    appVersion = o.appVersion, cspBuild = o.cspBuild,
    timeSync = TimeSync.new(), state = nil, stateAt = nil, lastError = nil, failures = 0,
    inFlight = false, nextPollAt = 0, actionInFlight = false, pairing = nil, feedback = nil,
    pending = {}, statusProvider = nil,
  }, Client)
  c:_loadPending()
  return c
end

function Client:paired() return type(self.storage.token) == 'string' and #self.storage.token > 20 end
function Client:baseUrl() return M.validBaseUrl(self.storage.serverUrl) end

-- Secvențe monotone persistente (rezervare în blocuri, ca să nu scriem storage la fiecare cerere).
function Client:_nextSeq(key)
  local cur = (self['_' .. key] or (self.storage[key] or 0)) + 1
  self['_' .. key] = cur
  if cur >= (self.storage[key] or 0) then self.storage[key] = cur + M.SEQ_BLOCK end
  return cur
end

function Client:_loadPending()
  local raw = self.storage.pendingEvents
  if type(raw) == 'string' and raw ~= '' then
    local ok, list = pcall(self.json.parse, raw)
    if ok and type(list) == 'table' then self.pending = list end
  end
end

function Client:_savePending()
  self.storage.pendingEvents = #self.pending > 0 and self.json.stringify(self.pending) or ''
end

function Client:_headers(withAuth)
  local h = { ['Content-Type'] = 'application/json', ['Accept'] = 'application/json', ['X-DRS-Starter'] = self.appVersion }
  if withAuth then h['Authorization'] = 'Bearer ' .. self.storage.token end
  return h
end

--- Eveniment raportat (plecare / zonă părăsită). Ora = estimarea orei serverului; se retrimite până la confirmare.
function Client:queueEvent(kind, data, slot, scheduleVersion)
  local t = self.now()
  local ev = { seq = self:_nextSeq('eventSeq'), type = kind, server_time_ms = self.timeSync:serverNowMs(t) and math.floor(self.timeSync:serverNowMs(t)) or nil,
    slot_id = slot and slot.id or nil, schedule_version = scheduleVersion, data = data }
  table.insert(self.pending, ev)
  while #self.pending > 20 do table.remove(self.pending, 1) end
  self:_savePending()
  self.nextPollAt = 0 -- trimite imediat
  return ev
end

function Client:pollNow() self.nextPollAt = 0 end

function Client:_context()
  if self.storage.mode == 'safety' then
    local e, c = tonumber(self.storage.scEventId), tonumber(self.storage.scClassId)
    return e and e > 0 and e or nil, c and c > 0 and c or nil
  end
end

function Client:update()
  local t = self.now()
  if self.pairing then self:_pairPoll(t); return end
  if self.inFlight and t - (self.inFlightSince or t) > M.REQUEST_TIMEOUT_S then
    self.inFlight = false -- cererea veche e abandonată; răspunsul ei întârziat va fi ignorat
    self:_fail(t, 'timeout')
  end
  if not self:paired() or not self:baseUrl() or self.inFlight or t < self.nextPollAt then return end
  self.requestId = (self.requestId or 0) + 1
  local myId = self.requestId
  self.inFlight, self.inFlightSince = true, t
  local status = self.statusProvider and self.statusProvider() or {}
  status.seq = self:_nextSeq('statusSeq')
  local eventId, classId = self:_context()
  local sent = {}
  for i, e in ipairs(self.pending) do sent[i] = e end
  local body = self.json.stringify({
    mode = self.storage.mode == 'safety' and 'safety' or 'driver', event_id = eventId, class_id = classId,
    client = { app_version = self.appVersion, csp_build = self.cspBuild }, status = status, events = #sent > 0 and sent or nil,
  })
  local t0 = t
  self.http('POST', self:baseUrl() .. '/api/starter/v1/sync', self:_headers(true), body, function (err, code, resp)
    if myId ~= self.requestId then return end -- răspuns la o cerere abandonată
    self.inFlight = false
    local t3 = self.now()
    if err or code == 0 then return self:_fail(t3, 'rețea: ' .. tostring(err)) end
    if code == 401 then
      self.storage.token, self.state, self.stateAt = '', nil, nil
      self.lastError = 'Dispozitivul nu mai este autorizat (revocat sau expirat). Împerechează din nou.'
      return
    end
    if code ~= 200 then return self:_fail(t3, 'HTTP ' .. tostring(code)) end
    local ok, parsed = pcall(self.json.parse, resp or '')
    local st, why = Model.validateState(ok and parsed or nil)
    if not st then return self:_fail(t3, 'răspuns invalid: ' .. tostring(why)) end
    self.timeSync:add(t0, st.server_received_ms, st.server_time_ms, t3)
    self:_ack(st.acks)
    self.state, self.stateAt, self.lastError, self.failures = st, t3, nil, 0
    local wait = (type(st.poll_after_ms) == 'number' and st.poll_after_ms or 5000) / 1000
    self.nextPollAt = t3 + math.max(0.5, math.min(10, wait))
    if #self.pending > 0 then self.nextPollAt = math.min(self.nextPollAt, t3 + 1) end
  end)
end

function Client:_ack(acks)
  if type(acks) ~= 'table' or #acks == 0 then return end
  local done = {}
  for _, s in ipairs(acks) do done[s] = true end
  for i = #self.pending, 1, -1 do if done[self.pending[i].seq] then table.remove(self.pending, i) end end
  self:_savePending()
end

function Client:_fail(t, msg)
  self.failures = self.failures + 1
  self.lastError = msg
  self.nextPollAt = t + math.min(M.MAX_BACKOFF_S, 2 ^ math.min(self.failures - 1, 4))
end

-- ───────────── Împerechere (cod afișat în joc, confirmat pe site) ─────────────

function Client:startPairing(deviceName)
  local base = self:baseUrl()
  if not base then self.feedback = { ok = false, text = 'Adresa serverului lipsește sau nu este https://.' }; return end
  if self.pairing then return end
  self.pairing = { requesting = true }
  self.http('POST', base .. '/api/starter/v1/pair', self:_headers(false), self.json.stringify({ device_name = deviceName }), function (err, code, resp)
    local ok, p = pcall(self.json.parse, resp or '')
    if err or code ~= 201 or not ok or type(p) ~= 'table' or type(p.device_code) ~= 'string' or type(p.user_code) ~= 'string' then
      self.pairing = nil
      self.feedback = { ok = false, text = 'Împerecherea nu a pornit (' .. (err and 'rețea' or 'HTTP ' .. tostring(code)) .. ').' }
      return
    end
    local t = self.now()
    self.pairing = { userCode = p.user_code, deviceCode = p.device_code, expiresAt = t + (tonumber(p.expires_in) or 600), nextAt = t + M.PAIR_POLL_S, verifyUrl = p.verify_url }
  end)
end

function Client:cancelPairing() self.pairing = nil end

function Client:_pairPoll(t)
  local p = self.pairing
  if p.requesting or p.polling or t < (p.nextAt or 0) then return end
  if t > p.expiresAt then self.pairing = nil; self.feedback = { ok = false, text = 'Codul a expirat. Pornește din nou împerecherea.' }; return end
  p.polling = true
  self.http('POST', self:baseUrl() .. '/api/starter/v1/pair/poll', self:_headers(false), self.json.stringify({ device_code = p.deviceCode }), function (err, code, resp)
    p.polling = false
    p.nextAt = self.now() + M.PAIR_POLL_S
    local ok, r = pcall(self.json.parse, resp or '')
    if err or code ~= 200 or not ok or type(r) ~= 'table' then return end
    if r.status == 'paired' and type(r.token) == 'string' then
      self.storage.token = r.token
      self.pairing, self.state, self.stateAt, self.nextPollAt = nil, nil, nil, 0
      self.feedback = { ok = true, text = 'Împerechere reușită.' }
    elseif r.status == 'expired' or r.status == 'unknown' or r.status == 'consumed' then
      self.pairing = nil
      self.feedback = { ok = false, text = 'Împerecherea nu mai este valabilă (' .. r.status .. ').' }
    end
  end)
end

function Client:unpair()
  self.storage.token, self.state, self.stateAt, self.pending = '', nil, nil, {}
  self:_savePending()
  self.feedback = { ok = true, text = 'Dispozitiv deconectat local. Revocă-l și din „Profilul meu → DRS Starter”.' }
end

-- ───────────── Acțiuni Safety Car (succes DOAR după confirmarea serverului) ─────────────

function Client:action(kind, payload, done)
  if self.actionInFlight then return false end
  local base = self:baseUrl()
  if not base or not self:paired() then return false end
  local path = ({ confirm = '/procedure/confirm-finish', hold = '/procedure/hold', resume = '/procedure/resume' })[kind]
  if not path then return false end
  self.actionInFlight = kind
  self.http('POST', base .. '/api/starter/v1' .. path, self:_headers(true), self.json.stringify(payload), function (err, code, resp)
    self.actionInFlight = false
    local ok, r = pcall(self.json.parse, resp or '')
    r = ok and type(r) == 'table' and r or {}
    local success = not err and code == 200
    self.feedback = { ok = success, kind = kind, text = success and nil or (r.message or (err and 'Fără conexiune: acțiunea NU a fost înregistrată.' or 'Refuzat (HTTP ' .. tostring(code) .. ').')), response = r }
    self.nextPollAt = 0
    if done then done(success, r) end
  end)
  return true
end

return M
