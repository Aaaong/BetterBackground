-- Settings: one flat table, saved to config/better_background.lua in the game's save folder.
-- Keys are the ones Chromite uses under global.ui (bg_*, fade) plus calm_*.

local M = {}

M.FILE = "config/better_background.lua"

M.DEFAULTS = {
  background = true,     -- the weather scene behind the game
  bg_weather = "random", -- "none", "random", "cycle" or a kind from background.KINDS
  bg_cycle = 60,
  bg_clouds = "default",
  bg_season = "auto",
  bg_stars = false,
  bg_shooting = false,
  bg_sunset = false,
  bg_fireflies = false,
  bg_leaves = true,
  bg_ground = true,
  calm = false,          -- Calm Balatro Background
  calm_mode = "slow",
  calm_soften = true,
  fade = true,           -- windows fade into each other
}

M.values = {}
for k, v in pairs(M.DEFAULTS) do M.values[k] = v end

function M.get(key)
  local v = M.values[key]
  if v == nil then return M.DEFAULTS[key] end
  return v
end

function M.set(key, value)
  if M.values[key] == value then return end
  M.values[key] = value
  M.save()
end

local function fs() return type(love) == "table" and love.filesystem end

-- Only known keys with a value of the default's type are kept, so an old or hand-edited file can't
-- break anything.
function M.load()
  local f = fs()
  if not (f and f.getInfo and f.getInfo(M.FILE)) then return end
  local ok, data = pcall(function()
    local chunk = assert(loadstring(f.read(M.FILE)))
    setfenv(chunk, {})
    return chunk()
  end)
  if not ok or type(data) ~= "table" then return end
  for k, def in pairs(M.DEFAULTS) do
    if type(data[k]) == type(def) then M.values[k] = data[k] end
  end
end

function M.save()
  local f = fs()
  if not (f and f.write) then return end
  local keys = {}
  for k in pairs(M.DEFAULTS) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = { "return {" }
  for _, k in ipairs(keys) do
    local v = M.get(k)
    local s = type(v) == "string" and string.format("%q", v) or tostring(v)
    out[#out + 1] = string.format("  %s = %s,", k, s)
  end
  out[#out + 1] = "}"
  pcall(function()
    if f.getInfo and not f.getInfo("config") then f.createDirectory("config") end
    f.write(M.FILE, table.concat(out, "\n") .. "\n")
  end)
end

return M
