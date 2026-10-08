-- Hook registry (from Chromite's core/hooks.lua). Better Background wraps existing functions instead
-- of replacing source lines. Every wrap records its owner (a feature id or "core"), keeps the
-- original, and logs targets it could not find, so a game or mod update shows
-- up in the log.
--
--   Hooks.wrap(owner_table, "name", function(orig) return function(...) ... end end,
--              { label = "Game:update (speed)", owner = "extended_speed" })
--
-- `make(orig)` returns the replacement. Unwrapping is safe in any order: if
-- other mods wrapped on top of ours, our layer stays in the chain but passes
-- straight through to the original.
-- A hook that throws is logged, switched off, and the original runs instead
-- (unless the hook already called it); "hook:error" is emitted with its owner.

local M = { installed = {}, failed = {}, late = {}, stacks_logged = {} }

local function log(level, ...)
  local ok, msg = pcall(string.format, ...)
  print("[Better Background] " .. level .. ": " .. tostring(ok and msg or (...)))
end

local unpack = table.unpack or unpack

local function describe(owner, key, opts)
  if opts and opts.label then return opts.label end
  return tostring(key)
end

function M.wrap(target, key, make, opts)
  opts = opts or {}
  local label = describe(target, key, opts)
  if type(target) ~= "table" or type(target[key]) ~= "function" then
    M.failed[#M.failed + 1] = label
    log("warn", "hook target missing: %s (game or mod version mismatch?)", label)
    return nil
  end
  local orig = target[key]
  local hook = { target = target, key = key, label = label, owner = opts.owner or "core", orig = orig }

  -- Errors raised by the original function are the game's (or another mod's),
  -- not this hook's: they pass through untouched and never switch the hook off.
  -- The stack where the original failed is kept: rethrowing loses it, and a crash report would
  -- only show this wrapper.
  local function keep_stack(e)
    hook.orig_tb = (debug and debug.traceback) and debug.traceback(tostring(e), 2) or tostring(e)
    return e
  end
  local function pass(ok, ...)
    if ok then return ... end
    local err = ...
    hook.orig_err = err
    error(err, 0)
  end
  local function guarded_orig(...)
    hook.called = true
    return pass(xpcall(orig, keep_stack, ...))
  end
  local okm, fn = pcall(make, guarded_orig)
  if not okm or type(fn) ~= "function" then
    M.failed[#M.failed + 1] = label
    log("error", "hook %s could not be built: %s", label, tostring(fn))
    return nil
  end

  -- The wrapper runs for every call (CardArea:draw and :update run for every card area, every
  -- frame, through many hooks), so its success path allocates nothing: the hook's results go
  -- straight through `after`. The arguments are kept in one reused table per call depth (calls can
  -- nest) for the rare case where the hook fails before calling the original and that has to run
  -- instead (round 7: per-call tables made the garbage collector pause the game every so often).
  local stash, depth = {}, 0
  local function after(ok, ...)
    local args = stash[depth]
    depth = depth - 1
    if ok then return ... end
    local err = ...
    if hook.orig_err ~= nil and err == hook.orig_err then
      -- the original failed, not us: log where (once per message), then pass the error on
      local msg = tostring(err)
      if hook.orig_tb and not M.stacks_logged[msg] then
        M.stacks_logged[msg] = true
        log("error", "error inside %s (not Better Background's hook; where it happened):\n%s", label, hook.orig_tb)
      end
      -- the crash screen shows only where error() was called (here), so the original stack
      -- rides along in the message; a non-string error is passed on as it is
      if type(err) == "string" and hook.orig_tb and not err:find("Better Background: passed through", 1, true) then
        error(err .. "\n\nBetter Background: passed through " .. label .. ", where it happened:\n" .. hook.orig_tb, 0)
      end
      error(err, 0)
    end
    -- hook failed: log, switch it off, keep the game running
    hook.dead = true
    log("error", "hook %s failed and was switched off: %s", label, tostring(err))
    if not hook.called then return orig(unpack(args, 1, args.n)) end
  end

  local function wrapper(...)
    if hook.dead then return orig(...) end
    hook.called, hook.orig_err = false, nil
    depth = depth + 1
    local args = stash[depth]
    if not args then args = {}; stash[depth] = args end
    local n = select("#", ...)
    args.n = n
    for i = 1, n do args[i] = (select(i, ...)) end
    return after(pcall(fn, ...))
  end
  hook.wrapper = wrapper
  target[key] = wrapper
  M.installed[#M.installed + 1] = hook
  return hook
end

function M.unwrap(hook)
  if not hook or hook.dead == "removed" then return false end
  if hook.target[hook.key] == hook.wrapper then
    hook.target[hook.key] = hook.orig -- ours is on top: restore for real
  end
  hook.dead = "removed"
  for i, h in ipairs(M.installed) do
    if h == hook then table.remove(M.installed, i); break end
  end
  return true
end

-- Removes every live hook owned by `owner` (a feature that forgot to). Returns how many.
function M.unwrap_owner(owner)
  local mine = {}
  for _, h in ipairs(M.installed) do
    if h.owner == owner then mine[#mine + 1] = h end
  end
  for i = #mine, 1, -1 do M.unwrap(mine[i]) end
  return #mine
end

function M.count(owner)
  local n = 0
  for _, h in ipairs(M.installed) do
    if not owner or h.owner == owner then n = n + 1 end
  end
  return n
end

-- Steamodded replaces some game functions while Game:start_up runs, after
-- Better Background boots. Hooks on those functions register here and are installed
-- once start_up has finished.
-- Once start_up has finished (M.started), it runs at once.
function M.after_start_up(fn)
  if M.started then
    local ok, err = pcall(fn)
    if not ok then log("error", "late hook failed: %s", tostring(err)) end
    return
  end
  M.late[#M.late + 1] = fn
end

function M.run_late()
  M.started = true
  local list = M.late
  M.late = {}
  for _, fn in ipairs(list) do
    local ok, err = pcall(fn)
    if not ok then log("error", "late hook failed: %s", tostring(err)) end
  end
end

return M
