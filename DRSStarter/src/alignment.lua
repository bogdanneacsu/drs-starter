-- Evaluarea alinierii la linia de start. Pur: primește un eșantion al mașinii și o configurație validată.
-- Un rezultat ALIGNED este o indicație locală pentru pilot, nu o dovadă sportivă.

local V = require('src/vec')
local C = require('src/config')

local A = {}

A.State = {
  NO_CONFIG = 'NO_CONFIG',
  INVALID_CONFIG = 'INVALID_CONFIG',
  NO_CAR = 'NO_CAR',
  SUSPENDED = 'SUSPENDED',            -- replay / pauză / meniu
  FAR = 'FAR',
  WRONG_DIRECTION = 'WRONG_DIRECTION',
  APPROACHING = 'APPROACHING',
  OFF_LANE = 'OFF_LANE',
  TOO_FAR_BACK = 'TOO_FAR_BACK',
  TOO_FAR_FORWARD = 'TOO_FAR_FORWARD',
  BAD_HEADING = 'BAD_HEADING',
  STEER_NOT_STRAIGHT = 'STEER_NOT_STRAIGHT',
  APPROX_REFERENCE = 'APPROX_REFERENCE', -- în zonă, dar doar cu referința aproximativă (bara față): niciodată verde
  MOVING = 'MOVING',
  STABILIZING = 'STABILIZING',
  ALIGNED = 'ALIGNED',
}
local S = A.State

--- Alege punctul de referință al axei față din eșantion.
--- sample.frontContact = {FL, FR} | sample.frontHub = {FL, FR} | sample.bumper
---@return table|nil point, string kind ('contact'|'hub'|'bumper')
function A.referencePoint(sample)
  local fc = sample.frontContact
  if fc and V.isFinite(fc[1]) and V.isFinite(fc[2]) then return V.mid(fc[1], fc[2]), 'contact' end
  local fh = sample.frontHub
  if fh and V.isFinite(fh[1]) and V.isFinite(fh[2]) then return V.mid(fh[1], fh[2]), 'hub' end
  if V.isFinite(sample.bumper) then return V.from(sample.bumper), 'bumper' end
  return nil, nil
end

--- Geometrie pură: distanța cu semn față de țintă, abaterea laterală, unghiul.
--- line.p0 / line.forward sunt deja validate (forward orizontal, normalizat).
function A.measure(point, look, line, target)
  local f = line.forward
  local s = V.new(f.z, 0, -f.x)
  local rel = V.flat(V.sub(point, line.p0))
  local along = V.dot(rel, f)                  -- față de linie (pozitiv = după linie)
  return {
    alongLine = along,
    d = along - target.offset_m,               -- față de țintă (0 = exact; <0 prea în spate; >0 prea în față)
    lateral = V.dot(rel, s),
    heading = V.angleDeg(V.flat(look), f),
    distanceToLine = V.len(rel),
  }
end

local function absf(x) return x < 0 and -x or x end

--- Evaluator cu memorie (stabilitate 1 s, histerezis, avertisment de pierdere a alinierii).
local Tracker = {}
Tracker.__index = Tracker

function A.newTracker() return setmetatable({ alignedSince = nil, stableStart = nil, stableAnchor = nil,
  wasAligned = false, lostAt = nil }, Tracker) end

-- Resetează doar temporizatorul de stabilitate; `wasAligned` este gestionat de finish() (avertisment de pierdere).
function Tracker:reset()
  self.stableStart, self.stableAnchor = nil, nil
end

---@param sample table|nil {frontContact, frontHub, bumper, look, speedKmh, steerDeg}
---@param cfg table|nil configurație validată (start_config.validate)
---@param now number secunde, ceas monoton
---@param opts table|nil {suspended=bool, configError=string}
function Tracker:evaluate(sample, cfg, now, opts)
  opts = opts or {}
  local result = { state = nil, now = now, alignmentLost = false }

  local function finish(state)
    result.state = state
    if state == S.ALIGNED then
      self.wasAligned = true
      self.lostAt = nil
    else
      if self.wasAligned and state ~= S.SUSPENDED then self.lostAt = now end
      self.wasAligned = false
    end
    result.alignmentLost = self.lostAt ~= nil and (now - self.lostAt) <= C.ALIGNMENT_LOST_WARN_S
      and state ~= S.ALIGNED
    return result
  end

  if opts.configError then self:reset(); result.error = opts.configError; return finish(S.INVALID_CONFIG) end
  if not cfg then self:reset(); return finish(S.NO_CONFIG) end
  if opts.suspended then self:reset(); return finish(S.SUSPENDED) end
  if not sample or not V.isFinite(sample.look) or type(sample.speedKmh) ~= 'number' then
    self:reset(); return finish(S.NO_CAR)
  end

  local point, kind = A.referencePoint(sample)
  if not point then self:reset(); return finish(S.NO_CAR) end

  local t, st = cfg.target, cfg.stationary
  local m = A.measure(point, sample.look, cfg.line, t)
  result.measure, result.reference, result.point = m, kind, point

  local hd = self.wasAligned and C.HYST_DISTANCE_M or 0
  local hh = self.wasAligned and C.HYST_HEADING_DEG or 0
  local speedLimit = self.wasAligned and C.HYST_SPEED_KMH or st.max_speed_kmh

  if m.distanceToLine > cfg.approach_radius_m then self:reset(); return finish(S.FAR) end
  if m.heading > 90 then self:reset(); return finish(S.WRONG_DIRECTION) end
  if absf(m.lateral) > t.max_lateral_m then self:reset(); return finish(S.OFF_LANE) end

  local inLong = m.d >= -(t.tol_back_m + hd) and m.d <= (t.tol_fwd_m + hd)
  if not inLong then
    self:reset()
    if m.distanceToLine > C.ALIGNING_RADIUS_M and m.d < 0 then return finish(S.APPROACHING) end
    return finish(m.d < 0 and S.TOO_FAR_BACK or S.TOO_FAR_FORWARD)
  end
  if m.heading > t.max_heading_deg + hh then self:reset(); return finish(S.BAD_HEADING) end
  if t.max_steer_deg and t.max_steer_deg > 0 and type(sample.steerDeg) == 'number'
      and absf(sample.steerDeg) > t.max_steer_deg then
    self:reset(); return finish(S.STEER_NOT_STRAIGHT)
  end
  if kind == 'bumper' then self:reset(); return finish(S.APPROX_REFERENCE) end
  if sample.speedKmh > speedLimit then self:reset(); return finish(S.MOVING) end

  -- Stabilitate: condiții continue hold_s și deriva punctului sub max_drift_m.
  local driftLimit = st.max_drift_m + (self.wasAligned and C.HYST_DISTANCE_M or 0)
  if not self.stableStart or V.len(V.flat(V.sub(point, self.stableAnchor))) > driftLimit then
    local wasAligned = self.wasAligned
    self.stableStart, self.stableAnchor = now, point
    if wasAligned then result.stableFor = 0; return finish(S.STABILIZING) end
  end
  result.stableFor = now - self.stableStart
  if result.stableFor + 1e-9 < st.hold_s and not self.wasAligned then return finish(S.STABILIZING) end
  return finish(S.ALIGNED)
end

A.Tracker = Tracker
return A
