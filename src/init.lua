-- Better Background: Chromite's weather background, Calm Balatro Background and window fading as a
-- mod of their own, until Chromite is released. Needs only Lovely; works with Steamodded too.
--
-- Lovely loads every file under src/ as a module (lovely/core.toml) and appends src/bootstrap.lua
-- to main.lua, which calls boot() before love.load.

local B = { VERSION = "1.0.0" }
BetterBackground = B

local function log(fmt, ...) print("[Better Background] " .. string.format(fmt, ...)) end

-- Chromite has all three features itself: when it is installed, this mod steps aside.
function B.chromite_installed()
  return rawget(_G, "Chromite") ~= nil or package.preload["chromite"] ~= nil
end

local function set_active(on)
  B.active = on
  B.background.active, B.calm.active, B.fade.active, B.settings.active = on, on, on, on
end

local function after_start_up()
  B.hooks.run_late()
  if B.chromite_installed() then
    set_active(false)
    log("Chromite is installed and has these features; Better Background is switched off")
  end
  B.background.install()
  B.calm.install()
  pcall(B.fade.install)
  B.settings.install()
  log("%s ready", B.VERSION)
end

function B.boot()
  if B.booted then return true end
  B.booted = true
  B.hooks = require("better_background.hooks")
  B.config = require("better_background.config")
  B.background = require("better_background.background")
  B.calm = require("better_background.calm")
  B.fade = require("better_background.fade")
  B.settings = require("better_background.settings")
  B.config.load()
  set_active(true)
  B.hooks.wrap(Game, "start_up", function(orig)
    return function(self, ...)
      local ret = orig(self, ...)
      local ok, err = pcall(after_start_up)
      if not ok then log("failed to start: %s", tostring(err)) end
      return ret
    end
  end, { label = "Game:start_up (better background ready)" })
  return true
end

-- Called by steamodded.lua when Steamodded loads the mod.
function B.attach_smods(mod)
  B.smods_mod = mod
  if B.settings then B.settings.attach_smods(mod) end
end

return B
