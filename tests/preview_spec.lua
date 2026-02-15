local ScenarioCases = require("tests.scenario_cases")
local PreviewContextSystem = require("systems.preview_context_system")
local CouplingRules = require("content.coupling_rules")

local PreviewSpec = {}

local STATS = { "heat", "air", "water", "soil" }

local function format_signed(value)
  if value > 0 then
    return "+" .. tostring(value)
  end
  return tostring(value)
end

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

local function expect_stat_table_equal(result, label, actual, expected)
  for _, key in ipairs(STATS) do
    expect_equal(result, label .. " " .. key, (actual and actual[key]) or 0, (expected and expected[key]) or 0)
  end
end

local function expect_edge_table_equal(result, label, actual, expected)
  for _, edge in ipairs(CouplingRules.edges) do
    local key = edge.source .. "->" .. edge.target
    expect_equal(result, label .. " " .. key, (actual and actual[key]) or 0, (expected and expected[key]) or 0)
  end
end

local function run_current_mode_contract()
  local result = make_result()
  local state = ScenarioCases.new_state()
  local hand = ScenarioCases.make_hand({ "water_down", "heat_up" })

  add_log(result, "GIVEN preview mode Current with a hand containing two cards")
  local ctx = PreviewContextSystem.build(state, hand, nil, "current", function() return true end)
  local _, expected_edges = state:compute_coupling(state.stats)

  add_log(result, "WHEN building preview context in current mode")
  expect_equal(result, "active mode is current", ctx.active_mode, "current")
  expect_stat_table_equal(result, "active snapshot matches live stats", ctx.active_snapshot, state.stats)
  expect_edge_table_equal(result, "active edges match coupling on live stats", ctx.active_edge_deltas, expected_edges)
  return result
end

local function run_do_nothing_contract()
  local result = make_result()
  local state = ScenarioCases.new_state()
  local hand = ScenarioCases.make_hand({ "water_down" })

  add_log(result, "GIVEN preview mode Do Nothing")
  local ctx = PreviewContextSystem.build(state, hand, nil, "do_nothing", function() return true end)

  add_log(result, "WHEN building do-nothing context")
  expect_equal(result, "active mode is do_nothing", ctx.active_mode, "do_nothing")
  expect_stat_table_equal(result, "active snapshot equals baseline projected stats", ctx.active_snapshot, ctx.baseline.projected_stats)
  expect_edge_table_equal(result, "active edges equal baseline forecast coupling edges", ctx.active_edge_deltas, ctx.baseline.coupling_edge_deltas)
  return result
end

local function run_selected_contract()
  local result = make_result()
  local state = ScenarioCases.new_state({
    starting_stats = { heat = -2, air = -5, water = -3, soil = -1 }
  })
  local hand = ScenarioCases.make_hand({ "water_down", "heat_up" })

  add_log(result, "GIVEN selected preview with Drain Basins")
  local ctx = PreviewContextSystem.build(state, hand, 1, "selected", function() return true end)

  add_log(result, "WHEN selected-card preview is built")
  expect_equal(result, "active mode is selected", ctx.active_mode, "selected")
  expect_equal(result, "scenario exists", type(ctx.scenario), "table")

  expect_stat_table_equal(
    result,
    "selected active snapshot equals selected summary projected stats",
    ctx.active_snapshot,
    ctx.scenario and ctx.scenario.summary and ctx.scenario.summary.projected_stats or {}
  )
  expect_edge_table_equal(
    result,
    "selected active edges equal selected summary coupling edges",
    ctx.active_edge_deltas,
    ctx.scenario and ctx.scenario.summary and ctx.scenario.summary.coupling_edge_deltas or {}
  )

  expect_equal(
    result,
    "card push snapshot water includes immediate card delta",
    (ctx.card_push_snapshot and ctx.card_push_snapshot.water) or 0,
    state.stats.water - 2
  )
  expect_equal(
    result,
    "card push snapshot heat unchanged",
    (ctx.card_push_snapshot and ctx.card_push_snapshot.heat) or 0,
    state.stats.heat
  )
  return result
end

local function run_selected_fallback_contract()
  local result = make_result()
  local state = ScenarioCases.new_state()
  local hand = ScenarioCases.make_hand({ "water_down" })

  add_log(result, "GIVEN selected mode with invalid card index")
  local ctx = PreviewContextSystem.build(state, hand, 99, "selected", function() return true end)
  add_log(result, "WHEN preview context resolves mode fallback")

  expect_equal(result, "falls back to do_nothing", ctx.active_mode, "do_nothing")
  expect_equal(result, "scenario is nil", ctx.scenario, nil)
  expect_stat_table_equal(result, "fallback snapshot uses baseline projection", ctx.active_snapshot, ctx.baseline.projected_stats)
  return result
end

local function run_user_regression_explanation_scenario()
  local result = make_result()
  local state = ScenarioCases.new_state({
    starting_stats = { heat = -2, air = -5, water = -3, soil = -1 },
    magnetosphere_level = 3
  })
  local hand = ScenarioCases.make_hand({ "water_down" })

  add_log(result, "GIVEN live Air is -5 and selected card is Drain Basins (water -2)")
  local current_ctx = PreviewContextSystem.build(state, hand, nil, "current", function() return true end)
  local selected_ctx = PreviewContextSystem.build(state, hand, 1, "selected", function() return true end)
  add_log(result, "WHEN comparing Current vs Selected Card end-turn projections")

  local summary = selected_ctx.scenario and selected_ctx.scenario.summary or {}
  local current_air = state.stats.air or 0
  local card_delta_air = ((summary.start_stats and summary.start_stats.air) or current_air) - current_air
  local hazard_delta_air = (summary.hazard_deltas and summary.hazard_deltas.air) or 0
  local coupling_delta_air = (summary.coupling_target_deltas_applied and summary.coupling_target_deltas_applied.air) or 0
  local expected_air = current_air + card_delta_air + hazard_delta_air + coupling_delta_air
  local projected_air = (summary.projected_stats and summary.projected_stats.air) or current_air

  add_log(
    result,
    "THEN Air equation: " .. format_signed(current_air) ..
      " + card " .. format_signed(card_delta_air) ..
      " + hazard " .. format_signed(hazard_delta_air) ..
      " + coupling " .. format_signed(coupling_delta_air) ..
      " = " .. format_signed(projected_air)
  )
  expect_equal(result, "air projection follows explicit equation", projected_air, expected_air)

  expect_equal(
    result,
    "selected context edges come from selected summary trace",
    (selected_ctx.active_edge_deltas and selected_ctx.active_edge_deltas["water->air"]) or 0,
    (summary.coupling_edge_deltas and summary.coupling_edge_deltas["water->air"]) or 0
  )
  expect_equal(
    result,
    "current context remains tied to live stats",
    (current_ctx.active_snapshot and current_ctx.active_snapshot.air) or 0,
    state.stats.air
  )

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

function PreviewSpec.run()
  local scenarios = {
    { name = "Current Mode Contract", fn = run_current_mode_contract },
    { name = "Do Nothing Mode Contract", fn = run_do_nothing_contract },
    { name = "Selected Card Mode + Card Push Contract", fn = run_selected_contract },
    { name = "Selected Mode Invalid Index Fallback", fn = run_selected_fallback_contract },
    { name = "User Regression Equation Trace (Air Drift)", fn = run_user_regression_explanation_scenario }
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

return PreviewSpec
