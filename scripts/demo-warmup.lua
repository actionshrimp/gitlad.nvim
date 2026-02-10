-- Warmup script: installs treesitter parsers for the demo.
-- Run after demo-init.lua has loaded: -S scripts/demo-warmup.lua
-- Polls for parser compilation to complete, then quits.

local languages = { "javascript", "typescript", "lua", "markdown", "python" }

-- Trigger async parser installation
vim.cmd("TSInstall " .. table.concat(languages, " "))

-- Poll until all parsers are compiled, then quit
local attempts = 0
local timer = vim.uv.new_timer()
timer:start(1000, 1000, vim.schedule_wrap(function()
  attempts = attempts + 1

  local all_installed = true
  for _, lang in ipairs(languages) do
    if not pcall(vim.treesitter.language.inspect, lang) then
      all_installed = false
      break
    end
  end

  if all_installed then
    timer:stop()
    timer:close()
    print("All parsers installed.")
    vim.cmd("qall")
  elseif attempts > 45 then
    timer:stop()
    timer:close()
    print("Timeout waiting for parsers.")
    vim.cmd("cquit")
  end
end))
