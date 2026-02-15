local ScenarioCases = require("tests.scenario_cases")
local ForecastSystem = require("systems.forecast_system")
local TurnResolver = require("systems.turn_resolver")
local CardTypes = require("card_types")

local ForecastTraceSpec = {}

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

local function sum_edges_by_target(edge_map)
  local totals = { heat = 0, air = 0, water = 0, soil = 0 }
  for key, value in pairs(edge_map or {}) do
    local target = key:match(".+%-%>(.+)")
    if target then
      totals[target] = (totals[target] or 0) + value
    end
  end
  return totals
end

local function run_trace_conservation_scenario()
  local result = make_result()
  local state = ScenarioCases.new_state({
    magnetosphere_level = 1,
    hazard_strength = 2
  })

  add_log(
    result,
    string.format(
      "GIVEN state Heat %s Air %s Water %s Soil %s, hazard strength %d, magnetosphere L%d",
      format_signed(state.stats.heat),
      format_signed(state.stats.air),
      format_signed(state.stats.water),
      format_signed(state.stats.soil),
      state.hazard_strength,
      state.magnetosphere_level
    )
  )

  local summary = state:forecast_end_turn(state.stats, {
    economy_state = state:get_economy_snapshot()
  })

  add_log(
    result,
    "WHEN do-nothing forecast runs with raw hazard " .. tostring(summary.hazard) ..
      " => " .. tostring(summary.hazard_category or "Hazard")
  )

  expect_equal(result, "trace has start_stats", type(summary.start_stats), "table")
  expect_equal(result, "trace has post_hazard_stats", type(summary.post_hazard_stats), "table")
  expect_equal(result, "trace has coupling_input_stats", type(summary.coupling_input_stats), "table")
  expect_equal(result, "trace has coupling_edge_deltas", type(summary.coupling_edge_deltas), "table")
  expect_equal(result, "trace has coupling_target_deltas_raw", type(summary.coupling_target_deltas_raw), "table")
  expect_equal(result, "trace has coupling_target_deltas_applied", type(summary.coupling_target_deltas_applied), "table")

  local edge_totals = sum_edges_by_target(summary.coupling_edge_deltas)
  for _, key in ipairs(STATS) do
    expect_equal(
      result,
      "edge sums match raw coupling for " .. key,
      edge_totals[key] or 0,
      (summary.coupling_target_deltas_raw and summary.coupling_target_deltas_raw[key]) or 0
    )
  end

  for _, key in ipairs(STATS) do
    local start_value = (summary.start_stats and summary.start_stats[key]) or 0
    local hazard_delta = (summary.hazard_deltas and summary.hazard_deltas[key]) or 0
    local coupling_delta = (summary.coupling_target_deltas_applied and summary.coupling_target_deltas_applied[key]) or 0
    local expected_projected = start_value + hazard_delta + coupling_delta
    local actual_projected = (summary.projected_stats and summary.projected_stats[key]) or 0
    expect_equal(
      result,
      key .. " conservation start + hazard + coupling = projected",
      actual_projected,
      expected_projected
    )
  end

  return result
end

local function run_capped_trace_scenario()
  local result = make_result()
  local state = ScenarioCases.new_state({
    cap_coupling_at_target = true,
    starting_stats = { heat = 0, air = -2, water = -1, soil = -4 },
    hazards = {
      {
        id = "none",
        name = "Calm Orbit",
        category = "Test",
        origin = "space",
        magnetosphere_blockable = true,
        deltas = {}
      }
    }
  })

  add_log(result, "GIVEN cap_coupling_at_target enabled and zero hazard deltas")
  local summary = state:forecast_end_turn(state.stats, {
    economy_state = state:get_economy_snapshot()
  })
  add_log(result, "WHEN forecast computes raw and applied coupling traces")

  expect_equal(result, "raw water coupling is +4", (summary.coupling_target_deltas_raw or {}).water or 0, 4)
  expect_equal(result, "applied water coupling is capped to +1", (summary.coupling_target_deltas_applied or {}).water or 0, 1)

  for _, key in ipairs(STATS) do
    local start_value = (summary.start_stats and summary.start_stats[key]) or 0
    local hazard_delta = (summary.hazard_deltas and summary.hazard_deltas[key]) or 0
    local coupling_delta = (summary.coupling_target_deltas_applied and summary.coupling_target_deltas_applied[key]) or 0
    expect_equal(
      result,
      key .. " projected matches trace with cap",
      (summary.projected_stats and summary.projected_stats[key]) or 0,
      start_value + hazard_delta + coupling_delta
    )
  end

  return result
