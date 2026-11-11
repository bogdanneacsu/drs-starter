-- Teste automate pentru modulele pure DRS Starter.
-- Rulare (din folderul proiectului):  luajit tests/run.lua
-- Nu folosesc API-ul CSP; nu dovedesc comportamentul în joc.

package.path = './DRSStarter/?.lua;' .. package.path

local V = require('src/vec')
local Countdown = require('src/countdown')
local A = require('src/alignment')
local SC = require('src/start_config')
local Cal = require('src/calibration')
local P = require('src/procedure_local')

local passed, failed, current = 0, 0, ''
local function test(name, fn)
  current = name
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; print('  ok   ' .. name)
  else failed = failed + 1; print('  FAIL ' .. name .. '\n       ' .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or '') .. ' expected ' .. tostring(b) .. ', got ' .. tostring(a), 2) end end
local function near(a, b, eps, msg) if math.abs(a - b) > (eps or 1e-6) then error((msg or '') .. ' expected ~' .. b .. ', got ' .. a, 2) end end
local function truthy(v, msg) if not v then error(msg or 'expected truthy', 2) end end

-- ───────────────────────── Countdown ─────────────────────────
print('Countdown')
test('stare inițială 40', function()
  local c = Countdown.new(40, 100)
  local s = c:update(100)
  eq(s.display, 40); near(s.remaining, 40); eq(s.cycleCompleted, false)
end)
test('decrementare pe timp scurs, nu pe cadre', function()
  local c = Countdown.new(40, 0)
  eq(c:update(0.5).display, 40)
  eq(c:update(1.0).display, 39)
  eq(c:update(39.2).display, 1)
  near(c:update(10.25).remaining, 29.75)
end)
test('reset la zero și semnal o singură dată', function()
  local c = Countdown.new(40, 0)
  c:update(39.99)
  local s = c:update(40.0)
  eq(s.cycleCompleted, true); eq(s.display, 40); eq(s.cycle, 1)
  eq(c:update(40.01).cycleCompleted, false)
end)
test('cicluri repetate fără drift (10000 de cadre neregulate)', function()
  local c = Countdown.new(40, 0)
  local t, completions = 0, 0
  math.randomseed(7)
  while t < 400 do
    t = t + 0.005 + math.random() * 0.03
    if c:update(t).cycleCompleted then completions = completions + 1 end
  end
  eq(completions, math.floor(t / 40))
  near(c:update(t).remaining, 40 - (t % 40), 1e-9)
end)
test('salt mare de timp (cadru blocat 95 s)', function()
  local c = Countdown.new(40, 0)
  c:update(1)
  local s = c:update(96)
  eq(s.cycleCompleted, true); eq(s.cyclesSkipped, 1); eq(s.cycle, 2)
  near(s.remaining, 24)
end)
test('pauză și reluare păstrează timpul rămas', function()
  local c = Countdown.new(40, 0)
  c:update(10); c:pause(10)
  local s = c:update(500)
  eq(s.paused, true); near(s.remaining, 30)
  c:resume(500)
  near(c:update(500).remaining, 30); near(c:update(505).remaining, 25)
  eq(c:update(530.0).cycleCompleted, true)
end)
test('ancoră restaurată după reîncărcare', function()
  local c = Countdown.new(40, 1000, 1000 - 85)
  near(c:update(1000).remaining, 35)
  eq(c:update(1000).cycleCompleted, false)
  truthy(Countdown.isAnchorUsable(900, 1000, 3600))
  truthy(not Countdown.isAnchorUsable(2000, 1000, 3600), 'ancoră în viitor')
  truthy(not Countdown.isAnchorUsable(0, 5000, 3600), 'ancoră prea veche')
end)
test('durată configurabilă', function()
  local c = Countdown.new(10, 0)
  eq(c:update(0).display, 10); eq(c:update(10).cycleCompleted, true)
end)

-- ───────────────────────── Aliniere ─────────────────────────
print('Aliniere')
local function cfgFor(over)
  local e = { id = 't/-/up', track = 't', line = { p0 = { 0, 0, 0 }, forward = { 0, 0, 1 } } }
  for k, v in pairs(over or {}) do e[k] = v end
  return assert(SC.validate(e))
