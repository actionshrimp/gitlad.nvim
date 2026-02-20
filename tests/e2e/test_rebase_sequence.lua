-- End-to-end tests for rebase sequence display ordering in the status buffer
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      local child = MiniTest.new_child_neovim()
      child.start({ "-u", "tests/minimal_init.lua" })
      _G.child = child
    end,
    post_case = function()
      if _G.child then
        _G.child.stop()
        _G.child = nil
      end
    end,
  },
})

--- Helper: create a repo with a linear history of commits on a branch, then
--- start an interactive rebase that stops at the desired point.
---
--- Creates commits A, B, C, D on main:
---   A -- B -- C -- D  (main)
---
--- @param child table MiniTest child process
--- @param opts table {stop_action: "conflict"|"edit", stop_at: number}
---   stop_at: which commit to stop on (1=B, 2=C, 3=D)
---   stop_action: "conflict" to cause a conflict, "edit" to use edit action
--- @return string repo_path
local function setup_rebase_stop(child, opts)
  local repo = helpers.create_test_repo(child)

  -- Create base commit A
  helpers.create_file(child, repo, "base.txt", "base content\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "A: base commit"')

  -- Create commits B, C, D that each touch their own file
  helpers.create_file(child, repo, "b.txt", "B content\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "B: second commit"')

  helpers.create_file(child, repo, "c.txt", "C content\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "C: third commit"')

  helpers.create_file(child, repo, "d.txt", "D content\n")
  helpers.git(child, repo, "add .")
  helpers.git(child, repo, 'commit -m "D: fourth commit"')

  if opts.stop_action == "conflict" then
    -- For conflict stops: amend the base commit to conflict with the target
    -- We'll do a rebase and use a sed-based sequence editor to keep picks,
    -- but first create a conflict on the target file.
    local target_file = ({ "b.txt", "c.txt", "d.txt" })[opts.stop_at]

    -- Build a sequence editor that keeps all as "pick" (default)
    -- The conflict will naturally stop the rebase
    -- First, modify the target file on the base so rebase hits a conflict
    -- We'll use a different approach: create a new branch from A, change target file, then rebase

    -- Reset to A, create conflicting content, then cherry-pick or rebase
    -- Simpler: just rewrite the file that commit opts.stop_at touches, creating a conflict
    -- We need to rebase onto a modified base that conflicts.

    -- Approach: create a side branch from A with a conflicting change,
    -- then rebase B..D onto it.
    helpers.git(child, repo, "checkout -b rebase-target HEAD~3") -- at A
    helpers.create_file(child, repo, target_file, "CONFLICTING content\n")
    helpers.git(child, repo, "add .")
    helpers.git(child, repo, 'commit -m "conflict base"')

    -- Go back to main and rebase onto rebase-target
    helpers.git(child, repo, "checkout main")
    -- Use a no-op sequence editor to keep all picks
    child.lua(
      string.format(
        [[vim.fn.system("cd %s && GIT_SEQUENCE_EDITOR=true git rebase -i rebase-target 2>&1")]],
        repo
      )
    )
  elseif opts.stop_action == "edit" then
    -- For edit stops: rebase interactively and change the target commit to "edit"
    -- Write a shell script that changes the Nth "pick" to "edit" in the todo file
    local stop_line = opts.stop_at -- 1=B (first after A), 2=C, 3=D
    local script_path = repo .. "/edit_todo.sh"

    child.lua(string.format(
      [[
      local f = io.open(%q, "w")
      f:write("#!/bin/sh\n")
      f:write("n=0\n")
      f:write("while IFS= read -r line; do\n")
      f:write("  case \"$line\" in\n")
      f:write("    pick*)\n")
      f:write("      n=$((n + 1))\n")
      f:write("      if [ $n -eq %d ]; then\n")
      f:write("        echo \"edit${line#pick}\"\n")
      f:write("      else\n")
      f:write("        echo \"$line\"\n")
      f:write("      fi\n")
      f:write("      ;;\n")
      f:write("    *) echo \"$line\" ;;\n")
      f:write("  esac\n")
      f:write("done < \"$1\" > \"$1.tmp\"\n")
      f:write("mv \"$1.tmp\" \"$1\"\n")
      f:close()
      vim.fn.system("chmod +x " .. %q)
      ]],
      script_path,
      stop_line,
      script_path
    ))

    child.lua(
      string.format(
        [[vim.fn.system("cd %s && GIT_SEQUENCE_EDITOR=%s git rebase -i HEAD~3 2>&1")]],
        repo,
        repo .. "/edit_todo.sh"
      )
    )
  end

  -- Give git a moment to settle
  helpers.wait_short(child, 100)

  return repo
end

--- Helper: get all buffer lines from the status buffer
local function get_status_lines(child)
  return child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]])
