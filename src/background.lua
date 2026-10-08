-- Background: a weather scene drawn behind the whole game, over the game's swirling background
-- and under every card and button, so it never blocks anything.
-- From Chromite's ui/background.lua; Chromite's "around its windows" mode is left out (there are
-- no Chromite windows here), so the scene is always drawn behind the game.
--
-- Layers, back to front, each with its own setting (see config.lua):
--   sky      starry night, sunset haze and fireflies: each its own switch
--   shooting shooting stars, their own switch
--   clouds   none, light, normal, heavy, or "default": the weather decides (heavy rain -> heavy);
--            clouds that are no longer wanted fade out where they are
--   weather  sunny, light or heavy rain, snow, thunderstorm, fog, or off; random per start, one kind,
--            or "cycle": a new kind every so often, crossfaded
--   ground   grass along the bottom; leaves land on it and fade
--   leaves   falling leaves from above (colours follow the season), separate from the weather
--
-- Everything is in real screen pixels. It is drawn right after the game's background sprite
-- (G.SPLASH_BACK: M.hook_back); a love.draw hook (M.install) steps the scene every frame.

local Config = require("better_background.config")

local M = {}

M.rng = math.random

M.KINDS = { "sunny", "rain_light", "rain_heavy", "snow", "thunder", "fog" }
M.WEATHERS = M.KINDS
M.NAMES = { sunny = "Sunny", rain_light = "Light rain", rain_heavy = "Heavy rain", snow = "Snow",
  thunder = "Thunderstorm", fog = "Fog", none = "Off" }
M.WEIGHTS = { sunny = 3, rain_light = 2.5, rain_heavy = 1.5, snow = 2.5, thunder = 1, fog = 2 }

-- Sky layers, each its own switch (global.ui.bg_<kind>); drawn in this order.
M.SKIES = { "stars", "sunset", "fireflies" }
M.SKY_NAMES = { none = "None", stars = "Starry night", sunset = "Sunset", fireflies = "Fireflies" }

M.CLOUD_LEVELS = { "none", "light", "normal", "heavy" }
M.CLOUD_NAMES = { default = "Default", none = "No clouds", light = "Light", normal = "Normal", heavy = "Heavy" }
-- What "default" clouds mean for each weather.
M.WEATHER_CLOUDS = { sunny = "light", rain_light = "normal", rain_heavy = "heavy", snow = "normal", thunder = "heavy",
  fog = "light", none = "none" }
M.CLOUD_COUNT = { none = 0, light = 4, normal = 8, heavy = 14 }

M.CYCLE_TIMES = { 30, 60, 120, 300 }
M.CROSSFADE = 2.5 -- seconds a cycled weather takes to give way to the next

-- Seasons by month (northern hemisphere).
function M.season(month)
  if month >= 3 and month <= 5 then return "spring" end
  if month >= 6 and month <= 8 then return "summer" end
  if month >= 9 and month <= 11 then return "autumn" end
  return "winter"
end

-- Leaf colours per season: spring blossom petals, summer greens, autumn reds and golds, winter dry browns.
M.LEAF_COLOURS = {
  spring = { { 1, 0.78, 0.84 }, { 0.98, 0.66, 0.76 }, { 1, 0.88, 0.92 }, { 0.93, 0.58, 0.7 } },
  summer = { { 0.36, 0.62, 0.28 }, { 0.46, 0.72, 0.3 }, { 0.28, 0.52, 0.24 }, { 0.58, 0.76, 0.34 } },
  autumn = { { 0.86, 0.36, 0.16 }, { 0.93, 0.6, 0.18 }, { 0.72, 0.24, 0.14 }, { 0.98, 0.76, 0.26 }, { 0.6, 0.36, 0.18 } },
  winter = { { 0.58, 0.46, 0.34 }, { 0.68, 0.58, 0.46 }, { 0.48, 0.38, 0.3 } },
}
M.GRASS_COLOURS = {
  spring = { 0.3, 0.56, 0.26 }, summer = { 0.26, 0.5, 0.2 }, autumn = { 0.42, 0.46, 0.22 }, winter = { 0.4, 0.42, 0.3 },
}

