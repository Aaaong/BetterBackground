-- Steamodded entry point (metadata.json main_file). Better Background itself is loaded by Lovely
-- (lovely/core.toml), so this only gives Steamodded the settings page. Without Steamodded this
-- file never runs and the mod works alone.

local ok, B = pcall(require, "better_background")
if not ok or type(B) ~= "table" then
  print("[Better Background] Steamodded shim: core module not found (is lovely/core.toml installed?)")
  return
end

B.boot() -- no-op when Lovely already booted it
B.attach_smods(SMODS and SMODS.current_mod or nil)

-- The mod's icon in Steamodded's mod list.
if SMODS and SMODS.Atlas then
  SMODS.Atlas({ key = "modicon", path = "icon.png", px = 32, py = 32 })
end
