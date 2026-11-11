-- DRS Starter: constante și valori implicite.
-- Valorile de aliniere sunt implicite de inginerie, NEVALIDATE în joc (vezi ARCHITECTURE.md §8.4).
-- Fișier pur: nu folosește API-ul CSP.

local M = {}

M.APP_VERSION = '0.3.0'

-- Build-ul CSP aprobat de organizator. Ținta: CSP 0.3.1 public (build 4302, sursa: arhiva comunitară
-- c1xtz.github.io/csp-logs). De confirmat în Content Manager; dacă diferă, se schimbă AICI.
M.APPROVED_CSP_BUILD = 4302
M.APPROVED_CSP_LABEL = '0.3.1'

-- Countdown local de test (Faza 1). NU este programul oficial de start (Faza 2: 50 s ± 10 s, din server).
M.LOCAL_COUNTDOWN_S = 40
M.LOCAL_GO_FLASH_S = 1.5
M.LOCAL_ANCHOR_MAX_AGE_S = 3600

-- Valori implicite pentru o configurație de start nouă (calibrare).
M.DEFAULT_TARGET = {
  offset_m = -0.30,       -- axa față la 30 cm ÎN SPATELE liniei
  tol_back_m = 0.175,     -- zona verde 35 cm (±17,5 cm): mărită cu 15 cm la cererea organizatorului (11.11.2026)
  tol_fwd_m = 0.175,
  max_lateral_m = 4.0,
  max_heading_deg = 8.0,
  max_steer_deg = 0,      -- 0 = verificare bracare dezactivată (de măsurat în joc)
}
M.DEFAULT_STATIONARY = {
  max_speed_kmh = 0.5,
  hold_s = 1.0,
  max_drift_m = 0.02,
}
M.DEFAULT_LINE_WIDTH_M = 8.0
M.DEFAULT_APPROACH_RADIUS_M = 80

-- Histerezis la ieșirea din starea ALIGNED (evită clipirea indicatorului).
M.HYST_DISTANCE_M = 0.02
M.HYST_HEADING_DEG = 1.0
M.HYST_SPEED_KMH = 1.0

-- Cât timp rămâne vizibil avertismentul „ai ieșit din aliniere”.
M.ALIGNMENT_LOST_WARN_S = 3.0

-- Distanța sub care se afișează „ALINIERE” în loc de „APROPIERE”.
M.ALIGNING_RADIUS_M = 6.0

-- Calibrare: durata de mediere a capturii.
M.CAPTURE_DURATION_S = 1.0

-- Încălzirea anvelopelor (integrată din scriptul organizatorului warm_tyres.lua). Valori fixe, fără UI pentru pilot.
-- Activă de la ieșirea din boxe până la STOP_RADIUS_M de linia de start; se re-armează doar în boxe („back to pits”).
M.WARM_TYRES = {
  enabled = true,
  stop_radius_m = 20,     -- la ce distanță (m) de linia de start se oprește încălzirea
  temp_offset_c = 0,      -- grade în plus/minus față de temperatura optimă a anvelopei
  interval_s = 0.25,      -- la câte secunde se reaplică temperatura
}

-- Interfața se minimizează după plecare (sau dacă mașina a trecut de linie cu viteză) și revine mare în boxe.
M.ON_RUN_PAST_LINE_M = 10
M.ON_RUN_MIN_SPEED_KMH = 15

return M
