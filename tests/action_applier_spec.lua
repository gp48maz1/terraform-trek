local ScenarioCases = require("tests.scenario_cases")
local ActionApplier = require("systems.action_applier")
local CardTypes = require("card_types")

local ActionApplierSpec = {}

local STATS = { "heat", "air", "water", "soil" }

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

local function run_preview_stats_delta_scenario()
  local result = make_result()
  local state = ScenarioCases.new_state()
  local before_heat = state.stats.heat
  local snapshot = {
    heat = state.stats.heat,
    air = state.stats.air,
    water = state.stats.water,
    soil = state.stats.soil
  }
  local economy = state:get_economy_snapshot()

  add_log(result, "GIVEN preview snapshot copied from live stats")
  ActionApplier.apply_action_preview(state, snapshot, economy, {
    type = "stats_delta",
    changes = { heat = 2, soil = -1 }
  })
  add_log(result, "WHEN applying preview stats_delta action")

  expect_equal(result, "snapshot heat changed", snapshot.heat, state.stats.heat + 2)
  expect_equal(result, "snapshot soil changed", snapshot.soil, state.stats.soil - 1)
  expect_equal(result, "live state heat unchanged", state.stats.heat, before_heat)
  return result
end

local function run_preview_install_industry_scenario()
  local result = make_result()
  local state = ScenarioCases.new_state()
  local snapshot = {
    heat = state.stats.heat,
    air = state.stats.air,
    water = state.stats.water,
    soil = state.stats.soil
  }
  local economy = state:get_economy_snapshot()
  local industry_card = CardTypes.createCardData("hydroponics_array")

  add_log(result, "GIVEN preview economy starts with open industry slots")
  ActionApplier.apply_action_preview(state, snapshot, economy, {
    type = "card",
    card = industry_card
  })
  add_log(result, "WHEN applying install-industry card in preview mode")

  expect_equal(result, "preview economy slot 1 filled", economy.industries[1] and economy.industries[1].id, "hydroponics_array")
  expect_equal(result, "live state slot 1 still empty", state.industries[1], nil)
  for _, key in ipairs(STATS) do
    expect_equal(result, "preview install does not alter stat " .. key, snapshot[key], state.stats[key])
  end
  return result
end

local function run_live_card_action_scenario()
  local result = make_result()
  local state = ScenarioCases.new_state({
    starting_stats = { heat = -2, air = -5, water = -3, soil = -1 }
  })
  local before_air = state.stats.air
  local before_heat = state.stats.heat
  local card = CardTypes.createCardData("air_up")

  add_log(result, "GIVEN live state and card Atmo Seeding (air +2)")
  ActionApplier.apply_action_live(state, {
    type = "card",
    card = card
  })
  add_log(result, "WHEN applying live card action")

  expect_equal(result, "air moved by +2", state.stats.air, before_air + 2)
  expect_equal(result, "heat unchanged", state.stats.heat, before_heat)
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

function ActionApplierSpec.run()
  local scenarios = {
    { name = "Preview stats_delta mutates snapshot only", fn = run_preview_stats_delta_scenario },
    { name = "Preview install-industry mutates preview economy only", fn = run_preview_install_industry_scenario },
    { name = "Live card action mutates state", fn = run_live_card_action_scenario }
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

return ActionApplierSpec
