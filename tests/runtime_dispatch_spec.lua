local Runtime = require("app.legacy_runtime")

local RuntimeDispatchSpec = {}

local function make_result()
  return {
    logs = {},
    failed = 0
  }
end

local function add_log(result, line)
  result.logs[#result.logs + 1] = line
end

local function expect_equal(result, label, actual, expected)
  local ok = actual == expected
  local status = ok and "PASS" or "FAIL"
  add_log(result, string.format("THEN %s: %s (expected %s, got %s)", status, label, tostring(expected), tostring(actual)))
  if not ok then
    result.failed = result.failed + 1
  end
end

local function with_overrides(overrides, fn)
  local originals = {}
  for key, value in pairs(overrides) do
    originals[key] = Runtime[key]
    Runtime[key] = value
  end

  local ok, result_or_err = pcall(fn)

  for key, value in pairs(originals) do
    Runtime[key] = value
  end

  if not ok then
    error(result_or_err)
  end

  return result_or_err
end

local function run_scene_switch_contract()
  local result = make_result()

  add_log(result, "GIVEN scene switching between gameplay/influence/card_library")
  Runtime.set_active_scene("influence")
  expect_equal(result, "set_active_scene(influence) applies", Runtime.get_active_scene(), "influence")

  Runtime.set_active_scene("gameplay")
  expect_equal(result, "set_active_scene(gameplay) applies", Runtime.get_active_scene(), "gameplay")

  Runtime.set_active_scene("card_library")
  expect_equal(result, "set_active_scene(card_library) applies", Runtime.get_active_scene(), "card_library")

  Runtime.set_active_scene("gameplay")
  expect_equal(result, "switching back from card library restores gameplay", Runtime.get_active_scene(), "gameplay")

  return result
end

local function run_generic_dispatch_contract()
  local result = make_result()

  local calls = {}
  with_overrides({
    update_gameplay = function()
      calls[#calls + 1] = "update:gameplay"
    end,
    update_influence = function()
      calls[#calls + 1] = "update:influence"
    end,
    update_card_library = function()
      calls[#calls + 1] = "update:card_library"
    end,
    draw_gameplay = function()
      calls[#calls + 1] = "draw:gameplay"
    end,
    draw_influence = function()
      calls[#calls + 1] = "draw:influence"
    end,
    draw_card_library = function()
      calls[#calls + 1] = "draw:card_library"
    end,
    keypressed_gameplay = function()
      calls[#calls + 1] = "key:gameplay"
    end,
    keypressed_influence = function()
      calls[#calls + 1] = "key:influence"
    end,
    keypressed_card_library = function()
      calls[#calls + 1] = "key:card_library"
    end,
    mousepressed_gameplay = function()
      calls[#calls + 1] = "mouse:gameplay"
    end,
    mousepressed_influence = function()
      calls[#calls + 1] = "mouse:influence"
    end,
    mousepressed_card_library = function()
      calls[#calls + 1] = "mouse:card_library"
    end,
    wheelmoved_gameplay = function()
      calls[#calls + 1] = "wheel:gameplay"
    end,
    wheelmoved_influence = function()
      calls[#calls + 1] = "wheel:influence"
    end,
    wheelmoved_card_library = function()
      calls[#calls + 1] = "wheel:card_library"
    end
  }, function()
    add_log(result, "GIVEN generic runtime callbacks with scene-specific handlers")

    Runtime.set_active_scene("gameplay")
    Runtime.update(0)
    Runtime.draw()
    Runtime.keypressed("a")
    Runtime.mousepressed(0, 0, 1)
    Runtime.wheelmoved(0, 1)

    Runtime.set_active_scene("influence")
    Runtime.update(0)
    Runtime.draw()
    Runtime.keypressed("a")
    Runtime.mousepressed(0, 0, 1)
    Runtime.wheelmoved(0, 1)

    Runtime.set_active_scene("card_library")
    Runtime.update(0)
    Runtime.draw()
    Runtime.keypressed("a")
    Runtime.mousepressed(0, 0, 1)
    Runtime.wheelmoved(0, 1)
  end)

  local expected = {
    "update:gameplay", "draw:gameplay", "key:gameplay", "mouse:gameplay", "wheel:gameplay",
    "update:influence", "draw:influence", "key:influence", "mouse:influence", "wheel:influence",
    "update:card_library", "draw:card_library", "key:card_library", "mouse:card_library", "wheel:card_library"
  }

  add_log(result, "WHEN generic callbacks are invoked across all active scenes")
  expect_equal(result, "dispatch call count", #calls, #expected)
  for i = 1, math.min(#calls, #expected) do
    expect_equal(result, "dispatch order " .. tostring(i), calls[i], expected[i])
  end

  Runtime.set_active_scene("gameplay")
  return result
end

local function run_named_scenario(name, fn)
  print("")
  print("Scenario: " .. name)
  local ok, result_or_err = pcall(fn)
  if not ok then
    print("  THEN FAIL: " .. tostring(result_or_err))
    return 0, 1
  end

  for _, line in ipairs(result_or_err.logs or {}) do
    print("  " .. line)
  end

  if (result_or_err.failed or 0) == 0 then
    print("  RESULT: PASS")
    return 1, 0
  end

  print("  RESULT: FAIL (" .. tostring(result_or_err.failed) .. " check(s) failed)")
  return 0, 1
end

function RuntimeDispatchSpec.run()
  local scenarios = {
    { name = "Scene Switching Contract", fn = run_scene_switch_contract },
    { name = "Generic Callback Dispatch Contract", fn = run_generic_dispatch_contract }
  }

  local passed = 0
  local failed = 0
  for _, scenario in ipairs(scenarios) do
    local scenario_passed, scenario_failed = run_named_scenario(scenario.name, scenario.fn)
    passed = passed + scenario_passed
    failed = failed + scenario_failed
  end

  return passed, failed
end

return RuntimeDispatchSpec
