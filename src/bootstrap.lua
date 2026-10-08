-- Better Background bootstrap, appended to main.lua by lovely/core.toml.
-- Runs after main.lua has defined Game and the love.* callbacks, before love.load.
do
  local ok, err = pcall(function() require("better_background").boot() end)
  if not ok then print("[Better Background] failed to start: " .. tostring(err)) end
end
