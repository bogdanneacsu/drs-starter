-- Stil DRS: culori din drs-design-system/tokens.json și fonturile DRS livrate cu aplicația.
-- Folosește API-ul CSP (rgbm, ui.DWriteFont); se încarcă doar în joc.

local M = {}

local function hex(h, a)
  return rgbm(tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255, a or 1)
end
M.hex = hex

-- Tokenuri DRS (valori exacte din tokens.json). Culorile de stare: vezi ARCHITECTURE.md §12 (abatere de aprobat).
M.color = {
  panel = hex('#231f20', 0.90),        -- fras-black / inverse, panou opac 90 %
  panelSoft = hex('#231f20', 0.72),
  edge = hex('#8a8d93', 0.35),         -- drs-gray ca linie decorativă
  orange = hex('#ff5a1f'),             -- drs-orange: accent, titluri, cifre mari
  orangeStart = hex('#ffa05c'),        -- gradient-orange-start
  orangeEnd = hex('#e8430c'),          -- gradient-orange-end
  white = hex('#ffffff'),              -- on-inverse
  gray = hex('#8a8d93'),               -- drs-gray: meta pe negru (4,9:1)
  grayLight = hex('#d9dadd'),          -- drs-gray-light
  ok = hex('#15803d'),                 -- positive (umplere, text alb)
  okSoft = hex('#15803d', 0.35),
  bad = hex('#cf2028'),                -- fras-red / negative
  badSoft = hex('#cf2028', 0.30),
  warn = hex('#fbd013'),               -- fras-yellow (text negru pe el)
  black = hex('#231f20'),
  transparent = rgbm(0, 0, 0, 0),
}

local fontDir = __dirname .. '/fonts'
local W, St = ui.DWriteFont.Weight, ui.DWriteFont.Style
-- Barlow Condensed ExtraBold (800 = UltraBold) pentru titluri, etichete și cifre; italic pentru cifre.
M.font = {
  display = ui.DWriteFont('Barlow Condensed', fontDir):weight(W.UltraBold),
  number = ui.DWriteFont('Barlow Condensed', fontDir):weight(W.UltraBold):style(St.Italic),
  body = ui.DWriteFont('Inter', fontDir):weight(W.Regular),
  bodyBold = ui.DWriteFont('Inter', fontDir):weight(W.SemiBold),
}

M.radius = { sm = 4, md = 8 }
M.logo = __dirname .. '/img/drs-logo-on-dark.png'

return M