end

local function run_forecast_turn_parity_scenario()
  local result = make_result()
  local config = ScenarioCases.spec_config({
    magnetosphere_level = 1,
    hazard_strength = 1,
    starting_stats = { heat = -2, air = -5, water = -3, soil = -1 }
  })

  local card = CardTypes.createCardData("water_down")
  add_log(result, "GIVEN a selected card action: Drain Basins (water -2)")

  local state_for_preview = ScenarioCases.new_state_from_config(config)
  local preview = ForecastSystem.preview({ terraforming_state = state_for_preview }, {
    type = "card",
    card = card
  })

  local state_for_turn = ScenarioCases.new_state_from_config(config)
  local _, report = TurnResolver.resolve_end_turn({ terraforming_state = state_for_turn }, {
    type = "card",
    card = card
  })

  add_log(result, "WHEN comparing preview output to real end-turn resolution")

  for _, key in ipairs(STATS) do
    expect_equal(
      result,
      "preview parity for " .. key,
      (preview.projected_stats and preview.projected_stats[key]) or 0,
      (report.projected_stats and report.projected_stats[key]) or 0
    )
  end

  expect_equal(result, "preview parity net", preview.net, report.net)
  expect_equal(result, "preview parity population", preview.projected_population, report.projected_population)
  expect_equal(result, "preview parity profit", preview.projected_profit, report.projected_profit)
  expect_equal(result, "preview parity hazard", preview.hazard_id, report.hazard_id)

  return result
end

local function run_magnetosphere_bypass_scenario()
  local result = make_result()
  local state = ScenarioCases.new_state({
    magnetosphere_level = 4,
    hazards = {
      {
        id = "dry_front_test",
        name = "Dry Front",
        category = "Hydrologic Shift",
        origin = "climate",
        magnetosphere_blockable = false,
        deltas = { water = -2, soil = -1 }
      }
    }
  })

  add_log(result, "GIVEN a non-space hazard that bypasses magnetosphere with L4 active")
  local summary = state:forecast_end_turn(state.stats, { economy_state = state:get_economy_snapshot() })
  add_log(result, "WHEN forecast applies hazard projection")

  expect_equal(result, "hazard marked non-blockable", summary.hazard_blockable, false)
  expect_equal(
    result,
    "effective water delta equals raw water delta",
    (summary.hazard_effective_deltas or {}).water or 0,
    (summary.hazard_raw_deltas or {}).water or 0
  )
  expect_equal(
    result,
    "effective soil delta equals raw soil delta",
    (summary.hazard_effective_deltas or {}).soil or 0,
    (summary.hazard_raw_deltas or {}).soil or 0
  )
  expect_equal(result, "blocked water is zero", (summary.hazard_blocked_deltas or {}).water or 0, 0)
  expect_equal(result, "blocked soil is zero", (summary.hazard_blocked_deltas or {}).soil or 0, 0)

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

function ForecastTraceSpec.run()
  local scenarios = {
    { name = "Forecast Trace Conservation", fn = run_trace_conservation_scenario },
    { name = "Forecast Trace With Coupling Cap", fn = run_capped_trace_scenario },
    { name = "Preview vs Turn Resolver Parity", fn = run_forecast_turn_parity_scenario },
    { name = "Magnetosphere Bypass Hazard", fn = run_magnetosphere_bypass_scenario }
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

return ForecastTraceSpec