end
-- Mașină cu axa față la coordonata z (de-a lungul direcției de mers +Z), ecartament 1,6 m.
local function sample(z, opts)
  opts = opts or {}
  local x = opts.x or 0
  local yaw = math.rad(opts.yawDeg or 0)
  local look = V.new(math.sin(yaw), 0, math.cos(yaw))
  return {
    frontContact = (not opts.noWheels) and { V.new(x - 0.8, 0, z), V.new(x + 0.8, 0, z) } or nil,
    bumper = V.new(x, 0.3, z + 0.9),
    look = look, speedKmh = opts.speed or 0, steerDeg = opts.steer or 0,
  }
end
local S = A.State
local function settle(tr, cfg, smp, t0, dur)
  local r
  for t = t0, t0 + dur, 0.05 do r = tr:evaluate(smp, cfg, t) end
  return r
end

test('țintă 30 cm în spatele liniei, aliniat după 1 s stabil', function()
  local cfg, tr = cfgFor(), A.newTracker()
  local r = tr:evaluate(sample(-0.30), cfg, 0)
  eq(r.state, S.STABILIZING); near(r.measure.d, 0, 1e-9); near(r.measure.alongLine, -0.30, 1e-9)
  r = settle(tr, cfg, sample(-0.30), 0.05, 0.9)
  eq(r.state, S.STABILIZING, 'înainte de 1 s')
  eq(tr:evaluate(sample(-0.30), cfg, 1.0).state, S.ALIGNED)
end)
test('toleranță longitudinală ±10 cm', function()
  local cfg = cfgFor()
  eq(settle(A.newTracker(), cfg, sample(-0.39), 0, 1.2).state, S.ALIGNED, '-9 cm')
  eq(settle(A.newTracker(), cfg, sample(-0.21), 0, 1.2).state, S.ALIGNED, '+9 cm')
  eq(A.newTracker():evaluate(sample(-0.41), cfg, 0).state, S.TOO_FAR_BACK, '-11 cm')
  eq(A.newTracker():evaluate(sample(-0.19), cfg, 0).state, S.TOO_FAR_FORWARD, '+11 cm')
  eq(A.newTracker():evaluate(sample(0.5), cfg, 0).state, S.TOO_FAR_FORWARD, 'după linie')
end)
test('departe în spate = APROPIERE, foarte departe = FAR', function()
  local cfg = cfgFor()
  eq(A.newTracker():evaluate(sample(-20), cfg, 0).state, S.APPROACHING)
  eq(A.newTracker():evaluate(sample(-3), cfg, 0).state, S.TOO_FAR_BACK)
  eq(A.newTracker():evaluate(sample(-200), cfg, 0).state, S.FAR)
end)
test('toleranță de orientare 8°', function()
  local cfg = cfgFor()
  eq(settle(A.newTracker(), cfg, sample(-0.30, { yawDeg = 7.5 }), 0, 1.2).state, S.ALIGNED)
  eq(A.newTracker():evaluate(sample(-0.30, { yawDeg = 8.5 }), cfg, 0).state, S.BAD_HEADING)
  eq(A.newTracker():evaluate(sample(-0.30, { yawDeg = 175 }), cfg, 0).state, S.WRONG_DIRECTION)
end)
test('mișcare: viteză peste 0,5 km/h nu e aliniată', function()
  local cfg = cfgFor()
  eq(settle(A.newTracker(), cfg, sample(-0.30, { speed = 0.6 }), 0, 2).state, S.MOVING)
end)
test('alunecare lentă (drift > 2 cm) repornește stabilizarea', function()
  local cfg, tr = cfgFor(), A.newTracker()
  local r
  for i = 0, 40 do r = tr:evaluate(sample(-0.38 + i * 0.002, { speed = 0.2 }), cfg, i * 0.05) end
  truthy(r.state ~= S.ALIGNED, 'nu trebuie să fie aliniat, a fost ' .. r.state)
end)
test('histerezis: rămâne aliniat la +10,5 cm, iese la +12,5 cm cu avertisment', function()
  local cfg, tr = cfgFor(), A.newTracker()
  settle(tr, cfg, sample(-0.205), 0, 1.2)
  eq(tr:evaluate(sample(-0.195), cfg, 1.3).state, S.ALIGNED, 'în banda de histerezis')
  local r = tr:evaluate(sample(-0.175), cfg, 1.4)
  eq(r.state, S.TOO_FAR_FORWARD); eq(r.alignmentLost, true)
  eq(tr:evaluate(sample(-0.175), cfg, 5).alignmentLost, false, 'avertismentul expiră după 3 s')
end)
test('referință aproximativă (fără roți) nu dă niciodată verde', function()
  local cfg = cfgFor()
  local s = sample(-1.2, { noWheels = true }) -- bara față la z = -0.30
  eq(settle(A.newTracker(), cfg, s, 0, 2).state, S.APPROX_REFERENCE)
end)
test('lateral în afara culoarului', function()
  eq(A.newTracker():evaluate(sample(-0.30, { x = 5 }), cfgFor(), 0).state, S.OFF_LANE)
end)
test('verificare bracare, dacă e activată', function()
  local cfg = cfgFor({ target = { max_steer_deg = 5 } })
  eq(A.newTracker():evaluate(sample(-0.30, { steer = 30 }), cfg, 0).state, S.STEER_NOT_STRAIGHT)
end)
test('linie oblică și traseu invers (forward opus)', function()
  local f = V.normalize(V.new(1, 0, 1))
  local cfg = assert(SC.validate({ id = 'r', track = 't', route = 'down',
    line = { p0 = { 100, 5, 100 }, forward = { -f.x, 0, -f.z } } }))
  local front = V.add(V.new(100, 5, 100), V.scale(V.new(-f.x, 0, -f.z), -0.30))
  local s = { frontContact = { front, front }, look = V.new(-f.x, 0, -f.z), speedKmh = 0 }
  eq(settle(A.newTracker(), cfg, s, 0, 1.2).state, S.ALIGNED)
  s.look = V.new(f.x, 0, f.z)
  eq(A.newTracker():evaluate(s, cfg, 0).state, S.WRONG_DIRECTION)
end)
test('panta (diferență de înălțime) nu afectează distanța orizontală', function()
  local cfg = cfgFor()
  local s = sample(-0.30); s.frontContact[1].y = 3; s.frontContact[2].y = 3
  near(A.newTracker():evaluate(s, cfg, 0).measure.d, 0, 1e-9)
end)

