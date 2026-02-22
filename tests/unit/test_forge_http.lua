local MiniTest = require("mini.test")
local expect, eq = MiniTest.expect, MiniTest.expect.equality

local T = MiniTest.new_set()

local http = require("gitlad.forge.http")

-- =============================================================================
-- _build_command
-- =============================================================================

T["_build_command()"] = MiniTest.new_set()

T["_build_command()"]["builds basic GET request"] = function()
  local cmd = http._build_command({ url = "https://api.example.com/test" })
  eq(cmd[1], "curl")
  expect.equality(vim.tbl_contains(cmd, "-s"), true)
  expect.equality(vim.tbl_contains(cmd, "-S"), true)
  expect.equality(vim.tbl_contains(cmd, "GET"), true)
  eq(cmd[#cmd], "https://api.example.com/test")
end

T["_build_command()"]["builds POST request with body"] = function()
  local cmd = http._build_command({
    url = "https://api.example.com/graphql",
    method = "POST",
    body = '{"query": "{}"}',
  })
  expect.equality(vim.tbl_contains(cmd, "POST"), true)
  -- Find -d flag and verify body follows it
  for i, v in ipairs(cmd) do
    if v == "-d" then
      eq(cmd[i + 1], '{"query": "{}"}')
      break
    end
  end
end

T["_build_command()"]["includes headers"] = function()
  local cmd = http._build_command({
    url = "https://api.example.com/test",
    headers = {
      Authorization = "Bearer token123",
      ["Content-Type"] = "application/json",
    },
  })
  -- Should have two -H flags
  local h_count = 0
  local headers_found = {}
  for i, v in ipairs(cmd) do
    if v == "-H" then
      h_count = h_count + 1
      headers_found[cmd[i + 1]] = true
    end
  end
  eq(h_count, 2)
  expect.equality(headers_found["Authorization: Bearer token123"], true)
  expect.equality(headers_found["Content-Type: application/json"], true)
end

T["_build_command()"]["sets timeout"] = function()
  local cmd = http._build_command({
    url = "https://api.example.com/test",
    timeout = 10,
  })
  for i, v in ipairs(cmd) do
    if v == "--max-time" then
      eq(cmd[i + 1], "10")
      return
    end
  end
  error("--max-time not found in command")
end

T["_build_command()"]["uses default timeout of 30"] = function()
  local cmd = http._build_command({ url = "https://api.example.com/test" })
  for i, v in ipairs(cmd) do
    if v == "--max-time" then
      eq(cmd[i + 1], "30")
      return
    end
  end
  error("--max-time not found in command")
end

-- =============================================================================
-- _parse_response
-- =============================================================================

T["_parse_response()"] = MiniTest.new_set()

T["_parse_response()"]["parses successful JSON response"] = function()
  local stdout = { '{"name": "test", "id": 1}', "200" }
  local response, err = http._parse_response(stdout)
  eq(err, nil)
  eq(response.status, 200)
  eq(response.body, '{"name": "test", "id": 1}')
  eq(response.json.name, "test")
  eq(response.json.id, 1)
end

T["_parse_response()"]["parses multi-line response body"] = function()
  local stdout = { "{", '  "name": "test"', "}", "200" }
  local response, err = http._parse_response(stdout)
  eq(err, nil)
  eq(response.status, 200)
  eq(response.body, '{\n  "name": "test"\n}')
  eq(response.json.name, "test")
end

T["_parse_response()"]["handles non-JSON response"] = function()
  local stdout = { "Not Found", "404" }
  local response, err = http._parse_response(stdout)
  eq(err, nil)
  eq(response.status, 404)
  eq(response.body, "Not Found")
  eq(response.json, nil)
end

T["_parse_response()"]["handles empty response body"] = function()
  local stdout = { "204" }
  local response, err = http._parse_response(stdout)
  eq(err, nil)
  eq(response.status, 204)
  eq(response.body, "")
end

T["_parse_response()"]["returns error for empty stdout"] = function()
  local response, err = http._parse_response({})
  eq(response, nil)
  expect.equality(err ~= nil, true)
end

T["_parse_response()"]["returns error for nil stdout"] = function()
  local response, err = http._parse_response(nil)
  eq(response, nil)
  expect.equality(err ~= nil, true)
end

T["_parse_response()"]["returns error for non-numeric status"] = function()
  local response, err = http._parse_response({ "body", "not-a-number" })
  eq(response, nil)
  expect.equality(err:match("Failed to parse HTTP status code") ~= nil, true)
end

T["_parse_response()"]["handles various HTTP status codes"] = function()
  for _, status in ipairs({ "200", "201", "301", "400", "401", "403", "404", "500", "503" }) do
    local response, err = http._parse_response({ "{}", status })
    eq(err, nil)
    eq(response.status, tonumber(status))
  end
end

-- =============================================================================
-- request (with mock executor)
-- =============================================================================

T["request()"] = MiniTest.new_set({
  hooks = {
    post_case = function()
      http._set_executor(nil)
    end,
  },
})

T["request()"]["calls executor with correct command"] = function()
  local captured_cmd = nil
  http._set_executor(function(cmd, opts)
    captured_cmd = cmd
    -- Simulate success
    opts.on_stdout(nil, { '{"ok": true}', "200", "" })
    opts.on_exit(nil, 0)
    return 1
  end)

  local got_response = nil
  http.request({ url = "https://api.example.com/test" }, function(response, err)
    got_response = response
  end)

  expect.equality(captured_cmd ~= nil, true)
  eq(captured_cmd[1], "curl")
  eq(captured_cmd[#captured_cmd], "https://api.example.com/test")
end

T["request()"]["handles successful response"] = function()
  http._set_executor(function(cmd, opts)
    opts.on_stdout(nil, { '{"ok": true}', "200", "" })
    opts.on_exit(nil, 0)
    return 1
  end)

  local got_response = nil
  local got_err = nil
  http.request({ url = "https://api.example.com/test" }, function(response, err)
    got_response = response
    got_err = err
  end)

  -- Flush vim.schedule queue
  vim.wait(100, function()
    return got_response ~= nil
  end, 10)

  eq(got_err, nil)
  eq(got_response.status, 200)
  eq(got_response.json.ok, true)
end

T["request()"]["handles curl failure"] = function()
  http._set_executor(function(cmd, opts)
    opts.on_stderr(nil, { "Could not resolve host", "" })
    opts.on_exit(nil, 6)
    return 1
  end)

  local got_response = nil
  local got_err = nil
  http.request({ url = "https://bad.example.com" }, function(response, err)
    got_response = response
    got_err = err
  end)

  -- Flush vim.schedule queue
  vim.wait(100, function()
    return got_err ~= nil
  end, 10)

  eq(got_response, nil)
  expect.equality(got_err:match("curl failed") ~= nil, true)
end

T["request()"]["handles timeout (exit code -1)"] = function()
  http._set_executor(function(cmd, opts)
    opts.on_exit(nil, -1)
    return 1
  end)

  local got_err = nil
  http.request({ url = "https://slow.example.com", timeout = 1 }, function(response, err)
    got_err = err
  end)

  -- Flush vim.schedule queue
  vim.wait(100, function()
    return got_err ~= nil
  end, 10)

  eq(got_err, "Request timed out")
end

T["request()"]["returns job_id for cancellation"] = function()
  http._set_executor(function()
    return 42
  end)

  local job_id = http.request({ url = "https://api.example.com/test" }, function() end)
  eq(job_id, 42)
end

T["request()"]["does not call callback twice"] = function()
  http._set_executor(function(cmd, opts)
    opts.on_stdout(nil, { '{"ok": true}', "200", "" })
    opts.on_exit(nil, 0)
    -- Call on_exit again (shouldn't trigger second callback)
    opts.on_exit(nil, 0)
    return 1
  end)

  local call_count = 0
  http.request({ url = "https://api.example.com/test" }, function()
    call_count = call_count + 1
  end)

  -- Flush vim.schedule queue
  vim.wait(100, function()
    return call_count > 0
  end, 10)

  eq(call_count, 1)
end

return T
