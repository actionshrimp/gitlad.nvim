-- Tests for gitlad.state.cache module
local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

T["cache"] = MiniTest.new_set()

T["cache"]["new creates cache instance"] = function()
  local cache_mod = require("gitlad.state.cache")
  local cache = cache_mod.new()

  expect.equality(type(cache), "table")
  expect.equality(type(cache.entries), "table")
end

T["cache"]["get returns nil for missing key"] = function()
  local cache_mod = require("gitlad.state.cache")
  local cache = cache_mod.new()

  local data, valid = cache:get("nonexistent", "/tmp")
  eq(data, nil)
  eq(valid, false)
end

T["cache"]["set and get round-trip"] = function()
  local cache_mod = require("gitlad.state.cache")
  -- Use empty watched files so timestamps don't affect test
  local cache = cache_mod.new({})

  local test_data = { foo = "bar", count = 42 }
  cache:set("test_key", "/tmp", test_data)

  local data, valid = cache:get("test_key", "/tmp")
  eq(valid, true)
  eq(data.foo, "bar")
  eq(data.count, 42)
end

T["cache"]["invalidate removes entry"] = function()
  local cache_mod = require("gitlad.state.cache")
  local cache = cache_mod.new({})

  cache:set("test_key", "/tmp", { value = 1 })
  cache:invalidate("test_key")

  local data, valid = cache:get("test_key", "/tmp")
  eq(data, nil)
  eq(valid, false)
end

T["cache"]["invalidate_all clears all entries"] = function()
  local cache_mod = require("gitlad.state.cache")
  local cache = cache_mod.new({})

  cache:set("key1", "/tmp", { value = 1 })
  cache:set("key2", "/tmp", { value = 2 })
  cache:invalidate_all()

  local _, valid1 = cache:get("key1", "/tmp")
  local _, valid2 = cache:get("key2", "/tmp")
  eq(valid1, false)
  eq(valid2, false)
end

T["cache"]["is_valid returns correct status"] = function()
  local cache_mod = require("gitlad.state.cache")
  local cache = cache_mod.new({})

  eq(cache:is_valid("missing", "/tmp"), false)

  cache:set("present", "/tmp", { value = 1 })
  eq(cache:is_valid("present", "/tmp"), true)
end

T["cache"]["global returns singleton"] = function()
  local cache_mod = require("gitlad.state.cache")

  local g1 = cache_mod.global()
  local g2 = cache_mod.global()
  eq(g1, g2)
end

T["cache"]["reset_global creates new instance"] = function()
  local cache_mod = require("gitlad.state.cache")

  local g1 = cache_mod.global()
  g1:set("test", "/tmp", { value = 1 })

  cache_mod.reset_global()
  local g2 = cache_mod.global()

  -- New instance shouldn't have the old data
  local _, valid = g2:get("test", "/tmp")
  eq(valid, false)
end

return T
