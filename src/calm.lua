-- Calm Background: slows or stills the swirling background shader, and can tone down its colour
-- contrast. Visual only.
-- From Chromite's features/calm_background.lua. Settings: calm (on/off), calm_mode, calm_soften.
--
-- The 'background' shader on G.SPLASH_BACK moves with two clocks it reads when it is drawn:
--   time      <- G.TIMERS.REAL_SHADER (TIMERS.REAL each Game:update, or held with Reduced Motion)
--   spin_time <- G.TIMERS.BACKGROUND (advances by dt * G.ARGS.spin.amount)
-- and `contrast` <- G.C.BACKGROUND.contrast, which packs ease up to 2-3.
-- Game:draw is wrapped: for the length of the draw those three values are swapped for calm ones,
-- then put back, so nothing the game keeps changes.

local Config = require("better_background.config")
local CB = {
  MODES = { "slow", "still" },
  SLOW = 0.25,       -- fraction of normal speed in "slow"
  SOFT_CONTRAST = 1, -- the contrast of a normal round
  state = nil,       -- calm clocks, carried from frame to frame
}

function CB.reset() CB.state = nil end

function CB.factor(mode)
  if mode == "still" then return 0 end
  return CB.SLOW
end

-- Advances the calm clocks and returns the values to draw with. real_shader / background are the
-- game's clocks this frame, dt its real_dt.
function CB.step(real_shader, background, dt, factor)
  local s = CB.state
  if not s then
    s = { time = real_shader, spin = background, last_spin = background }
    CB.state = s
    return s.time, s.spin
  end
  dt = (type(dt) == "number" and dt > 0 and dt < 1) and dt or 0
  s.time = s.time + dt * factor
  local d = background - s.last_spin
  if d ~= d or math.abs(d) > 1e6 then d = 0 end -- new run or timer reset
  s.spin = s.spin + d * factor
  s.last_spin = background
  return s.time, s.spin
end

-- Whether the background should be calmed this frame.
function CB.calming()
  local T = type(G) == "table" and G.TIMERS
  if type(T) ~= "table" or type(T.REAL_SHADER) ~= "number" or type(T.BACKGROUND) ~= "number" then return false end
  -- the game's own Reduced Motion already holds the swirl still
  if G.SETTINGS and G.SETTINGS.reduced_motion then return false end
  -- leave the intro splash alone
  if G.STATES and G.STATE ~= nil and G.STATE == G.STATES.SPLASH then return false end
  return true
end

CB.NAMES = { slow = "Slow", still = "Still" }

-- Wraps Game:draw: for the length of the draw the clocks (and contrast) are swapped for calm ones.
-- CB.active is false while Chromite is installed: it has this feature itself.
function CB.install()
  if CB.hook then return end
  CB.reset()
  local hooks = require("better_background.hooks")
  CB.hook = hooks.wrap(Game, "draw", function(orig)
    return function(self, ...)
      if not (CB.active ~= false and Config.get("calm") and CB.calming()) then
        CB.reset()
        return orig(self, ...)
      end
      local T, bg = G.TIMERS, G.C and G.C.BACKGROUND
      local real_shader, background = T.REAL_SHADER, T.BACKGROUND
      local contrast = type(bg) == "table" and bg.contrast or nil
      local t, spin = CB.step(real_shader, background, G.real_dt, CB.factor(Config.get("calm_mode")))
      T.REAL_SHADER, T.BACKGROUND = t, spin
      if type(contrast) == "number" and Config.get("calm_soften") and contrast > CB.SOFT_CONTRAST then
        bg.contrast = CB.SOFT_CONTRAST
      end
      local ok, err = pcall(orig, self, ...)
      T.REAL_SHADER, T.BACKGROUND = real_shader, background
      if contrast ~= nil then bg.contrast = contrast end
      if not ok then error(err, 0) end
    end
  end, { label = "Game:draw (calm background)" })
end

return CB
