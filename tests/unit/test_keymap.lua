-- Tests for gitlad.utils.keymap module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["keymap"] = MiniTest.new_set()

T["keymap"]["set creates buffer-local keymap"] = function()
  local keymap = require("gitlad.utils.keymap")

  -- Create a test buffer
  local bufnr = vim.api.nvim_create_buf(false, true)

  keymap.set(bufnr, "n", "<leader>t", function() end, "Test keymap")

  -- Get the keymap and verify it exists
  local maps = vim.api.nvim_buf_get_keymap(bufnr, "n")
  local found = false
  for _, map in ipairs(maps) do
    if map.lhs == " t" or map.lhs == "<Leader>t" then
      found = true
      eq(map.desc, "Test keymap")
      eq(map.silent, 1)
      break
    end
  end

  expect.equality(found, true)

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["keymap"]["set works with multiple modes"] = function()
  local keymap = require("gitlad.utils.keymap")

  local bufnr = vim.api.nvim_create_buf(false, true)

  keymap.set(bufnr, { "n", "v" }, "s", function() end, "Test multi-mode")

  local n_maps = vim.api.nvim_buf_get_keymap(bufnr, "n")
  local v_maps = vim.api.nvim_buf_get_keymap(bufnr, "v")

  local found_n = false
  local found_v = false

  for _, map in ipairs(n_maps) do
    if map.lhs == "s" then
      found_n = true
      break
    end
  end

  for _, map in ipairs(v_maps) do
    if map.lhs == "s" then
      found_v = true
      break
    end
  end

  expect.equality(found_n, true)
  expect.equality(found_v, true)

  -- Cleanup
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