-- Picks a kind. Snow is likelier in winter and rare in summer.
function M.pick(month)
  local season = M.season(month or 1)
  local w, total = {}, 0
  for _, k in ipairs(M.KINDS) do
    local v = M.WEIGHTS[k]
    if k == "snow" then v = v * (season == "winter" and 2 or season == "summer" and 0.2 or 0.7) end
    if k == "sunny" and season == "summer" then v = v * 1.6 end
    w[k] = v
    total = total + v
  end
  local r = M.rng() * total
  for _, k in ipairs(M.KINDS) do
    r = r - w[k]
    if r <= 0 then return k end
  end
  return M.KINDS[#M.KINDS]
end

local function rand(a, b) return a + M.rng() * (b - a) end

---------------------------------------------------------------- settings

local function ui(key, default)
  local v = Config.get(key)
  if v == nil then return default end
  return v
end

-- M.active is false while Chromite is installed: it draws its own background.
function M.enabled() return M.active ~= false and ui("background", true) ~= false end
function M.everywhere() return true end
function M.leaves_on() return ui("bg_leaves", true) ~= false end
function M.ground_on() return ui("bg_ground", true) ~= false end
function M.shooting_on()
  if M.forced_sky then return M.forced_sky == "shooting" end
  return ui("bg_shooting", false) == true
end
function M.cycling() return M.forced == nil and ui("bg_weather", "random") == "cycle" end
function M.cycle_time()
  local v = tonumber(ui("bg_cycle", 60)) or 60
  return math.max(5, v)
end

-- The weather to show: the Test Bench's pick, else the setting; nil = random ("random" and "cycle").
function M.wanted()
  if M.forced then return M.forced end
  local k = ui("bg_weather", "random")
  if k == "none" then return "none" end
  if type(k) == "string" and M.NAMES[k] then return k end
  return nil
end

-- The sky layers to show: { stars = true, ... } from their switches, or the Test Bench's one pick.
function M.wanted_skies()
  local out = {}
  if M.forced_sky then
    if M.forced_sky ~= "none" and M.SKY_NAMES[M.forced_sky] then out[M.forced_sky] = true end
    return out
  end
  for _, k in ipairs(M.SKIES) do
    if ui("bg_" .. k, false) == true then out[k] = true end
  end
  return out
end

-- The cloud level for a weather kind (the setting, or the weather's own with "default").
function M.cloud_level(kind)
  local v = ui("bg_clouds", "default")
  if v ~= "default" and M.CLOUD_COUNT[v] then return v end
  return M.WEATHER_CLOUDS[kind or "none"] or "light"
end

M.SEASONS = { "spring", "summer", "autumn", "winter" }
M.SEASON_MONTH = { spring = 4, summer = 7, autumn = 10, winter = 1 }

-- What the weather was built for: the kind (nil = random) and the season setting. A change rebuilds it.
function M.want_key()
  return tostring(M.wanted()) .. "|" .. tostring(ui("bg_season", "auto"))
end

-- Whether two want_key()s differ only in the season part.
function M.only_season_changed(old, new)
  if type(old) ~= "string" or type(new) ~= "string" then return false end
  return old:match("^[^|]*") == new:match("^[^|]*") and old ~= new
end

-- The month the scene is built for: the PC's month ("auto"), a random season's, or a chosen season's.
function M.wanted_month()
  local s = ui("bg_season", "auto")
  if s == "random" then return M.SEASON_MONTH[M.SEASONS[math.floor(M.rng() * 4) + 1]] end
  if M.SEASON_MONTH[s] then return M.SEASON_MONTH[s] end
  return tonumber(os.date("%m")) or 1
end

-- A random kind that is not the one shown last time (a fresh pick should look like one).
function M.pick_new(month, avoid)
  avoid = avoid or M.last_kind
  local k = M.pick(month)
  for _ = 1, 8 do
    if k ~= avoid then break end
    k = M.pick(month)
  end
  return k
end

---------------------------------------------------------------- weather particles

-- Particle counts and look per kind, for a 1080 px tall screen (scaled with the screen).
local SPEC = {
  sunny = { count = 46 },
  rain_light = { count = 170, speed = { 850, 1150 }, len = { 16, 28 }, wind = 120, alpha = 0.5 },
  rain_heavy = { count = 360, speed = { 1200, 1600 }, len = { 22, 38 }, wind = 260, alpha = 0.45, tint = 0.18 },
  snow = { count = 260 },
  thunder = { count = 380, speed = { 1300, 1700 }, len = { 24, 40 }, wind = 340, alpha = 0.45, tint = 0.32 },
  fog = { count = 16 },
  none = { count = 0 },
}
M.SPEC = SPEC

local function new_part(s, kind, fresh)
  local w, h, k = s.w, s.h, s.k
  local p = {}
  if kind == "sunny" then
    p.x, p.y = rand(0, w), fresh and rand(0, h) or h + 10 * k
    p.vx, p.vy = rand(-8, 12) * k, rand(-22, -8) * k
    p.r = rand(1.2, 3.2) * k
    p.phase = rand(0, 6.28)
  elseif kind == "rain_light" or kind == "rain_heavy" or kind == "thunder" then
    local sp = SPEC[kind]
    p.x, p.y = rand(-0.2 * w, w), fresh and rand(-h, h) or rand(-0.3 * h, -10 * k)
    p.vy = rand(sp.speed[1], sp.speed[2]) * k
    p.vx = sp.wind * k * rand(0.85, 1.15)
    p.len = rand(sp.len[1], sp.len[2]) * k
    p.a = sp.alpha * rand(0.6, 1)
  elseif kind == "snow" then
    p.x, p.y = rand(-0.05 * w, w * 1.05), fresh and rand(-h, h) or rand(-0.1 * h, -6 * k)
    p.r = rand(1.6, 4.8) * k
    p.vy = (22 + p.r / k * 18) * k * rand(0.8, 1.2) -- nearer (bigger) flakes fall faster
    p.vx = rand(-10, 18) * k
    p.phase, p.sway = rand(0, 6.28), rand(8, 26) * k
    p.a = 0.5 + 0.12 * p.r / k
  elseif kind == "fog" then
    p.rx, p.ry = rand(0.22, 0.42) * w, rand(0.1, 0.2) * h
    p.x = fresh and rand(-p.rx, w + p.rx) or -p.rx
    p.y = rand(0.05 * h, 0.95 * h)
    p.vx = rand(10, 28) * k
    p.a = rand(0.05, 0.1)
  end
  return p
end

local function scale_count(s, n)
  return math.floor(n * math.max(0.5, math.min(2, s.w * s.h / (1920 * 1080))))
end

-- Fills a weather table (the scene itself for the current weather, a copy for one fading out).
local function init_weather(s, ws, kind)
  ws.kind = kind
  ws.parts = {}
  ws.flash, ws.bolt, ws.flicker, ws.next_bolt = 0, nil, nil, 2
  for i = 1, scale_count(s, (SPEC[kind] or SPEC.none).count) do ws.parts[i] = new_part(s, kind, true) end
  return ws
end

local function bolt_path(s)
  -- a jagged line from the top to 45-75% of the height, with one or two short branches
  local x, y = rand(0.08, 0.92) * s.w, 0
  local stop = rand(0.45, 0.75) * s.h
  local main, branches = { x, y }, {}
  while y < stop do
    x = x + rand(-38, 38) * s.k
    y = y + rand(26, 52) * s.k
    main[#main + 1], main[#main + 2] = x, y
    if M.rng() < 0.18 and #branches < 2 then
      local bx, by, br = x, y, { x, y }
      for _ = 1, 4 do
        bx, by = bx + rand(-50, 50) * s.k, by + rand(20, 40) * s.k
        br[#br + 1], br[#br + 2] = bx, by
      end
      branches[#branches + 1] = br
    end
  end
  return { main = main, branches = branches, life = 0.28 }
end

local function step_weather(s, ws, dt)
  local w, h, k, kind = s.w, s.h, s.k, ws.kind
  for i, p in ipairs(ws.parts) do
    if kind == "sunny" then
      p.x = p.x + (p.vx + math.sin(s.t * 0.7 + p.phase) * 6 * k) * dt
      p.y = p.y + p.vy * dt
      if p.y < -10 * k or p.x < -10 * k or p.x > w + 10 * k then ws.parts[i] = new_part(s, kind) end
    elseif kind == "rain_light" or kind == "rain_heavy" or kind == "thunder" then
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
      if p.y - p.len > h then ws.parts[i] = new_part(s, kind) end
    elseif kind == "snow" then
      p.x = p.x + (p.vx + math.sin(s.t * 1.1 + p.phase) * p.sway) * dt
      p.y = p.y + p.vy * dt
      if p.y > h + 8 * k then ws.parts[i] = new_part(s, kind) end
    elseif kind == "fog" then
      p.x = p.x + p.vx * dt
      if p.x - p.rx > w then ws.parts[i] = new_part(s, kind) end
    end
  end
  if kind == "thunder" then
    ws.flash = math.max(0, ws.flash - dt * 2.4)
    if ws.bolt then
      ws.bolt.life = ws.bolt.life - dt
      if ws.bolt.life <= 0 then ws.bolt = nil end
    end
    ws.next_bolt = ws.next_bolt - dt
    if ws.next_bolt <= 0 then
      ws.bolt = bolt_path(s)
      ws.flash = 0.75
      ws.flicker = s.t + rand(0.08, 0.14) -- a second, weaker flash right after
      ws.next_bolt = rand(3.5, 9)
    end
    if ws.flicker and s.t >= ws.flicker then
      ws.flash, ws.flicker = math.max(ws.flash, 0.45), nil
    end
  end
end

-- Shooting stars: their own layer (was the "meteor shower" weather), now and then, sometimes in pairs.
local function new_shooting() return { list = {}, next = rand(1, 3) } end

local function step_shooting(s, dt)
  local sh = s.shooting
  if not sh then return end
  local w, h, k = s.w, s.h, s.k
  sh.next = sh.next - dt
  if sh.next <= 0 then
    local ang = rand(0.42, 0.62) -- heading down and to the left
    local sp = rand(900, 1500) * k
    sh.list[#sh.list + 1] = { x = rand(0.25, 1.15) * w, y = rand(-0.15, 0.35) * h, vx = -math.cos(ang) * sp,
      vy = math.sin(ang) * sp, len = rand(180, 340) * k, life = rand(0.7, 1.3), age = 0 }
    sh.next = M.rng() < 0.2 and rand(0.1, 0.35) or rand(1.5, 4.5)
  end
  for i = #sh.list, 1, -1 do
    local m = sh.list[i]
    m.x, m.y, m.age = m.x + m.vx * dt, m.y + m.vy * dt, m.age + dt
    if m.age >= m.life or m.y > h + m.len or m.x < -m.len then table.remove(sh.list, i) end
  end
end

---------------------------------------------------------------- scenery

-- Where the grass starts (screen y), or the bottom of the screen without grass.
function M.ground_y(s)
  if s.ground then return s.h * (1 - 0.075) end
  return s.h
end

local function new_ground(s)
  local blades = {}
  local n = math.floor(s.w / (5 * s.k))
  for i = 1, n do
    blades[i] = { x = (i - 1 + rand(0, 1)) * 5 * s.k, h = rand(9, 24) * s.k, phase = rand(0, 6.28),
      shade = rand(0.75, 1.15) }
  end
  return { blades = blades }
end

-- A leaf, coming in from above the screen and drifting right as it falls.
local function new_leaf(s, fresh)
  local w, h, k = s.w, s.h, s.k
  local cols = M.LEAF_COLOURS[s.season]
  local p = {}
  p.x, p.y = rand(-0.1 * w, w), fresh and rand(-h, h) or rand(-0.15 * h, -20 * k)
  p.vy = rand(45, 95) * k
  p.vx = rand(15, 55) * k
  p.size = rand(13, 22) * k * (s.season == "spring" and 0.7 or 1)
  p.rot, p.vrot = rand(0, 6.28), rand(-2.2, 2.2)
  p.phase, p.sway = rand(0, 6.28), rand(18, 42) * k
  p.c = cols[math.floor(M.rng() * #cols) + 1]
  p.a = 1
  return p
end

M.LEAF_COUNT = 56
M.LEAF_REST = 2.2 -- seconds a leaf lies on the grass before it fades away

local function step_leaves(s, dt)
  local gy = s.ground and M.ground_y(s) or nil
  for i, p in ipairs(s.leaves) do
    if p.rest then
      p.rest = p.rest - dt
      p.a = math.max(0, math.min(1, p.rest / 0.8))
      if p.rest <= 0 then s.leaves[i] = new_leaf(s) end
    else
      p.x = p.x + (p.vx + math.cos(s.t * 1.3 + p.phase) * p.sway) * dt
      p.y = p.y + p.vy * dt
      p.rot = p.rot + p.vrot * dt
      if gy and p.y >= gy + p.size * 0.2 then
        -- landed: lies still on the grass a moment, then fades
        p.y = gy + rand(0.15, 0.85) * (s.h - gy)
        p.rest = M.LEAF_REST * rand(0.7, 1.3)
      elseif p.y > s.h + 20 * s.k or p.x > s.w + 30 * s.k then
        s.leaves[i] = new_leaf(s)
      end
    end
  end
end

local function new_clouds()
  return { list = {}, spawn = 0, tint = 0 }
end

local function new_cloud(s, level, x)
  local k = s.k
  local size = rand(0.7, 1.3) * (level == "heavy" and 1.35 or 1)
  local c = { x = x, y = rand(0.02, 0.3) * s.h, vx = rand(10, 24) * k, puffs = {}, size = size, a = 1 }
  local n = math.floor(rand(5, 9))
  local span = 0
  for i = 1, n do
    local r = rand(38, 70) * k * size
    c.puffs[i] = { dx = (i - 1) * 42 * k * size + rand(-10, 10) * k, dy = rand(-0.35, 0.25) * r, r = r }
    span = math.max(span, c.puffs[i].dx + r)
  end
  c.span = span
  if x == nil then c.x = -span - rand(0, 200) * k end
  return c
end

M.CLOUD_FADE = 2.5 -- seconds a cloud that is no longer wanted takes to fade away

-- Clouds drift right; the count eases towards the level's: new ones come in from the left, and
-- extra ones fade out where they are (so "No clouds" ends with none), a few seconds apart.
local function step_clouds(s, dt, level, kind)
  local cl = s.clouds
  local want = math.floor(M.CLOUD_COUNT[level] * math.max(0.6, math.min(1.6, s.w / 1920)))
  local staying = 0
  for i = #cl.list, 1, -1 do
    local c = cl.list[i]
    c.x = c.x + c.vx * dt
    if c.leaving then
      c.a = c.a - dt / M.CLOUD_FADE
      if c.a <= 0 then table.remove(cl.list, i) end
    elseif c.x > s.w + 20 * s.k then
      table.remove(cl.list, i)
    else
      staying = staying + 1
    end
  end
  -- too many: the next one starts fading (all of them at once when none are wanted)
  cl.thin = (cl.thin or 0) - dt
  if staying > want and (cl.thin <= 0 or want == 0) then
    for _, c in ipairs(cl.list) do
      if not c.leaving then
        c.leaving = true
        staying = staying - 1
        if want > 0 or staying <= want then break end
      end
    end
    cl.thin = 0.8
  end
  cl.spawn = cl.spawn - dt
  if staying < want and cl.spawn <= 0 then
    cl.list[#cl.list + 1] = new_cloud(s, level)
    cl.spawn = rand(2, 6) / math.max(1, want / 6)
  end
  local tint = (level == "heavy" and (kind == "thunder" and 0.16 or 0.1)) or 0
  cl.tint = cl.tint + (tint - cl.tint) * math.min(1, dt * 0.8)
  cl.level, cl.dark = level, kind == "thunder" or kind == "rain_heavy"
end

local function fill_clouds(s, level)
  local want = math.floor(M.CLOUD_COUNT[level] * math.max(0.6, math.min(1.6, s.w / 1920)))
  for i = 1, want do s.clouds.list[i] = new_cloud(s, level, rand(-0.1, 0.95) * s.w) end
  s.clouds.tint = level == "heavy" and 0.1 or 0
end

-- One sky layer.
local function new_sky(s, kind)
  local sky = { kind = kind, parts = {} }
  if kind == "stars" then
    for i = 1, scale_count(s, 150) do
      sky.parts[i] = { x = rand(0, s.w), y = rand(0, s.h * 0.8), r = rand(0.8, 2.2) * s.k, phase = rand(0, 6.28),
        tw = rand(0.6, 2.4) }
    end
  elseif kind == "fireflies" then
    for i = 1, scale_count(s, 42) do
      sky.parts[i] = { x = rand(0, s.w), y = rand(0.45, 0.95) * s.h, vx = rand(-18, 18) * s.k, vy = rand(-10, 10) * s.k,
        phase = rand(0, 6.28), tw = rand(0.6, 1.6), r = rand(1.6, 3) * s.k }
    end
  end
  return sky
end

local function step_sky(s, dt)
  local sky = s.skies and s.skies.fireflies
  if not sky then return end
  for _, p in ipairs(sky.parts) do
    p.vx = p.vx + rand(-30, 30) * s.k * dt
    p.vy = p.vy + rand(-30, 30) * s.k * dt
    local sp = math.sqrt(p.vx * p.vx + p.vy * p.vy)
    local max = 26 * s.k
    if sp > max then p.vx, p.vy = p.vx / sp * max, p.vy / sp * max end
    p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    if p.x < 0 then p.x, p.vx = 0, math.abs(p.vx) end
    if p.x > s.w then p.x, p.vx = s.w, -math.abs(p.vx) end
    if p.y < 0.4 * s.h then p.vy = math.abs(p.vy) end
    if p.y > s.h then p.vy = -math.abs(p.vy) end
  end
end

---------------------------------------------------------------- the scene

-- `o.skies` as a set ({ stars = true }), from a list ({ "stars" }) or one kind (o.sky).
local function sky_set(o)
  local out = {}
  if type(o.skies) == "table" then
    for k, v in pairs(o.skies) do
      if type(k) == "number" then out[v] = true elseif v then out[k] = true end
    end
  elseif o.sky and o.sky ~= "none" then
    out[o.sky] = true
  end
  return out
end

-- A new scene for a sw by sh screen. `kind` is the weather (nil picks one, "none" is off);
-- `month` sets the season; o: { skies = set, sky = one kind, shooting, leaves, ground,
-- clouds = level } (defaults: off, except clouds follow the weather), so tests and the bench can
-- build exactly what they need.
function M.new(sw, sh, kind, month, o)
  o = o or {}
  month = month or tonumber(os.date("%m")) or 1
  local s = { w = sw, h = sh, k = sh / 1080, t = 0, month = month, season = M.season(month) }
  init_weather(s, s, kind or M.pick(month))
  s.clouds = new_clouds()
  if o.ground then s.ground = new_ground(s) end
  if o.leaves then
    s.leaves = {}
    for i = 1, M.LEAF_COUNT do s.leaves[i] = new_leaf(s, true) end
  end
  s.skies = {}
  for k in pairs(sky_set(o)) do
    if M.SKY_NAMES[k] and k ~= "none" then s.skies[k] = new_sky(s, k) end
  end
  if o.shooting then s.shooting = new_shooting() end
  local level = o.clouds or M.WEATHER_CLOUDS[s.kind] or "light"
  fill_clouds(s, level)
  s.next_cycle = o.cycle
  return s
end

-- Keeps the scene when the screen size changes (recreates it for the new size, with the same parts).
function M.resize(s, sw, sh)
  if s.w == sw and s.h == sh then return s end
  local skies = {}
  for k in pairs(s.skies or {}) do skies[k] = true end
  local fresh = M.new(sw, sh, s.kind, s.month, { skies = skies,
    shooting = s.shooting ~= nil, leaves = s.leaves ~= nil, ground = s.ground ~= nil,
    clouds = s.clouds and s.clouds.level, cycle = s.next_cycle })
  fresh.t = s.t
  return fresh
end

-- Switches the weather. With a crossfade the old one keeps falling and fades out over M.CROSSFADE.
function M.change_weather(s, kind, crossfade)
  if crossfade and s.kind ~= "none" then
    s.prev = { kind = s.kind, parts = s.parts, flash = s.flash, bolt = s.bolt, flicker = s.flicker, next_bolt = 1e9 }
    s.mix = 0
  else
    s.prev, s.mix = nil, nil
  end
  init_weather(s, s, kind)
  if crossfade then s.mix = 0 end
end

-- Brings the optional layers in line with the settings (a switch applies at once, no rebuild).
-- o: { ground, leaves, skies (set), shooting }; a field left nil reads its setting.
function M.sync_layers(s, o)
  o = o or {}
  local want_ground = o.ground
  if want_ground == nil then want_ground = M.ground_on() end
  local want_leaves = o.leaves
  if want_leaves == nil then want_leaves = M.leaves_on() end
  if want_ground and not s.ground then s.ground = new_ground(s) end
  if not want_ground and s.ground then s.ground = nil end
  if want_leaves and not s.leaves then
    s.leaves = {}
    for i = 1, M.LEAF_COUNT do s.leaves[i] = new_leaf(s, true) end
  elseif not want_leaves then
    s.leaves = nil
  end
  local want_skies = (o.skies or o.sky) and sky_set(o) or M.wanted_skies()
  s.skies = s.skies or {}
  for _, k in ipairs(M.SKIES) do
    local have = s.skies[k]
    if want_skies[k] and not have then
      s.skies[k] = new_sky(s, k)
    elseif not want_skies[k] and have then
      s.skies[k] = nil
    end
  end
  local want_shooting = o.shooting
  if want_shooting == nil then want_shooting = M.shooting_on() end
  if want_shooting and not s.shooting then s.shooting = new_shooting() end
  if not want_shooting then s.shooting = nil end
end

-- Advances the scene by dt seconds. `level`: the cloud level (default: the weather's own).
function M.step(s, dt, level)
  s.t = s.t + dt
  step_weather(s, s, dt)
  if s.prev then
    step_weather(s, s.prev, dt)
    s.mix = math.min(1, (s.mix or 0) + dt / M.CROSSFADE)
    if s.mix >= 1 then s.prev, s.mix = nil, nil end
  end
  if s.leaves then step_leaves(s, dt) end
  step_clouds(s, dt, level or M.WEATHER_CLOUDS[s.kind] or "light", s.kind)
  step_sky(s, dt)
  step_shooting(s, dt)
  return s
end

-- The four screen bands around `rect` ({x, y, w, h} in pixels), which together cover everything outside
-- it once and never touch it. Each is {x, y, w, h} with whole pixels; empty bands are left out.
function M.bands(sw, sh, rect)
  local x0 = math.max(0, math.min(sw, math.floor(rect.x)))
  local y0 = math.max(0, math.min(sh, math.floor(rect.y)))
  local x1 = math.max(x0, math.min(sw, math.ceil(rect.x + rect.w)))
  local y1 = math.max(y0, math.min(sh, math.ceil(rect.y + rect.h)))
  local out = {}
  local function add(x, y, w, h) if w > 0 and h > 0 then out[#out + 1] = { x = x, y = y, w = w, h = h } end end
  add(0, 0, sw, y0)               -- above
  add(0, y1, sw, sh - y1)         -- below
  add(0, y0, x0, y1 - y0)         -- left
  add(x1, y0, sw - x1, y1 - y0)   -- right
  return out
end

---------------------------------------------------------------- drawing

-- A vertical gradient strip from colour a (top) to b (bottom), in `n` bands.
local function gradient(g, x, y, w, h, a, b, n, col)
  n = n or 16
  for i = 0, n - 1 do
    local f = (i + 0.5) / n
    -- whole-pixel bands that meet exactly (an overlap shows as a brighter line with translucent colours)
    local y0, y1 = math.floor(y + h * i / n), math.floor(y + h * (i + 1) / n)
    col(a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f, a[4] + (b[4] - a[4]) * f)
    g.rectangle("fill", x, y0, w, y1 - y0)
  end
end

local function draw_one_sky(s, sky, g, col, dark)
  local w, h, k = s.w, s.h, s.k
  if sky.kind == "stars" then
    if dark then
      col(0.02, 0.03, 0.1, 0.36)
      g.rectangle("fill", 0, 0, w, h)
    end
    for _, p in ipairs(sky.parts) do
      col(0.92, 0.94, 1, 0.45 + 0.4 * math.sin(s.t * p.tw + p.phase))
      g.circle("fill", p.x, p.y, p.r)
    end
  elseif sky.kind == "sunset" then
    -- only the haze: purple at the top to warm orange at the bottom
    gradient(g, 0, 0, w, h, { 0.3, 0.16, 0.45, 0.28 }, { 1, 0.5, 0.28, 0.3 }, 24, col)
  elseif sky.kind == "fireflies" then
    if dark then
      col(0.02, 0.05, 0.06, 0.3)
      g.rectangle("fill", 0, 0, w, h)
    end
    if g.setBlendMode then g.setBlendMode("add") end
    for _, p in ipairs(sky.parts) do
      local glow = math.max(0, math.sin(s.t * p.tw + p.phase)) ^ 0.7
      col(0.8, 1, 0.3, 0.08 * glow)
      g.circle("fill", p.x, p.y, p.r * 7)
      col(0.85, 1, 0.35, 0.2 * glow)
      g.circle("fill", p.x, p.y, p.r * 3)
      col(1, 1, 0.7, 0.95 * glow)
      g.circle("fill", p.x, p.y, p.r * 1.2)
    end
    if g.setBlendMode then g.setBlendMode("alpha") end
  end
end

-- Every sky layer that is on, in order. Only the first night sky darkens the screen, so two of
-- them together are not twice as dark.
local function draw_sky(s, g, col)
  local dark = true
  for _, k in ipairs(M.SKIES) do
    local sky = s.skies and s.skies[k]
    if sky then
      draw_one_sky(s, sky, g, col, dark)
      if k ~= "sunset" then dark = false end
    end
  end
end

local function draw_shooting(s, g, col)
  local sh = s.shooting
  if not sh then return end
  local k = s.k
  for _, m in ipairs(sh.list) do
    local life = 1 - m.age / m.life
    local sp = math.sqrt(m.vx * m.vx + m.vy * m.vy)
    local ux, uy = m.vx / sp, m.vy / sp
    local seg = 8
    for i = seg, 1, -1 do -- tail: fading segments behind the head
      local a0, a1 = (i - 1) / seg, i / seg
      g.setLineWidth(math.max(1, (3.4 - 2.6 * a0) * k))
      col(1, 0.92, 0.75, (1 - a0) * 0.8 * life)
      g.line(m.x - ux * m.len * a0, m.y - uy * m.len * a0, m.x - ux * m.len * a1, m.y - uy * m.len * a1)
    end
    col(1, 1, 0.95, life)
    g.circle("fill", m.x, m.y, 3 * k)
  end
end

local function draw_clouds(s, g, col)
  local cl = s.clouds
  if not cl then return end
  if cl.tint > 0.002 then
    col(0.12, 0.13, 0.17, cl.tint)
    g.rectangle("fill", 0, 0, s.w, s.h)
  end
  local heavy, dark = cl.level == "heavy", cl.dark
  for _, c in ipairs(cl.list) do
    local r, gg, b, a = 0.95, 0.96, 1, 0.5
    if heavy then r, gg, b, a = 0.62, 0.65, 0.72, 0.62 end
    if dark then r, gg, b, a = 0.36, 0.38, 0.46, 0.7 end
    a = a * (c.a or 1)
    -- a darker underside, then the puffs, then a light top
    col(r * 0.75, gg * 0.75, b * 0.8, a * 0.7)
    for _, p in ipairs(c.puffs) do g.circle("fill", c.x + p.dx, c.y + p.dy + p.r * 0.18, p.r) end
    col(r, gg, b, a)
    for _, p in ipairs(c.puffs) do g.circle("fill", c.x + p.dx, c.y + p.dy, p.r * 0.92) end
  end
end

local function draw_weather(s, ws, g, col)
  local w, h, k, kind = s.w, s.h, s.k, ws.kind
  if kind == "sunny" then
    -- warm wash, then soft rays from a sun just off the top-left corner, then floating dust
    col(1, 0.82, 0.45, 0.07)
    g.rectangle("fill", 0, 0, w, h)
    local sx, sy = 0.02 * w, -0.02 * h
    local reach = math.sqrt(w * w + h * h) * 1.1
    for i = 0, 5 do
      local a0 = 0.18 + i * 0.22 + math.sin(s.t * 0.25 + i * 1.7) * 0.03
      local spread = 0.05 + 0.02 * math.sin(s.t * 0.4 + i)
      local alpha = 0.05 + 0.025 * math.sin(s.t * 0.6 + i * 2.1)
      col(1, 0.93, 0.7, alpha)
      g.polygon("fill", sx, sy, sx + math.cos(a0 - spread) * reach, sy + math.sin(a0 - spread) * reach,
        sx + math.cos(a0 + spread) * reach, sy + math.sin(a0 + spread) * reach)
    end
    for ring = 4, 1, -1 do
      col(1, 0.9, 0.55, 0.07)
      g.circle("fill", sx, sy, (0.2 + ring * 0.035) * h)
    end
    col(1, 0.86, 0.42, 1)
    g.circle("fill", sx, sy, 0.2 * h)
    col(1, 0.95, 0.68, 1)
    g.circle("fill", sx, sy, 0.15 * h)
    for _, p in ipairs(ws.parts) do
      col(1, 0.94, 0.72, 0.35 + 0.25 * math.sin(s.t * 2 + p.phase))
      g.circle("fill", p.x, p.y, p.r)
    end
  elseif kind == "rain_light" or kind == "rain_heavy" or kind == "thunder" then
    local sp = SPEC[kind]
    if sp.tint then
      col(0.05, 0.07, 0.12, sp.tint)
      g.rectangle("fill", 0, 0, w, h)
    end
    g.setLineWidth(math.max(1, (kind == "rain_light" and 1.3 or 1.7) * k))
    for _, p in ipairs(ws.parts) do
      local dx, dy = p.vx / p.vy * p.len, p.len
      col(0.72, 0.8, 0.92, p.a)
      g.line(p.x - dx, p.y - dy, p.x, p.y)
    end
    if kind == "thunder" then
      if ws.bolt then
        local a = math.min(1, ws.bolt.life / 0.12)
        g.setLineWidth(9 * k)
        col(0.65, 0.75, 1, 0.25 * a)
        g.line(ws.bolt.main)
        for _, b in ipairs(ws.bolt.branches) do g.line(b) end
        g.setLineWidth(2.4 * k)
        col(0.95, 0.97, 1, a)
        g.line(ws.bolt.main)
        g.setLineWidth(1.4 * k)
        for _, b in ipairs(ws.bolt.branches) do g.line(b) end
      end
      if ws.flash > 0 then
        col(0.88, 0.92, 1, ws.flash * 0.55)
        g.rectangle("fill", 0, 0, w, h)
      end
    end
  elseif kind == "snow" then
    col(0.75, 0.82, 0.92, 0.06)
    g.rectangle("fill", 0, 0, w, h)
    for _, p in ipairs(ws.parts) do
      col(1, 1, 1, p.a)
      g.circle("fill", p.x, p.y, p.r)
    end
  elseif kind == "fog" then
    col(0.72, 0.76, 0.8, 0.12)
    g.rectangle("fill", 0, 0, w, h)
    for _, p in ipairs(ws.parts) do
      local breathe = 1 + 0.06 * math.sin(s.t * 0.3 + p.x * 0.01)
      for ring = 6, 1, -1 do -- soft edge: many faint rings, each smaller one adds a little more
        col(0.86, 0.88, 0.9, p.a * 0.45)
        g.ellipse("fill", p.x, p.y, p.rx * (0.4 + ring * 0.12) * breathe, p.ry * (0.4 + ring * 0.12) * breathe)
      end
    end
  end
end

local function draw_ground(s, g, col)
  if not s.ground then return end
  local k, w, h = s.k, s.w, s.h
  local gy = M.ground_y(s)
  local gc = M.GRASS_COLOURS[s.season] or M.GRASS_COLOURS.summer
  col(gc[1] * 0.7, gc[2] * 0.7, gc[3] * 0.7, 0.96)
  g.rectangle("fill", 0, gy, w, h - gy)
  local wind = (s.kind == "rain_heavy" or s.kind == "thunder") and 7 or 3
  for _, b in ipairs(s.ground.blades) do
    local tip = math.sin(s.t * 1.4 + b.phase + b.x * 0.004) * wind * k
    col(gc[1] * b.shade, gc[2] * b.shade, gc[3] * b.shade, 0.96)
    g.polygon("fill", b.x - 2.4 * k, gy + 4 * k, b.x + 2.4 * k, gy + 4 * k, b.x + tip, gy - b.h)
  end
  if s.kind == "snow" or (s.prev and s.prev.kind == "snow") then
    col(0.95, 0.97, 1, 0.8)
    g.rectangle("fill", 0, gy + 2 * k, w, 5 * k)
  end
end

local function draw_leaves(s, g, col)
  if not s.leaves then return end
  local k = s.k
  for _, p in ipairs(s.leaves) do
    local c = p.c
    g.push()
    g.translate(p.x, p.y)
    g.rotate(p.rot)
    col(c[1], c[2], c[3], 0.92 * p.a)
    if s.season == "spring" then
      g.ellipse("fill", 0, 0, p.size * 0.55, p.size * 0.38)
    else
      local L, W = p.size, p.size * 0.45
      g.polygon("fill", -L, 0, -L * 0.2, -W, L * 0.6, -W * 0.55, L, 0, L * 0.6, W * 0.55, -L * 0.2, W)
      col(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 0.9 * p.a)
      g.setLineWidth(math.max(1, k))
      g.line(-L * 1.25, 0, L * 0.85, 0) -- stem and midrib
    end
    g.pop()
  end
end

-- Draws every layer of the scene at `fade` (0..1) in the current transform.
function M.draw_scene(s, g, fade)
  local function col(r, gg, b, a) g.setColor(r, gg, b, a * fade) end
  draw_sky(s, g, col)
  draw_shooting(s, g, col)
  draw_clouds(s, g, col)
  if s.prev then
    local m = s.mix or 0
    draw_weather(s, s.prev, g, function(r, gg, b, a) g.setColor(r, gg, b, a * fade * (1 - m)) end)
    draw_weather(s, s, g, function(r, gg, b, a) g.setColor(r, gg, b, a * fade * m) end)
  else
    draw_weather(s, s, g, col)
  end
  draw_ground(s, g, col)
  draw_leaves(s, g, col)
end

---------------------------------------------------------------- where it is drawn

local function note(level, msg, ...)
  local line = msg:format(...)
  if M.noted == line then return end
  M.noted = line
  print("[Better Background] " .. level .. ": background: " .. line)
end

-- The open window that asked for the background: always nil here.
-- (Chromite draws the scene around its own windows; there are none here.)
local function current_box()
  return nil
end
M.current_box = current_box

-- The element that is the visible window. The overlay's root is a dimmed backdrop several times the
-- size of the room (the game's create_UIBox_generic_options), so walk down first children until one
-- fits in the room: that is the window's frame.
function M.frame(box)
  local node = box.UIRoot or box
  local room_w = (G.ROOM and G.ROOM.T and G.ROOM.T.w) or 20
  local room_h = (G.ROOM and G.ROOM.T and G.ROOM.T.h) or 11.5
  for _ = 1, 8 do
    local VT = node.VT or node.T
    if not VT then break end
    if VT.w <= room_w and VT.h <= room_h then return node end
    local child = node.children and node.children[1]
    if not child then break end
    node = child
  end
  return box
end

-- The window in screen pixels, where it is drawn this frame (VT, so it follows the slide-in and a page
-- that changes the window's size). Room space to screen: add G.ROOM.T, scale by TILESCALE * TILE_SIZE.
function M.window_rect(box)
  local ppu = (G.TILESCALE or 1) * (G.TILE_SIZE or 20)
  local ox, oy = (G.ROOM and G.ROOM.T.x) or 0, (G.ROOM and G.ROOM.T.y) or 0
  local node = M.frame(box)
  local VT = node.VT or node.T
  return { x = (VT.x + ox) * ppu, y = (VT.y + oy) * ppu, w = VT.w * ppu, h = VT.h * ppu }
end

-- Forces a weather kind (Test Bench); nil goes back to the setting. Clearing it keeps whatever is
-- showing unless `repick` asks for a new random kind: leaving the bench's case must not change the
-- weather around the next bench window (WX18). Only lasts while the background is shown.
function M.set_kind(kind, repick)
  M.forced = kind
  if M.state and kind == nil and not repick then
    M.built_for = M.want_key()
    return
  end
  if M.state then
    local want = kind or M.wanted()
    M.change_weather(M.state, want or M.pick_new(M.state.month), false)
    M.built_for = M.want_key()
    M.last_kind = M.state.kind
    M.noted = nil
    note("info", "%s (%s), screen %dx%d", M.NAMES[M.state.kind] or M.state.kind, M.state.season, M.state.w, M.state.h)
  end
end

-- The sky layers a scene shows, for the Test Bench ("Starry night + Sunset", or "none").
function M.sky_label(s)
  local out = {}
  for _, k in ipairs(M.SKIES) do
    if s.skies and s.skies[k] then out[#out + 1] = M.SKY_NAMES[k] end
  end
  if s.shooting then out[#out + 1] = "Shooting stars" end
  return #out > 0 and table.concat(out, " + ") or "none"
end

-- Forces one sky layer (Test Bench; "shooting" for shooting stars alone, "none" for no sky); nil
-- goes back to the settings.
function M.set_sky(kind)
  M.forced_sky = kind
end

-- Where the hub window is when the measured rectangle cannot be right (it covers nearly the whole
-- screen, or lies outside it): the window's usual share of the screen, so the scene still shows.
function M.fallback_rect(sw, sh)
  return { x = sw * 0.25, y = sh * 0.126, w = sw * 0.5, h = sh * 0.748 }
end

function M.rect_ok(rect, sw, sh)
  return rect.w > 0 and rect.h > 0 and rect.x < sw and rect.y < sh and rect.x + rect.w > 0 and rect.y + rect.h > 0
    and rect.w < sw * 0.92 and rect.h < sh * 0.97
end

M.FADE_IN, M.FADE_OUT = 0.6, 0.45

-- Draws the scene into the game's canvas in screen pixels (the canvas is the window times CANV_SCALE).
local function draw_into_canvas()
  local s = M.state
  local g = love.graphics
  g.push("all")
  g.origin()
  g.scale((type(G) == "table" and G.CANV_SCALE) or 1)
  g.setShader()
  g.setBlendMode("alpha")
  g.setScissor()
  if g.setColorMask then g.setColorMask(true, true, true, true) end
  M.draw_scene(s, g, M.fade)
  g.pop()
end

-- Under the window: the overlay's root element is the game's dimmed backdrop and its children are the
-- window (Game:draw -> UIBox:draw -> UIRoot:draw_self, then UIRoot:draw_children). Drawing the scene
-- just before the children puts it over the backdrop and under the window, inside the game's canvas,
-- so it covers the whole screen (rounded corners included) and gets the game's CRT look. The love.draw
-- pass (around the window, clipped) stays as the fallback for a frame this did not run.
function M.draw_under()
  local s = M.state
  if not (s and M.fade and M.fade > 0 and not M.failed) then return end
  draw_into_canvas()
  M.under_frame = G.FRAMES and G.FRAMES.DRAW
end

function M.hook_under(box)
  local root = box.UIRoot
  if not root or root.better_background or type(root.draw_children) ~= "function" then return end
  local base = root.draw_children
  root.better_background = true
  root.draw_children = function(self, ...)
    if not M.under_failed then
      local ok, err = pcall(M.draw_under)
      if not ok then
        M.under_failed = true -- the love.draw pass takes over
        note("warn", "drawing under the window failed, drawing around it instead: %s", tostring(err))
      end
    end
    return base(self, ...)
  end
end

-- Everywhere: right after the game's background sprite, before anything else of the game is drawn.
function M.draw_back()
  local s = M.state
  if not (s and M.fade and M.fade > 0 and M.everywhere() and not M.failed) then return end
  if current_box() then return end
  draw_into_canvas()
  M.back_frame = G.FRAMES and G.FRAMES.DRAW
end

-- The game makes a new background sprite for the main menu and each run, so this is checked every frame.
function M.hook_back()
  local back = type(G) == "table" and G.SPLASH_BACK
  if type(back) ~= "table" or back.better_background then return end
  local base = back.draw
  if type(base) ~= "function" then return end
  back.better_background = true
  back.draw = function(self, ...)
    local ret = base(self, ...)
    if not M.back_failed then
      local ok, err = pcall(M.draw_back)
      if not ok then
        M.back_failed = true
        note("warn", "drawing behind the game failed, switched off until restart: %s", tostring(err))
      end
    end
    return ret
  end
end

-- Whether the main menu's buttons have popped in (always true off the main menu). The game parks
-- G.MAIN_MENU_UI below the screen and eases it up; the scene fades in once it has arrived. A new
-- main menu (back from a run) starts the wait again.
function M.menu_settled()
  if type(G) ~= "table" or not G.STAGES or G.STAGE ~= G.STAGES.MAIN_MENU then
    M.menu_ui, M.menu_ready = nil, nil
    return true
  end
  local ui = G.MAIN_MENU_UI
  if ui ~= M.menu_ui then M.menu_ui, M.menu_ready = ui, false end
  if M.menu_ready then return true end
  if type(ui) ~= "table" or not (ui.T and ui.VT) then return false end
  local room_h = (G.ROOM and G.ROOM.T and G.ROOM.T.h) or 11.5
  if ui.T.y + ui.T.h > room_h + 0.5 then return false end -- still parked below the screen
  if math.abs((ui.VT.y or 0) - (ui.T.y or 0)) > 0.05 then return false end -- still moving
  M.menu_ready = true
  return true
end

-- After the window goes away the scene keeps its hole for this long (a hub page change replaces the
-- window within a frame or two), then fades out over the whole screen.
M.HOLE_GRACE = 0.15

-- Keeps the optional layers, the sky and the cycling weather in line with the settings.
local function follow_settings(s, dt)
  M.sync_layers(s)
  if M.cycling() then
    s.next_cycle = (s.next_cycle or M.cycle_time()) - dt
    if s.next_cycle > M.cycle_time() then s.next_cycle = M.cycle_time() end
    if s.next_cycle <= 0 then
      local kind = M.pick_new(s.month, s.kind)
      M.change_weather(s, kind, true)
      M.last_kind = kind
      s.next_cycle = M.cycle_time()
      note("info", "cycled to %s", M.NAMES[kind] or kind)
    end
  else
    s.next_cycle = nil
  end
end

function M.draw()
  -- switched off (the setting, or Chromite is installed): what shows fades out
  local enabled = M.enabled()
  if not enabled and not M.state then M.alpha = 0; return end
  local now = type(love) == "table" and love.timer and love.timer.getTime() or 0
  -- the fades follow the clock (whatever the frame rate); the particles step at most 0.1 s a frame
  local elapsed = math.max(0, now - (M.last_t or now))
  M.last_t = now
  local dt = math.min(elapsed > 0 and elapsed or (type(G) == "table" and G.real_dt) or 0.016, 0.1)
  local box = current_box()
  local everywhere = M.everywhere()
  local g = love.graphics
  local sw, sh = g.getDimensions()
  local rect
  if enabled and (box or everywhere) then
    if not box then
      -- no window of ours open: a forced pick has ended
      if M.forced then M.forced = nil; M.built_for = M.want_key() end
      M.forced_sky = nil
    end
    if box then
      rect = M.window_rect(box)
      if not M.rect_ok(rect, sw, sh) then
        note("warn", "window rectangle %.0f,%.0f,%.0f,%.0f looks wrong, using a default", rect.x, rect.y, rect.w, rect.h)
        rect = M.fallback_rect(sw, sh)
      end
      M.rect, M.seen = rect, now
    end
    local want, key = M.wanted(), M.want_key()
    if M.state and M.built_for ~= key then
      local month = M.wanted_month()
      if M.only_season_changed(M.built_for, key) and want == nil then
        -- random kind, only the season setting changed: the same weather stays (the leaves take
        -- the new season's colours)
        M.state.month, M.state.season = month, M.season(month)
        M.built_for = key
      else
        -- the kind or season setting, or a forced kind, changed while shown: switch at once
        M.state.month, M.state.season = month, M.season(month)
        M.change_weather(M.state, want or M.pick_new(month), false)
        M.built_for, M.last_kind = key, M.state.kind
        note("info", "%s (%s), screen %dx%d", M.NAMES[M.state.kind] or M.state.kind, M.state.season, sw, sh)
      end
    end
    if not M.state then
      local month = M.wanted_month()
      M.built_for = key
      local kind = want or M.pick_new(month)
      M.state = M.new(sw, sh, kind, month, { clouds = M.cloud_level(kind) })
      M.last_kind = M.state.kind
      M.alpha = 0
      note("info", "%s (%s), screen %dx%d%s", M.NAMES[M.state.kind] or M.state.kind, M.state.season, sw, sh,
        everywhere and ", everywhere" or "")
    end
    if not box and not M.menu_settled() then
      M.alpha = 0 -- Everywhere on the main menu: wait for the menu buttons to pop in first
    else
      M.alpha = math.min(1, (M.alpha or 0) + elapsed / M.FADE_IN)
    end
  else
    if not M.state then return end
    -- a Test Bench pick ends with its window, but what shows stays until it fades out (a window that
    -- replaces this one a frame later keeps the same weather)
    if M.forced then M.forced = nil; M.built_for = M.want_key() end
    M.forced_sky = nil
    M.alpha = math.max(0, (M.alpha or 0) - elapsed / M.FADE_OUT)
    if M.alpha <= 0 then M.state = nil; return end
    -- only the around-the-window mode keeps a hole for a moment (a page change); a closed window
    -- leaves none, which showed as a box of undimmed screen while the rain faded out
    rect = M.mode == "around" and now - (M.seen or 0) < M.HOLE_GRACE and M.rect or nil
  end
  M.state = M.resize(M.state, sw, sh)
  follow_settings(M.state, dt)
  M.step(M.state, dt, M.cloud_level(M.state.kind))
  local a = M.alpha
  local fade = a * a * (3 - 2 * a) -- smooth in and out
  M.fade = fade
  if everywhere then pcall(M.hook_back) end
  if box then
    M.hook_under(box)
    -- drawn under the window this frame (between the game's dimmed backdrop and the window): done
    if M.under_frame and M.under_frame == (G.FRAMES and G.FRAMES.DRAW) then M.mode = "under"; return end
    -- a window that just replaced the last one has not been drawn by the game yet: while drawing under
    -- works, skip this one frame instead of punching an undimmed hole around it (a white flicker)
    if M.mode == "under" and not M.under_failed and M.under_frame and G.FRAMES and G.FRAMES.DRAW
      and G.FRAMES.DRAW - M.under_frame <= 2 then
      return
    end
    M.mode = "around"
  elseif everywhere then
    -- behind the game: drawn from the background sprite, never over the game
    M.mode = "back"
    return
  end
  g.push("all")
  -- the game leaves its own shader, blend mode, colour mask or stencil set after drawing its frame
  if g.reset then g.reset() end
  g.origin()
  if rect then
    for _, b in ipairs(M.bands(sw, sh, rect)) do
      g.setScissor(b.x, b.y, b.w, b.h)
      M.draw_scene(M.state, g, fade)
    end
    g.setScissor()
  else
    M.draw_scene(M.state, g, fade)
  end
  g.pop()
end

-- Draws over the finished frame. Installed once, the first time the scene is wanted.
function M.install()
  if M.hook or type(love) ~= "table" then return M.hook ~= nil end
  local hooks = require("better_background.hooks")
  M.hook = hooks.wrap(love, "draw", function(orig)
    return function(...)
      local ret = orig(...)
      if not M.failed then
        local ok, err = pcall(M.draw)
        if not ok then
          M.failed = true -- never keep a failing draw
          note("warn", "draw failed, switched off until restart: %s", tostring(err))
        end
      end
      return ret
    end
  end, { label = "love.draw (background)" })
  return M.hook ~= nil
end

return M
