-- Stare DEMONSTRATIVĂ locală pentru Safety Car Mode (Faza 1).
-- Nu comunică cu Laravel sau cu agentul Node, nu creează ore de start și nu pornește nicio procedură reală.
-- Faza 2: un `procedure_remote.lua` cu aceleași metode înlocuiește acest modul, fără rescrierea UI-ului.

local P = {}
P.__index = P

P.Phase = {
  SC_ON_COURSE = 'SC_ON_COURSE',       -- Safety Car pe traseu (stare inițială demonstrativă)
  SC_AT_FINISH = 'SC_AT_FINISH',       -- sosire confirmată local
  HOLD = 'HOLD',                       -- suspendare locală
}

function P.new()
  return setmetatable({ phase = P.Phase.SC_ON_COURSE, confirmedAt = nil, holdAt = nil, prevPhase = nil,
    log = {}, isLocalDemo = true }, P)
end

function P:_log(now, text)
  table.insert(self.log, 1, { t = now, text = text })
  while #self.log > 6 do table.remove(self.log) end
end

--- Returnează (ok, mesaj). Idempotent: o a doua apăsare nu schimbă nimic.
function P:confirmSafetyCarFinish(now)
  if self.phase == P.Phase.HOLD then return false, 'HOLD activ — reia întâi procedura' end
  if self.phase == P.Phase.SC_AT_FINISH then return false, 'Sosirea este deja confirmată (local)' end
  self.phase, self.confirmedAt = P.Phase.SC_AT_FINISH, now
  self:_log(now, 'Sosire la finish confirmată (LOCAL DEMO)')
  return true, 'Confirmare înregistrată local. Nicio oră de start nu a fost creată.'
end

function P:hold(now)
  if self.phase == P.Phase.HOLD then return false, 'HOLD este deja activ' end
  self.prevPhase, self.phase, self.holdAt = self.phase, P.Phase.HOLD, now
  self:_log(now, 'HOLD activat (LOCAL DEMO)')
  return true, 'HOLD local activ'
end

function P:release(now)
  if self.phase ~= P.Phase.HOLD then return false, 'HOLD nu este activ' end
  self.phase, self.holdAt = self.prevPhase or P.Phase.SC_ON_COURSE, nil
  self:_log(now, 'HOLD ridicat (LOCAL DEMO)')
  return true, 'HOLD ridicat local'
end

function P:resetDemo(now)
  self.phase, self.confirmedAt, self.holdAt, self.prevPhase = P.Phase.SC_ON_COURSE, nil, nil, nil
  self:_log(now, 'Demo resetat')
  return true, 'Demo resetat'
end

function P:snapshot()
  return { phase = self.phase, confirmedAt = self.confirmedAt, holdAt = self.holdAt, log = self.log,
    isLocalDemo = true }
end

return P
