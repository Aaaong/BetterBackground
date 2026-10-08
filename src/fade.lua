-- Window transitions: windows fade into each other instead of sliding up from
-- the bottom. When an overlay opens, closes or is replaced, the last frame is
-- copied from the game's canvas, the new overlay is placed straight in the
-- middle (no slide), and the copy is drawn over the new frame, fading out over
-- DURATION seconds. The copy is drawn into the game's canvas just before the
-- pointer, so the screen effects still apply and the pointer stays on top.
-- Clicks are never held back: the new window works while it fades in.
--
-- From Chromite's ui/fade.lua. Chromite's "only Chromite windows" choice is left out: here every
-- game window fades. Setting: fade (on/off).

local hooks = require("better_background.hooks")
local Config = require("better_background.config")

local util = { now = function() return love.timer.getTime() end }
local log = { warn = function(...) print("[Better Background] warn: " .. string.format(...)) end }

local M = { DURATION = 0.25, alpha = 0, draws = 0, opening = false }

-- M.active is false while Chromite is installed: it fades windows itself.
function M.on() return M.active ~= false and Config.get("fade") ~= false end
function M.everywhere() return true end

-- (Chromite fades changes inside its own windows; there are none here.)
local function is_chromite(box) return false end

-- Whether a change of overlay fades. `chromite`: a Chromite window is involved.
function M.applies(chromite)
  if not M.on() then return false end
  return M.everywhere() or chromite == true
end

-- Joins two clip rectangles; nil (the whole screen) wins.
function M.union(a, b)
  if not a or not b then return nil end
  local x0, y0 = math.min(a.x, b.x), math.min(a.y, b.y)
  local x1, y1 = math.max(a.x + a.w, b.x + b.w), math.max(a.y + a.h, b.y + b.h)
  return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

M.MARGIN = 8 -- pixels around the window, for its shadow and outline

-- The open overlay in screen pixels (with a margin), or nil when it can't be measured.
function M.window_clip()
  local box = type(G) == "table" and G.OVERLAY_MENU
  if type(box) ~= "table" then return nil end
  local ok, bg = pcall(require, "better_background.background")
  if not ok or type(bg.window_rect) ~= "function" then return nil end
  local ok2, r = pcall(bg.window_rect, box)
  if not ok2 or type(r) ~= "table" or not (r.w and r.w > 0 and r.h and r.h > 0) then return nil end
  local m = M.MARGIN
  return { x = r.x - m, y = r.y - m, w = r.w + 2 * m, h = r.h + 2 * m }
end

-- Copies the frame on screen (still in the game's canvas until the next draw). `clip` (screen
-- pixels) limits the fade to that rectangle; nil fades the whole screen.
function M.snapshot(clip)
  local g = love and love.graphics
  local src = type(G) == "table" and G.CANVAS
  if not (src and g and g.newCanvas and src.getDimensions) then return false end
  -- a second change before the next draw: the canvas still holds the same frame
  if M.alpha > 0 and M.snap_draw == M.draws then
    M.clip = M.union(M.clip, clip)
    return true
  end
  local w, h = src:getDimensions()
  if not M.canvas or M.cw ~= w or M.ch ~= h then
    if M.canvas and M.canvas.release then M.canvas:release() end
    M.canvas, M.cw, M.ch = g.newCanvas(w, h), w, h
  end
  g.push("all")
  g.setCanvas(M.canvas)
  g.origin()
  g.setShader()
  g.setBlendMode("replace")
  g.setColor(1, 1, 1, 1)
  g.draw(src, 0, 0)
  g.pop()
  M.alpha, M.started, M.snap_draw, M.clip, M.clip_source = 1, util.now(), M.draws, clip, nil
  return true
end

-- A box in screen pixels (with the margin), from where it is drawn now.
function M.box_rect(box, target)
  local VT = type(box) == "table" and ((target and box.T) or box.VT or box.T)
  if not (VT and VT.w and VT.h) then return nil end
  local ppu = (G.TILESCALE or 1) * (G.TILE_SIZE or 20)
  local ox, oy = (G.ROOM and G.ROOM.T.x) or 0, (G.ROOM and G.ROOM.T.y) or 0
  local m = M.MARGIN
  return { x = (VT.x + ox) * ppu - m, y = (VT.y + oy) * ppu - m, w = VT.w * ppu + 2 * m, h = VT.h * ppu + 2 * m }
end

