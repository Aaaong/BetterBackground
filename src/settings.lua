-- Settings menu: a "Background" tab in the game's own Settings window (Options > Settings), built
-- from the game's toggles and option cycles so it needs nothing but Lovely. With Steamodded the
-- same page is also the mod's config tab.
--
-- The tab is added at runtime: while create_UIBox_settings runs, create_tabs gets one more tab.

local Config = require("better_background.config")
local hooks = require("better_background.hooks")

local M = {}

M.TAB_LABEL = "Background"

local function weather_choices()
  local bg = require("better_background.background")
  local values, labels = { "none", "random", "cycle" }, { "Off", "Random", "Cycle" }
  for _, k in ipairs(bg.KINDS) do
    values[#values + 1] = k
    labels[#labels + 1] = bg.NAMES[k] or k
  end
  return values, labels
end

local function cycle_label(v)
  if v < 60 then return v .. " sec" end
  return (v / 60) .. " min"
end

-- Each cycle: key, label, values, labels (same order).
local function cycles()
  local bg = require("better_background.background")
  local calm = require("better_background.calm")
  local wv, wl = weather_choices()
  local cv, cl = {}, {}
  for _, v in ipairs(bg.CYCLE_TIMES) do cv[#cv + 1], cl[#cl + 1] = v, cycle_label(v) end
  local clouds = { "default", "none", "light", "normal", "heavy" }
  local cloud_labels = {}
  for i, v in ipairs(clouds) do cloud_labels[i] = bg.CLOUD_NAMES[v] or v end
  local modes, mode_labels = {}, {}
  for i, v in ipairs(calm.MODES) do modes[i], mode_labels[i] = v, calm.NAMES[v] or v end
  return {
    { "bg_weather", "Weather", wv, wl },
    { "bg_cycle", "Cycle every", cv, cl },
    { "bg_clouds", "Clouds", clouds, cloud_labels },
    { "bg_season", "Season", { "auto", "random", "spring", "summer", "autumn", "winter" },
      { "Auto", "Random", "Spring", "Summer", "Autumn", "Winter" } },
    { "calm_mode", "Calm swirl", modes, mode_labels },
  }
end

M.TOGGLES = {
  { "background", "Weather background" },
  { "bg_stars", "Starry night" },
  { "bg_shooting", "Shooting stars" },
  { "bg_sunset", "Sunset" },
  { "bg_fireflies", "Fireflies" },
  { "bg_leaves", "Falling leaves" },
  { "bg_ground", "Grass" },
  { "calm", "Calm Balatro background" },
  { "calm_soften", "Soften colours" },
  { "fade", "Fade between windows" },
}

local function row(node) return { n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = { node } } end

local function option_cycle(key, label, values, labels)
  local current = 1
  for i, v in ipairs(values) do
    if v == Config.get(key) then current = i end
  end
  local fn = "better_background_cycle_" .. key
  G.FUNCS[fn] = function(args)
    local v = values[args and args.to_key or 1]
    if v ~= nil then Config.set(key, v) end
  end
  return create_option_cycle({ label = label, options = labels, current_option = current, opt_callback = fn,
    scale = 0.7, w = 3.6, colour = G.C.RED })
end

local function toggle(key, label)
  return create_toggle({ label = label, ref_table = Config.values, ref_value = key, label_scale = 0.32, w = 3.4,
    callback = function() Config.save() end })
end

-- The page itself: option cycles on the left, switches on the right.
function M.page()
  if M.active == false then
    return { n = G.UIT.ROOT, config = { align = "cm", padding = 0.2, colour = G.C.CLEAR }, nodes = {
      row({ n = G.UIT.T, config = { text = "Chromite is installed and draws its own background.",
        scale = 0.4, colour = G.C.UI.TEXT_LIGHT } }),
      row({ n = G.UIT.T, config = { text = "Better Background is switched off while it is.",
        scale = 0.4, colour = G.C.UI.TEXT_LIGHT } }),
    } }
  end
  local left, right = {}, {}
  for _, c in ipairs(cycles()) do left[#left + 1] = row(option_cycle(c[1], c[2], c[3], c[4])) end
  for _, t in ipairs(M.TOGGLES) do right[#right + 1] = row(toggle(t[1], t[2])) end
  return { n = G.UIT.ROOT, config = { align = "cm", padding = 0.05, colour = G.C.CLEAR }, nodes = {
    { n = G.UIT.R, config = { align = "tm", padding = 0.05 }, nodes = {
      { n = G.UIT.C, config = { align = "tm", padding = 0.05 }, nodes = left },
      { n = G.UIT.C, config = { align = "tm", padding = 0.05 }, nodes = right },
    } },
  } }
end

-- Adds the tab to the game's Settings window. Installed after Game:start_up (Steamodded replaces
-- some UI functions while it runs).
function M.install()
  if M.installed or type(create_UIBox_settings) ~= "function" or type(create_tabs) ~= "function" then return end
  M.installed = true
  local building = false
  hooks.wrap(_G, "create_UIBox_settings", function(orig)
    return function(...)
      building = true
      local ok, res = pcall(orig, ...)
      building = false
      if not ok then error(res, 0) end
      return res
    end
  end, { label = "create_UIBox_settings (background tab)" })
  hooks.wrap(_G, "create_tabs", function(orig)
    return function(args, ...)
      if building and type(args) == "table" and type(args.tabs) == "table" then
        building = false -- only the window's own tab row
        args.tabs[#args.tabs + 1] = { label = M.TAB_LABEL, tab_definition_function = M.page }
      end
      return orig(args, ...)
    end
  end, { label = "create_tabs (background tab)" })
end

-- Steamodded's config tab for this mod.
function M.attach_smods(mod)
  if type(mod) ~= "table" then return end
  mod.config_tab = function() return M.page() end
end

return M
