local TerraformingState = require("terraforming_state")
local CouplingRules = require("content.coupling_rules")

local MathSuite = {}

local STATS = { "heat", "air", "water", "soil" }

local function assert_equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s expected %s got %s", label, tostring(expected), tostring(actual)), 2)
  end
end

local function assert_truthy(value, label)
  if not value then
    error(label .. " expected truthy value", 2)
  end
end

local function new_state(config)
  local options = {
    targets = { heat = 0, air = 0, water = 0, soil = 0 },
    starting_stats = { heat = 0, air = 0, water = 0, soil = 0 },
    hazards = {
      {
        id = "test_none",
        name = "Test None",
        origin = "space",
        magnetosphere_blockable = true,
        deltas = {}
      }
    }
  }

  for key, value in pairs(config or {}) do
    options[key] = value
  end

  return TerraformingState.new(options)
end

local function collect_edge_map(state, snapshot)
  local edge_map = {}
  for _, edge in ipairs(CouplingRules.edges) do
    local key = edge.source .. "->" .. edge.target
    edge_map[key] = state:get_coupling_delta_for_edge(edge.source, edge.factor, snapshot, edge.target)
  end
  return edge_map
end

local function sum_edges_to_targets(edge_map)
  local totals = { heat = 0, air = 0, water = 0, soil = 0 }
  for key, delta in pairs(edge_map) do
    local target = key:match(".+%-%>(.+)")
    totals[target] = (totals[target] or 0) + delta
  end
  return totals
end

local function test_signal_mapping_and_symmetry()
  local state = new_state()
  local cases = {
    { value = 0, expected = 3 },
    { value = 1, expected = 2 },
    { value = 2, expected = 1 },
    { value = 3, expected = 0 },
    { value = 4, expected = 0 },
    { value = 5, expected = 0 },
    { value = 6, expected = -1 },
    { value = 7, expected = -2 },
    { value = 8, expected = -3 },
    { value = 9, expected = -4 },
    { value = 10, expected = -5 },
    { value = 14, expected = -5 }
  }

  for _, stat_key in ipairs(STATS) do
    for _, case in ipairs(cases) do
      local snapshot = { heat = 0, air = 0, water = 0, soil = 0 }
      snapshot[stat_key] = case.value
      assert_equal(
        state:get_source_coupling_signal(stat_key, snapshot),
        case.expected,
        stat_key .. " signal at +" .. tostring(case.value)
      )

      snapshot[stat_key] = -case.value
      assert_equal(
        state:get_source_coupling_signal(stat_key, snapshot),
        case.expected,
        stat_key .. " signal symmetry at -" .. tostring(case.value)
      )
    end
  end
end

local function test_equal_distance_edges_match_expected()
  local state = new_state()
  local snapshot = { heat = -2, air = -2, water = -2, soil = -2 }

  assert_equal(state:get_coupling_delta_for_edge("heat", 1, snapshot, "water"), 1, "heat->water")
  assert_equal(state:get_coupling_delta_for_edge("heat", 1, snapshot, "soil"), 1, "heat->soil")
  assert_equal(state:get_coupling_delta_for_edge("air", 1, snapshot, "heat"), 1, "air->heat")
  assert_equal(state:get_coupling_delta_for_edge("air", 1, snapshot, "water"), 1, "air->water")
  assert_equal(state:get_coupling_delta_for_edge("water", 1, snapshot, "soil"), 1, "water->soil")
  assert_equal(state:get_coupling_delta_for_edge("water", 1, snapshot, "air"), 1, "water->air")
  assert_equal(state:get_coupling_delta_for_edge("soil", 1, snapshot, "air"), 1, "soil->air")
end

local function test_user_reported_case_no_order_cap_side_effects()
  local state = new_state()
  local snapshot = { heat = 0, air = -2, water = -1, soil = -4 }

  -- The bug report case: both of these should be positive and non-zero.
  assert_equal(state:get_coupling_delta_for_edge("heat", 1, snapshot, "water"), 3, "heat 0 -> water")
  assert_equal(state:get_coupling_delta_for_edge("air", 1, snapshot, "water"), 1, "air -2 -> water")

  -- And same source signal should apply consistently to all outgoing edges.
  assert_equal(state:get_coupling_delta_for_edge("heat", 1, snapshot, "soil"), 3, "heat 0 -> soil")
end

local function test_stress_signal_direction()
  local state = new_state()
  local snapshot = { heat = 8, air = 0, water = 0, soil = -1 }

  assert_equal(state:get_coupling_delta_for_edge("heat", 1, snapshot, "water"), -3, "heat stress to water")
  assert_equal(state:get_coupling_delta_for_edge("heat", 1, snapshot, "soil"), -3, "heat stress to soil")
end