-- A change to one box outside any window (the main menu's Chromite column opening its dropdown):
-- fades just that box. `now` returns the box that replaces it, so a box that grew is covered too.
function M.region(box, now)
  if not M.on() then return false end
  local clip = M.box_rect(box)
  if not clip then return false end
  M.hook_cursor()
  local ok, res = pcall(M.snapshot, clip)
  if ok and res then
    -- the new box by where it is going (T): in its first frame its VT can still be where it was
    -- built, and the union with that covered a large patch of screen with the old frame (round 7)
    M.clip_source = function() return M.box_rect(now and now() or box, true) end
  end
  return ok and res == true
end

-- A change inside the open Chromite window: fades just the window.
function M.refresh()
  if not M.applies(true) then return false end
  local box = type(G) == "table" and G.OVERLAY_MENU
  if not is_chromite(box) then return false end
  local clip = M.window_clip()
  if not clip then return false end
  M.hook_cursor()
  local ok, res = pcall(M.snapshot, clip)
  return ok and res == true
end

-- Draws the copy over the new frame (called from the pointer's draw, inside the game's canvas).
function M.draw_snapshot()
  M.draws = M.draws + 1
  if M.alpha <= 0 or not M.canvas then return end
  local t = (util.now() - (M.started or 0)) / M.DURATION
  M.alpha = 1 - t
  if M.alpha <= 0 then
    M.alpha = 0
    return
  end
  -- eased, so the old frame lets go quickly at first and settles softly
  local a = M.alpha * M.alpha
  local g = love.graphics
  g.push("all")
  g.origin()
  g.setShader()
  g.setBlendMode("alpha", "premultiplied")
  g.setColor(a, a, a, a)
  if M.clip then
    -- the window may have grown since: cover where it is now too
    local cur = M.clip_source and M.clip_source() or (not M.clip_source and M.window_clip()) or nil
    local r = M.union(M.clip, cur or M.clip)
    local sx = M.cw / math.max(1, (g.getWidth and g.getWidth()) or M.cw)
    local x0, y0 = math.max(0, math.floor(r.x * sx)), math.max(0, math.floor(r.y * sx))
    local x1, y1 = math.min(M.cw, math.ceil((r.x + r.w) * sx)), math.min(M.ch, math.ceil((r.y + r.h) * sx))
    if x1 <= x0 or y1 <= y0 then g.pop(); return end
    g.setScissor(x0, y0, x1 - x0, y1 - y0)
  end
  g.draw(M.canvas, 0, 0)
  g.pop()
end

-- The pointer is drawn last into the game's canvas: the copy goes right under it.
function M.hook_cursor()
  local cur = type(G) == "table" and G.CURSOR
  if type(cur) ~= "table" or cur.better_background_fade then return end
  local orig = cur.draw
  if type(orig) ~= "function" then return end
  cur.draw = function(self, ...)
    pcall(M.draw_snapshot)
    return orig(self, ...)
  end
  cur.better_background_fade = true
end

function M.install()
  if M.installed or type(G) ~= "table" or type(G.FUNCS) ~= "table" then return end
  if type(G.FUNCS.overlay_menu) ~= "function" or type(G.FUNCS.exit_overlay_menu) ~= "function" then return end
  M.installed = true
  hooks.wrap(G.FUNCS, "overlay_menu", function(orig)
    return function(args, ...)
      if args and M.applies(M.opening or is_chromite(G.OVERLAY_MENU)) then
        M.hook_cursor()
        -- a Chromite window replaced in place (a page refreshed): only the window fades
        local clip = M.still and is_chromite(G.OVERLAY_MENU) and M.window_clip() or nil
        local ok, err = pcall(M.snapshot, clip)
        if not ok then log.warn("fade: %s", tostring(err)) end
        -- straight to the middle instead of sliding up from below
        args.config = args.config or {}
        args.config.offset = args.config.offset or { x = 0, y = 0 }
      end
      return orig(args, ...)
    end
  end, { label = "G.FUNCS.overlay_menu (fade)" })
  hooks.wrap(G.FUNCS, "exit_overlay_menu", function(orig)
    return function(...)
      if G.OVERLAY_MENU and M.applies(is_chromite(G.OVERLAY_MENU)) then
        M.hook_cursor()
        pcall(M.snapshot)
      end
      return orig(...)
    end
  end, { label = "G.FUNCS.exit_overlay_menu (fade)" })
end

return M
