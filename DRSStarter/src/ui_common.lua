-- Primitive de desen comune (CSP ImGui). Coordonatele sunt în spațiul ferestrei, scalate cu `k`.
local Style = require('src/style')
local Col = Style.color

local U = {}
U.k = 1

function U.setScale(k) U.k = k end
function U.v(x, y) return vec2(x * U.k, y * U.k) end
local function px(n) return math.max(8, math.floor(n * U.k + 0.5)) end -- mărimi întregi: evită atlase de font noi
U.px = px

function U.panel(x, y, w, h, color, edge)
  local p1, p2 = U.v(x, y), U.v(x + w, y + h)
  ui.drawRectFilled(p1, p2, color or Col.panel, Style.radius.md * U.k)
  if edge ~= false then ui.drawRect(p1, p2, edge or Col.edge, Style.radius.md * U.k, nil, 1) end
end

function U.rect(x, y, w, h, color, r)
  ui.drawRectFilled(U.v(x, y), U.v(x + w, y + h), color, (r or 0) * U.k)
end

function U.outline(x, y, w, h, color, r, thickness)
  ui.drawRect(U.v(x, y), U.v(x + w, y + h), color, (r or 0) * U.k, nil, thickness or 1)
end

--- Gradient portocaliu orizontal (stânga → dreapta), ca în design system.
function U.orangeBar(x, y, w, h)
  local half = w * 0.45
  ui.drawRectFilledMultiColor(U.v(x, y), U.v(x + half, y + h), Col.orangeStart, Col.orange, Col.orange, Col.orangeStart)
  ui.drawRectFilledMultiColor(U.v(x + half, y), U.v(x + w, y + h), Col.orange, Col.orangeEnd, Col.orangeEnd, Col.orange)
end

function U.text(str, size, x, y, color, font)
  ui.pushDWriteFont(font or Style.font.display)
  ui.dwriteDrawText(str, px(size), U.v(x, y), color or Col.white)
  ui.popDWriteFont()
end

--- Text aliniat într-o cutie (h/v: ui.Alignment.Start | Center | End).
function U.textBox(str, size, x, y, w, h, color, font, hAlign, vAlign)
  ui.pushDWriteFont(font or Style.font.display)
  ui.setCursor(U.v(x, y))
  ui.dwriteTextAligned(str, px(size), hAlign or ui.Alignment.Center, vAlign or ui.Alignment.Center, U.v(w, h), false,
    color or Col.white)
  ui.popDWriteFont()
end

--- Bifă / X desenate cu linii (fără dependență de un font de iconițe).
function U.check(cx, cy, r, ok)
  local c = U.v(cx, cy)
  ui.drawCircleFilled(c, r * U.k, ok and Col.ok or Col.bad, 24)
  local t = math.max(2, 2.2 * U.k)
  if ok then
    ui.drawLine(c + U.v(-r * 0.45, 0), c + U.v(-r * 0.1, r * 0.38), Col.white, t)
    ui.drawLine(c + U.v(-r * 0.1, r * 0.38), c + U.v(r * 0.5, -r * 0.35), Col.white, t)
  else
    ui.drawLine(c + U.v(-r * 0.38, -r * 0.38), c + U.v(r * 0.38, r * 0.38), Col.white, t)
    ui.drawLine(c + U.v(r * 0.38, -r * 0.38), c + U.v(-r * 0.38, r * 0.38), Col.white, t)
  end
end

--- Buton desenat în stilul DRS. Returnează true la clic.
function U.button(id, label, x, y, w, h, kind, enabled)
  if enabled == nil then enabled = true end
  ui.setCursor(U.v(x, y))
  local clicked = ui.invisibleButton(id, U.v(w, h)) and enabled
  local hovered = enabled and ui.itemHovered()
  if not enabled then
    U.rect(x, y, w, h, Col.panelSoft, Style.radius.sm)
    U.outline(x, y, w, h, Col.edge, Style.radius.sm)
    U.textBox(label, 18, x, y, w, h, Col.gray)
  elseif kind == 'primary' then
    U.orangeBar(x, y, w, h)
    if hovered then U.outline(x, y, w, h, Col.white, Style.radius.sm, 2) end
    U.textBox(label, 20, x, y, w, h, Col.white)
  elseif kind == 'danger' then
    U.rect(x, y, w, h, hovered and Col.bad or Col.badSoft, Style.radius.sm)
    U.outline(x, y, w, h, Col.bad, Style.radius.sm, 2)
    U.textBox(label, 20, x, y, w, h, Col.white)
  else
    U.rect(x, y, w, h, Col.panelSoft, Style.radius.sm)
    U.outline(x, y, w, h, hovered and Col.white or Col.gray, Style.radius.sm, 1)
    U.textBox(label, 18, x, y, w, h, Col.white)
  end
  return clicked
end

--- Bara de sus comună (logo, context, ceas local, stare conexiune REALĂ: ctx.rc = {label, ok}; implicit „local”).
function U.topBar(w, ctx)
  U.panel(0, 0, w, 52, Col.panel)
  ui.drawImage(Style.logo, U.v(12, 6), U.v(12 + 101, 6 + 40))
  U.text('STARTER', 15, 118, 26, Col.orange)
  U.rect(196, 10, 1, 32, Col.edge)
  U.text(ctx.title or '', 16, 210, 8, Col.white)
  U.text(ctx.subtitle or '', 13, 210, 29, Col.gray, Style.font.body)
  U.text(os.date('%H:%M:%S'), 22, w - 262, 13, Col.white, Style.font.number)
  U.rect(w - 168, 10, 1, 32, Col.edge)
  local rc = ctx.rc or { label = 'NECONECTAT · LOCAL', ok = nil }
  ui.drawCircleFilled(U.v(w - 152, 33), 4 * U.k, rc.ok == true and Col.ok or (rc.ok == false and Col.bad or Col.gray), 12)
  U.text('RACE CONTROL', 12, w - 156, 9, Col.gray)
  U.text(rc.label, 12, w - 143, 27, rc.ok == false and Col.white or Col.grayLight)
end

return U
