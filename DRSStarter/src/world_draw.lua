-- Desenează în lume linia de start și zona țintă (callback TRANSPARENT). Doar ghidaj vizual.
-- Limitare: zona este un plan la înălțimea punctului P0; pe un drum cu dever mare poate intra parțial în asfalt.
local Style = require('src/style')
local A = require('src/alignment')

local M = {}

local zoneColor = {
  ok = rgbm(0.08, 0.50, 0.24, 0.45),      -- positive #15803d, translucid
  idle = rgbm(0.08, 0.50, 0.24, 0.22),
  bad = rgbm(0.81, 0.13, 0.16, 0.30),     -- fras-red, translucid
}
local lineWhite = rgbm(2, 2, 2, 1)
local lineOrange = rgbm(2.5, 0.9, 0.3, 1) -- drs-orange, luminozitate HDR ca în exemplele CSP

local function v3(p) return vec3(p.x, p.y, p.z) end

local function quad(a, b, c, d, color)
  render.glSetColor(color)
  render.glBegin(render.GLPrimitiveType.Quads)
  render.glVertex(a); render.glVertex(b); render.glVertex(c); render.glVertex(d)
  render.glEnd()
end

---@param cfg table configurație validată
---@param result table rezultatul evaluării
function M.draw(cfg, result)
  if not cfg then return end
  local p0 = v3(cfg.line.p0)
  local f = vec3(cfg.line.forward.x, 0, cfg.line.forward.z)
  local s = vec3(f.z, 0, -f.x)
  local half = cfg.line.width_m / 2
  local t = cfg.target
  local lift = vec3(0, 0.03, 0)

  local function at(along, across) return p0 + f * along + s * across + lift end

  render.setBlendMode(render.BlendMode.AlphaBlend)
  render.setDepthMode(render.DepthMode.ReadOnlyLessEqual)

  local st = result and result.state
  local col = st == A.State.ALIGNED and zoneColor.ok or
    ((st == A.State.TOO_FAR_FORWARD or st == A.State.WRONG_DIRECTION) and zoneColor.bad or zoneColor.idle)
  local a0, a1 = t.offset_m - t.tol_back_m, t.offset_m + t.tol_fwd_m
  quad(at(a0, -half), at(a1, -half), at(a1, half), at(a0, half), col)

  -- Contur zonă, linia țintă (portocaliu) și linia de start (alb).
  render.debugLine(at(a0, -half), at(a0, half), Style.color.ok)
  render.debugLine(at(a1, -half), at(a1, half), Style.color.ok)
  render.debugLine(at(t.offset_m, -half), at(t.offset_m, half), lineOrange)
  render.debugLine(at(0, -half), at(0, half), lineWhite)

  render.setDepthMode(render.DepthMode.Normal)
  render.setBlendMode(render.BlendMode.Opaque)
end

return M
