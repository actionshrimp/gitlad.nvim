-- Batch test runner for gitlad.nvim
-- Runs a subset of tests from a test file based on indices
--
-- Environment variables:
--   TEST_FILE: the test file path (required)
--   TEST_BATCH: comma-separated list of test indices to run, 1-based (optional)
--              If not provided, runs all tests in the file
--   TEST_OUTPUT_MODE: "streaming" for per-test output, "standard" for mini.test default

local MiniTest = require("mini.test")
MiniTest.setup()

local test_file = os.getenv("TEST_FILE")
if not test_file then
  print("Error: TEST_FILE environment variable not set")
  vim.cmd("cq!")
  return
end

local batch_str = os.getenv("TEST_BATCH") or ""
local output_mode = os.getenv("TEST_OUTPUT_MODE") or "standard"

-- Parse batch indices into a lookup table
local batch_indices = {}
local run_all = (batch_str == "")
if not run_all then
  for idx in batch_str:gmatch("(%d+)") do
    batch_indices[tonumber(idx)] = true
  end
end

-- Track individual test start times
local case_start_times = {}

-- Custom reporter for streaming output with per-test timing
local streaming_reporter = {
  start = function() end,
  update = function(case_num)
    -- Get the case
    local cases = MiniTest.current.all_cases
    local case = cases[case_num]
    if not case or not case.exec then
      return
    end

    local state = case.exec.state

    -- Record start time when test begins executing
    if state == "Executing test" then
      case_start_times[case_num] = vim.loop.hrtime()
      return
    end

    -- Only print on final state (Pass or Fail)
    if state ~= "Pass" and state ~= "Fail" then
      return
    end

    -- Calculate elapsed time
    local elapsed_ms = 0
    if case_start_times[case_num] then
      local elapsed_ns = vim.loop.hrtime() - case_start_times[case_num]
      elapsed_ms = elapsed_ns / 1000000
    end

    -- Build test name from description hierarchy
    local test_name = case.desc[#case.desc] or "unknown"
    local module_name = vim.fn.fnamemodify(test_file, ":t:r"):gsub("^test_", "")
    local status = (state == "Pass") and "pass" or "FAIL"

    -- Format timing
    local time_str
    if elapsed_ms >= 1000 then
      time_str = string.format("%.1fs", elapsed_ms / 1000)
    else
      time_str = string.format("%dms", elapsed_ms)
    end

    -- Color marker for slow tests (>3s = warn, >5s = slow)
    local marker = ""
    if elapsed_ms >= 5000 then
      marker = "SLOW "
    elseif elapsed_ms >= 3000 then
      marker = "WARN "
    end

    -- Output: [TIME] MODULE STATUS TEST_NAME
    print(string.format("%s[%6s] %-18s %s  %s", marker, time_str, module_name, status, test_name))
  end,
  finish = function() end,
}

-- Track which test we're on and filter accordingly
local case_idx = 0
local run_opts = {
  collect = {
    find_files = function()
      return { test_file }
    end,
  },
}

-- Add filter if specific tests requested
if not run_all then
  run_opts.collect.filter_cases = function(_)
    case_idx = case_idx + 1
    return batch_indices[case_idx] or false
  end
end

-- Use streaming reporter if requested
if output_mode == "streaming" then
  run_opts.execute = { reporter = streaming_reporter }
end

MiniTest.run(run_opts)