end

--- Helper: find lines matching a pattern, returns list of {index, line}
local function find_lines(lines, pattern)
  local matches = {}
  for i, line in ipairs(lines) do
    if line:match(pattern) then
      table.insert(matches, { index = i, line = line })
    end
  end
  return matches
end

--- Helper: extract the rebase section lines (between "Rebasing" header and next blank/section)
local function get_rebase_section_lines(lines)
  local in_section = false
  local section = {}
  for _, line in ipairs(lines) do
    if line:match("^Rebasing ") then
      in_section = true
    elseif in_section then
      -- Section ends at blank line or next section header
      if line == "" or (line:match("^%u") and not line:match("^[a-z]")) then
        break
      end
      table.insert(section, line)
    end
  end
  return section
end

T["rebase sequence"] = MiniTest.new_set()

T["rebase sequence"]["conflict stop midway shows reversed todo order"] = function()
  local child = _G.child
  -- Stop at commit C (second of three), so B is done, C conflicts, D is todo
  local repo = setup_rebase_stop(child, { stop_action = "conflict", stop_at = 2 })

  helpers.open_gitlad(child, repo)

  -- Wait for the rebase section to appear
  local found = helpers.wait_for_status_content(child, "Rebasing")
  eq(found, true)

  local lines = get_status_lines(child)
  local section = get_rebase_section_lines(lines)

  -- Should have: todo (D), stop (C), done (B), onto
  -- With reversed todo, D should be listed (only one todo, so order doesn't matter here)
  local todo_lines = find_lines(section, "^pick ")
  local stop_lines = find_lines(section, "^stop ")
  local done_lines = find_lines(section, "^done ")
  local onto_lines = find_lines(section, "^onto ")

  -- D is the remaining todo
  eq(#todo_lines, 1)
  eq(todo_lines[1].line:find("D: fourth commit") ~= nil, true)

  -- C is the stopped commit
  eq(#stop_lines, 1)
  eq(stop_lines[1].line:find("C: third commit") ~= nil, true)

  -- B is done (already rebased)
  eq(#done_lines, 1)
  eq(done_lines[1].line:find("B: second commit") ~= nil, true)

  -- Onto line exists
  eq(#onto_lines, 1)

  -- Verify ordering: todo before stop before done before onto
  eq(todo_lines[1].index < stop_lines[1].index, true)
  eq(stop_lines[1].index < done_lines[1].index, true)
  eq(done_lines[1].index < onto_lines[1].index, true)

  helpers.cleanup_repo(child, repo)
end

T["rebase sequence"]["conflict stop with multiple todos shows reversed order"] = function()
  local child = _G.child
  -- Stop at commit B (first of three), so B conflicts, C and D are todos
  local repo = setup_rebase_stop(child, { stop_action = "conflict", stop_at = 1 })

  helpers.open_gitlad(child, repo)

  local found = helpers.wait_for_status_content(child, "Rebasing")
  eq(found, true)

  local lines = get_status_lines(child)
  local section = get_rebase_section_lines(lines)

  -- Should have: todo (D, C in reversed order), stop (B), no done, onto
  local todo_lines = find_lines(section, "^pick ")
  local stop_lines = find_lines(section, "^stop ")
  local done_lines = find_lines(section, "^done ")
  local onto_lines = find_lines(section, "^onto ")

  -- Two remaining todos: C and D, but in reversed order (D first, then C)
  eq(#todo_lines, 2)
  -- D should be first (furthest from application)
  eq(todo_lines[1].line:find("D: fourth commit") ~= nil, true)
  -- C should be second (next to be applied, adjacent to stop)
  eq(todo_lines[2].line:find("C: third commit") ~= nil, true)

  -- B is the stopped commit
  eq(#stop_lines, 1)
  eq(stop_lines[1].line:find("B: second commit") ~= nil, true)

  -- No done commits (B was the first and it conflicted)
  eq(#done_lines, 0)

  -- Onto line exists
  eq(#onto_lines, 1)

  helpers.cleanup_repo(child, repo)
end

T["rebase sequence"]["edit stop at first commit shows no duplicates"] = function()
  local child = _G.child
  -- Edit stop at B (first commit), so B is "stop", C and D are todos, no done
  local repo = setup_rebase_stop(child, { stop_action = "edit", stop_at = 1 })

  helpers.open_gitlad(child, repo)

  local found = helpers.wait_for_status_content(child, "Rebasing")
  eq(found, true)

  local lines = get_status_lines(child)
  local section = get_rebase_section_lines(lines)

  local todo_lines = find_lines(section, "^pick ")
  local stop_lines = find_lines(section, "^stop ")
  local done_lines = find_lines(section, "^done ")
  local onto_lines = find_lines(section, "^onto ")

  -- C and D are todos (reversed: D first, C second)
  eq(#todo_lines, 2)
  eq(todo_lines[1].line:find("D: fourth commit") ~= nil, true)
  eq(todo_lines[2].line:find("C: third commit") ~= nil, true)

  -- B is the stopped commit
  eq(#stop_lines, 1)
  eq(stop_lines[1].line:find("B: second commit") ~= nil, true)

  -- No done commits - B is shown as stop, not duplicated in done
  -- (edit applies the commit before stopping, so git log onto..HEAD includes it,
  -- but we skip it to avoid the duplicate)
  eq(#done_lines, 0)

  eq(#onto_lines, 1)

  helpers.cleanup_repo(child, repo)
end

T["rebase sequence"]["edit stop midway shows no duplicate and correct done"] = function()
  local child = _G.child
  -- Edit stop at C (second commit): B is done, C is stop, D is todo
  local repo = setup_rebase_stop(child, { stop_action = "edit", stop_at = 2 })

  helpers.open_gitlad(child, repo)

  local found = helpers.wait_for_status_content(child, "Rebasing")
  eq(found, true)

  local lines = get_status_lines(child)
  local section = get_rebase_section_lines(lines)

  local todo_lines = find_lines(section, "^pick ")
  local stop_lines = find_lines(section, "^stop ")
  local done_lines = find_lines(section, "^done ")
  local onto_lines = find_lines(section, "^onto ")

  -- D is the only todo
  eq(#todo_lines, 1)
  eq(todo_lines[1].line:find("D: fourth commit") ~= nil, true)

  -- C is the stopped commit
  eq(#stop_lines, 1)
  eq(stop_lines[1].line:find("C: third commit") ~= nil, true)

  -- B is done (and C is NOT duplicated here)
  eq(#done_lines, 1)
  eq(done_lines[1].line:find("B: second commit") ~= nil, true)

  eq(#onto_lines, 1)

  -- Verify section ordering: todo < stop < done < onto
  eq(todo_lines[1].index < stop_lines[1].index, true)
  eq(stop_lines[1].index < done_lines[1].index, true)
  eq(done_lines[1].index < onto_lines[1].index, true)

  helpers.cleanup_repo(child, repo)
end

T["rebase sequence"]["full section ordering is todo, stop, done, onto top to bottom"] = function()
  local child = _G.child
  -- Edit stop at C: B is done, C is stop, D is todo
  local repo = setup_rebase_stop(child, { stop_action = "edit", stop_at = 2 })

  helpers.open_gitlad(child, repo)

  local found = helpers.wait_for_status_content(child, "Rebasing")
  eq(found, true)

  local lines = get_status_lines(child)
  local section = get_rebase_section_lines(lines)

  -- Collect all action prefixes in order
  local actions = {}
  for _, line in ipairs(section) do
    local action = line:match("^(%S+) ")
    if action then
      table.insert(actions, action)
    end
  end

  -- Expected order: pick (todo D), stop (C), done (B), onto
  eq(#actions, 4)
  eq(actions[1], "pick")
  eq(actions[2], "stop")
  eq(actions[3], "done")
  eq(actions[4], "onto")

  helpers.cleanup_repo(child, repo)
end

return T