local function test_coupling_aggregation_consistency()
  local state = new_state()
  local snapshot = { heat = 0, air = -2, water = -1, soil = -4 }

  local edge_map = collect_edge_map(state, snapshot)
  local summed = sum_edges_to_targets(edge_map)
  local changes, edge_deltas = state:compute_coupling(snapshot)
  local build_only = state:build_coupling_changes(snapshot)

  for _, key in ipairs(STATS) do
    assert_equal(changes[key] or 0, summed[key] or 0, "compute_coupling sum " .. key)
    assert_equal(build_only[key] or 0, changes[key] or 0, "build_coupling " .. key)
  end

  for edge_key, value in pairs(edge_map) do
    assert_equal(edge_deltas[edge_key] or 0, value, "edge delta " .. edge_key)
  end
end

local function test_coupling_application_allows_crossing_zero_pre_clamp()
  local state = new_state({ starting_stats = { heat = 0, air = -2, water = -1, soil = -4 } })
  local before = { heat = state.stats.heat, air = state.stats.air, water = state.stats.water, soil = state.stats.soil }

  local changes = state:build_coupling_changes(state.stats)
  state:apply_stat_changes(changes)

  -- water receives +3 (from heat) +1 (from air) in this setup: -1 -> +3
  assert_equal(before.water, -1, "water baseline")
  assert_equal(changes.water, 4, "water aggregated coupling")
  assert_equal(state.stats.water, 3, "water crosses zero before any optional clamp")
end

local function test_optional_second_pass_cap_at_target()
  local state = new_state({
    cap_coupling_at_target = true,
    starting_stats = { heat = 0, air = -2, water = -1, soil = -4 }
  })

  local raw_changes = state:compute_coupling(state.stats)
  assert_equal(raw_changes.water, 4, "raw water coupling before cap")

  local capped = state:build_coupling_changes(state.stats)
  assert_equal(capped.water, 1, "second-pass cap limits water to target")
  assert_equal(capped.soil, 4, "soil remains uncapped when not crossing target")
end

local function test_stat_bounds_are_guidance_only()
  local uncapped = new_state()
  uncapped:apply_stat_changes({ heat = 25, water = -25, air = 12, soil = 13 })
  assert_truthy(uncapped.stats.heat > 10, "heat can exceed +10")
  assert_truthy(uncapped.stats.water < -10, "water can exceed -10")
  assert_truthy(uncapped.stats.air > 0, "air can exceed 0")
  assert_truthy(uncapped.stats.soil > 0, "soil can exceed 0")

  local capped = new_state({ enforce_stat_bounds = true })
  capped:apply_stat_changes({ heat = 25, water = -25, air = 12, soil = 13 })
  assert_equal(capped.stats.heat, 10, "heat capped when enabled")
  assert_equal(capped.stats.water, -10, "water capped when enabled")
  assert_equal(capped.stats.air, 0, "air capped when enabled")
  assert_equal(capped.stats.soil, 0, "soil capped when enabled")
end

local function test_magnetosphere_blocking_math()
  local state = new_state()
  local hazard = {
    id = "comet",
    name = "Comet Crash Landing",
    origin = "space",
    magnetosphere_blockable = true,
    deltas = { soil = -2, water = 2 }
  }

  local full_block = state:project_hazard(hazard, 1, 3)
  assert_equal(full_block.effective_deltas.soil or 0, 0, "mag3 blocks soil fully")
  assert_equal(full_block.effective_deltas.water or 0, 0, "mag3 blocks water fully")
  assert_equal(full_block.blocked_deltas.soil or 0, -2, "blocked soil amount")
  assert_equal(full_block.blocked_deltas.water or 0, 2, "blocked water amount")

  local partial = state:project_hazard(hazard, 1, 1)
  assert_equal(partial.effective_deltas.soil or 0, -1, "mag1 soil partial")
  assert_equal(partial.effective_deltas.water or 0, 1, "mag1 water partial")
end

local TESTS = {
  signal_mapping_and_symmetry = test_signal_mapping_and_symmetry,
  equal_distance_edges_match_expected = test_equal_distance_edges_match_expected,
  user_reported_case_no_order_cap_side_effects = test_user_reported_case_no_order_cap_side_effects,
  stress_signal_direction = test_stress_signal_direction,
  coupling_aggregation_consistency = test_coupling_aggregation_consistency,
  coupling_application_allows_crossing_zero_pre_clamp = test_coupling_application_allows_crossing_zero_pre_clamp,
  optional_second_pass_cap_at_target = test_optional_second_pass_cap_at_target,
  stat_bounds_are_guidance_only = test_stat_bounds_are_guidance_only,
  magnetosphere_blocking_math = test_magnetosphere_blocking_math
}

function MathSuite.run()
  local names = {}
  for name, _ in pairs(TESTS) do
    names[#names + 1] = name
  end
  table.sort(names)

  local passed = 0
  local failed = 0
  for _, name in ipairs(names) do
    local ok, err = pcall(TESTS[name])
    if ok then
      passed = passed + 1
      print("PASS", name)
    else
      failed = failed + 1
      print("FAIL", name)
      print("  " .. tostring(err))
    end
  end

  print(string.format("math suite: %d passed, %d failed", passed, failed))
  return passed, failed
end

return MathSuite
