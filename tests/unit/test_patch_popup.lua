local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

-- Patch popup builder tests
T["patch popup"] = MiniTest.new_set()

T["patch popup"]["creates top-level popup with correct actions"] = function()
  local popup = require("gitlad.ui.popup")

  local create_called = false
  local apply_called = false
  local am_called = false
  local save_called = false

  local data = popup
    .builder()
    :name("Patch")
    :group_heading("Create")
    :action("c", "Create patches", function()
      create_called = true
    end)
    :group_heading("Apply")
    :action("a", "Apply plain patch", function()
      apply_called = true
    end)
    :action("w", "Apply patches (git am)", function()
      am_called = true
    end)
    :group_heading("Save")
    :action("s", "Save diff as patch", function()
      save_called = true
    end)
    :build()

  eq(data.name, "Patch")

  -- 3 headings + 4 actions = 7
  eq(#data.actions, 7)

  -- Headings
  eq(data.actions[1].type, "heading")
  eq(data.actions[1].text, "Create")
  eq(data.actions[3].type, "heading")
  eq(data.actions[3].text, "Apply")
  eq(data.actions[6].type, "heading")
  eq(data.actions[6].text, "Save")

  -- Actions
  eq(data.actions[2].type, "action")
  eq(data.actions[2].key, "c")
  eq(data.actions[2].description, "Create patches")

  eq(data.actions[4].type, "action")
  eq(data.actions[4].key, "a")
  eq(data.actions[4].description, "Apply plain patch")

  eq(data.actions[5].type, "action")
  eq(data.actions[5].key, "w")
  eq(data.actions[5].description, "Apply patches (git am)")

  eq(data.actions[7].type, "action")
  eq(data.actions[7].key, "s")
  eq(data.actions[7].description, "Save diff as patch")

  -- Test callbacks
  data.actions[2].callback(data)
  eq(create_called, true)

  data.actions[4].callback(data)
  eq(apply_called, true)

  data.actions[5].callback(data)
  eq(am_called, true)

  data.actions[7].callback(data)
  eq(save_called, true)
end

T["patch popup"]["create sub-popup has correct switches and options"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :name("Create patches")
    :switch("l", "cover-letter", "Generate cover letter")
    :switch("R", "rfc", "Use [RFC PATCH] prefix")
    :switch("s", "signoff", "Add Signed-off-by line")
    :switch("n", "numbered", "Force numbered patches")
    :option("v", "reroll-count", "", "Reroll count (version number)")
    :option("o", "output-directory", "", "Output directory")
    :option("p", "subject-prefix", "", "Subject prefix")
    :build()

  eq(data.name, "Create patches")
  eq(#data.switches, 4)
  eq(data.switches[1].key, "l")
  eq(data.switches[1].cli, "cover-letter")
  eq(data.switches[2].key, "R")
  eq(data.switches[2].cli, "rfc")
  eq(data.switches[3].key, "s")
  eq(data.switches[3].cli, "signoff")
  eq(data.switches[4].key, "n")
  eq(data.switches[4].cli, "numbered")

  eq(#data.options, 3)
  eq(data.options[1].key, "v")
  eq(data.options[1].cli, "reroll-count")
  eq(data.options[2].key, "o")
  eq(data.options[2].cli, "output-directory")
  eq(data.options[3].key, "p")
  eq(data.options[3].cli, "subject-prefix")
end

T["patch popup"]["create sub-popup get_arguments returns enabled switches and options"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("l", "cover-letter", "Generate cover letter", { enabled = true })
    :switch("R", "rfc", "Use [RFC PATCH] prefix")
    :switch("s", "signoff", "Add Signed-off-by line", { enabled = true })
    :option("v", "reroll-count", "", "Reroll count")
    :option("o", "output-directory", "", "Output directory")
    :build()

  -- Set an option
  data:set_option("v", "2")

  local args = data:get_arguments()
  eq(#args, 3)
  eq(args[1], "--cover-letter")
  eq(args[2], "--signoff")
  eq(args[3], "--reroll-count=2")
end

T["patch popup"]["apply sub-popup has correct switches"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :name("Apply patch")
    :switch("3", "3way", "Fall back on 3-way merge")
    :switch("i", "index", "Also apply to index")
    :switch("c", "cached", "Only apply to index")
    :switch("R", "reverse", "Apply in reverse")
    :build()

  eq(data.name, "Apply patch")
  eq(#data.switches, 4)
  eq(data.switches[1].key, "3")
  eq(data.switches[1].cli, "3way")
  eq(data.switches[2].key, "i")
  eq(data.switches[2].cli, "index")
  eq(data.switches[3].key, "c")
  eq(data.switches[3].cli, "cached")
  eq(data.switches[4].key, "R")
  eq(data.switches[4].cli, "reverse")
end

T["patch popup"]["apply sub-popup get_arguments with 3way enabled"] = function()
  local popup = require("gitlad.ui.popup")

  local data = popup
    .builder()
    :switch("3", "3way", "Fall back on 3-way merge", { enabled = true })
    :switch("i", "index", "Also apply to index")
    :switch("c", "cached", "Only apply to index")
    :switch("R", "reverse", "Apply in reverse")
    :build()

  local args = data:get_arguments()
  eq(#args, 1)
  eq(args[1], "--3way")
end

return T