-- ───────────────────────── Configurație ─────────────────────────
print('Configurație')
test('fără configurație → NO_CONFIG', function()
  eq(A.newTracker():evaluate(sample(-0.3), nil, 0).state, S.NO_CONFIG)
end)
test('configurație invalidă → INVALID_CONFIG', function()
  eq(A.newTracker():evaluate(sample(-0.3), nil, 0, { configError = 'x' }).state, S.INVALID_CONFIG)
end)
test('valori invalide respinse', function()
  truthy(not SC.validate({ id = 'a', track = 't', line = { p0 = { 0, 0, 0 }, forward = { 0, 1, 0 } } }), 'forward vertical')
  truthy(not SC.validate({ id = 'a', track = 't', line = { p0 = { 0, 0 / 0, 0 }, forward = { 0, 0, 1 } } }), 'NaN')
  truthy(not SC.validate({ id = 'a', line = { p0 = { 0, 0, 0 }, forward = { 0, 0, 1 } } }), 'fără track')
  truthy(not SC.validate({ id = 'a', track = 't', line = { p0 = { 0, 0, 0 }, forward = { 0, 0, 1 } },
    target = { tol_back_m = 0 } }), 'toleranță 0')
  truthy(not SC.validate({ id = 'a', track = 't', line = { p0 = { 0, 0, 0 }, forward = { 0, 0, 1 } },
    target = { max_heading_deg = 90 } }), 'unghi 90')
  local list, errs = SC.parseDocument({ schema = 2, starts = {} })
  eq(#list, 0); eq(#errs, 1)
end)
test('valori implicite aplicate', function()
  local c = cfgFor()
  near(c.target.offset_m, -0.30); near(c.target.tol_back_m, 0.10); near(c.target.max_heading_deg, 8)
  near(c.stationary.max_speed_kmh, 0.5); near(c.stationary.hold_s, 1.0)
end)
test('selecție după traseu/layout și sens', function()
  local up = assert(SC.validate({ id = 'up', track = 't', layout = 'l', line = { p0 = { 0, 0, 0 }, forward = { 0, 0, 1 } } }))
  local down = assert(SC.validate({ id = 'down', track = 't', layout = 'l', line = { p0 = { 0, 0, 500 }, forward = { 0, 0, -1 } } }))
  local other = assert(SC.validate({ id = 'o', track = 't', layout = 'x', line = { p0 = { 0, 0, 0 }, forward = { 0, 0, 1 } } }))
  local list = SC.forTrack({ up, down, other }, 't', 'l')
  eq(#list, 2)
  eq(#SC.forTrack({ up }, 't', ''), 0, 'layout diferit')
  eq(SC.select(list, nil, V.new(0, 0, 490), V.new(0, 0, -1)).id, 'down')
  eq(SC.select(list, nil, V.new(0, 0, 10), V.new(0, 0, 1)).id, 'up')
  eq(SC.select(list, 'down', V.new(0, 0, 10), V.new(0, 0, 1)).id, 'down', 'preferință explicită')
end)
test('merge: configurația locală înlocuiește pe cea livrată', function()
  local a = cfgFor(); local b = cfgFor({ label = 'local' })
  local m = SC.merge({ a }, { b })
  eq(#m, 1); eq(m[1].label, 'local')
end)

-- ───────────────────────── Calibrare ─────────────────────────
print('Calibrare')
test('captură mediată și dispersie', function()
  local s = {}
  for i = 1, 20 do s[i] = { point = V.new(10 + (i % 2) * 0.004, 0, 20), look = V.new(0, 0, 1), speedKmh = 0, reference = 'contact' } end
  local r = assert(Cal.average(s))
  near(r.p0.x, 10.002, 1e-9); near(r.forward.z, 1); truthy(r.spreadM <= 0.0021)
  local e = Cal.buildEntry({ track = 't', route = 'up', p0 = r.p0, forward = r.forward })
  local cfg = assert(SC.validate(e))
  eq(cfg.id, 't/-/up')
end)
test('captură refuzată dacă mașina se mișcă sau lipsesc roțile', function()
  local s = {}
  for i = 1, 10 do s[i] = { point = V.new(0, 0, 0), look = V.new(0, 0, 1), speedKmh = 0, reference = 'contact' } end
  s[5].speedKmh = 3
  truthy(not Cal.average(s))
  s[5].speedKmh = 0; s[6].reference = 'bumper'
  truthy(not Cal.average(s))
end)
test('linie din nodurile de start, orientată după mașină', function()
  local l = assert(Cal.lineFromNodes(V.new(-4, 0, 50), V.new(4, 0, 50), V.new(0, 0, 1)))
  near(l.p0.z, 50); near(l.width_m, 8); near(l.forward.z, 1)
  local r = assert(Cal.lineFromNodes(V.new(-4, 0, 50), V.new(4, 0, 50), V.new(0, 0, -1)))
  near(r.forward.z, -1)
end)

-- ───────────────────────── Safety Car local ─────────────────────────
print('Safety Car (local demo)')
test('confirmare idempotentă, HOLD și reluare', function()
  local p = P.new()
  eq(p:snapshot().phase, P.Phase.SC_ON_COURSE)
  truthy(p:confirmSafetyCarFinish(1)); truthy(not p:confirmSafetyCarFinish(2), 'a doua apăsare')
  truthy(p:hold(3)); truthy(not p:confirmSafetyCarFinish(4), 'blocat în HOLD')
  truthy(p:release(5)); eq(p:snapshot().phase, P.Phase.SC_AT_FINISH)
  eq(p:snapshot().isLocalDemo, true)
end)

print(string.format('\n%d trecute, %d eșuate', passed, failed))
os.exit(failed == 0 and 0 or 1)
