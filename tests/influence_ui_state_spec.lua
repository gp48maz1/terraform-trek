local InfluenceUIState = require("app.influence_ui_state")

local InfluenceUIStateSpec = {}

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

local function run_default_state_contract()
  local result = make_result()
  local state = InfluenceUIState.new()

  add_log(result, "GIVEN a new influence UI state")
  add_log(result, "WHEN defaults are inspected")
  expect_equal(result, "focused stat defaults to heat", state.focused_stat, "heat")
  expect_equal(result, "forecast mode defaults to current", state.forecast_mode, "current")
  expect_equal(result, "selection starts empty", state.selected_forecast_card_index, nil)
  expect_equal(result, "edge filter defaults to focused_both", state.edge_filter_mode, "focused_both")
  expect_equal(result, "graph explain starts hidden", state.show_graph_explain, false)
  expect_equal(result, "turn explain starts hidden", state.show_turn_explain, false)
  expect_equal(result, "objectives explain starts hidden", state.show_objectives_explain, false)
  expect_equal(result, "help tooltip starts hidden", state.show_help_tooltip, false)
  return result
end

local function run_mode_selection_contract()
  local result = make_result()
  local state = InfluenceUIState.new()

  add_log(result, "GIVEN mode transitions between current/do-nothing/selected")
  state:set_selected_mode(3)
  expect_equal(result, "selected mode enables selected forecast", state.forecast_mode, "selected")
  expect_equal(result, "selected card index is stored", state.selected_forecast_card_index, 3)

  state:set_do_nothing_mode(false)
  expect_equal(result, "do nothing mode is active", state.forecast_mode, "do_nothing")
  expect_equal(result, "selection is retained when not clearing", state.selected_forecast_card_index, 3)

  state:set_selected_or_do_nothing_mode()
  expect_equal(result, "selected-or-do-nothing returns selected when card exists", state.forecast_mode, "selected")

  state:set_do_nothing_mode(true)
  expect_equal(result, "clear-on-do-nothing clears selection", state.selected_forecast_card_index, nil)
  expect_equal(result, "mode remains do_nothing after clear", state.forecast_mode, "do_nothing")

  state:set_selected_or_do_nothing_mode()
  expect_equal(result, "selected-or-do-nothing falls back to do_nothing", state.forecast_mode, "do_nothing")

  state:set_current_mode()
  expect_equal(result, "set_current_mode clears selection", state.selected_forecast_card_index, nil)
  expect_equal(result, "set_current_mode sets current", state.forecast_mode, "current")
  return result
end

local function run_selection_sanitize_contract()
  local result = make_result()
  local state = InfluenceUIState.new()

  add_log(result, "GIVEN selected card points outside current hand size")
  state:set_selected_mode(5)
  state:sanitize_selection(2)

  add_log(result, "WHEN sanitizing with hand size 2")
  expect_equal(result, "invalid selected index is cleared", state.selected_forecast_card_index, nil)
  expect_equal(result, "selected mode degrades to current", state.forecast_mode, "current")
  return result
end

local function run_explain_toggle_contract()
  local result = make_result()
  local state = InfluenceUIState.new()

  add_log(result, "GIVEN explain overlays are mutually exclusive for graph vs turn")
  state:toggle_graph_explain()
  expect_equal(result, "graph explain toggles on", state.show_graph_explain, true)
  expect_equal(result, "turn explain remains off", state.show_turn_explain, false)

  state:toggle_turn_explain()
  expect_equal(result, "turn explain toggles on", state.show_turn_explain, true)
  expect_equal(result, "graph explain is forced off", state.show_graph_explain, false)

  state:toggle_objectives_explain()
  expect_equal(result, "objectives explain toggles on independently", state.show_objectives_explain, true)
  state:toggle_objectives_explain()
  expect_equal(result, "objectives explain toggles off", state.show_objectives_explain, false)

  state:toggle_help_tooltip()
  expect_equal(result, "help tooltip toggles on", state.show_help_tooltip, true)
  state:toggle_help_tooltip()
  expect_equal(result, "help tooltip toggles off", state.show_help_tooltip, false)
  return result
end

local function run_edge_filter_contract()
  local result = make_result()
  local state = InfluenceUIState.new()
  local edge_heat_to_water = { source = "heat", target = "water" }
  local edge_water_to_air = { source = "water", target = "air" }

  add_log(result, "GIVEN focused stat is heat and edge filter cycles")
  expect_equal(result, "default label is in + out", state:get_edge_filter_label(), "In + Out")
  expect_equal(result, "focused_both shows heat outgoing edge", state:edge_is_visible(edge_heat_to_water), true)
  expect_equal(result, "focused_both hides unrelated edge", state:edge_is_visible(edge_water_to_air), false)

  state:cycle_edge_filter_mode()
  expect_equal(result, "first cycle is incoming", state.edge_filter_mode, "focused_incoming")
  expect_equal(result, "incoming hides heat outgoing edge", state:edge_is_visible(edge_heat_to_water), false)

  state:cycle_edge_filter_mode()
  expect_equal(result, "second cycle is outgoing", state.edge_filter_mode, "focused_outgoing")
  expect_equal(result, "outgoing shows heat outgoing edge", state:edge_is_visible(edge_heat_to_water), true)

  state:cycle_edge_filter_mode()
  expect_equal(result, "third cycle is all", state.edge_filter_mode, "all")
  expect_equal(result, "all shows unrelated edge", state:edge_is_visible(edge_water_to_air), true)

  state:cycle_edge_filter_mode()
  expect_equal(result, "fourth cycle loops back to focused_both", state.edge_filter_mode, "focused_both")
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

function InfluenceUIStateSpec.run()
  local scenarios = {
    { name = "Default State Contract", fn = run_default_state_contract },
    { name = "Mode Selection Contract", fn = run_mode_selection_contract },
    { name = "Selection Sanitize Contract", fn = run_selection_sanitize_contract },
    { name = "Explain Toggle Contract", fn = run_explain_toggle_contract },
    { name = "Edge Filter Contract", fn = run_edge_filter_contract }
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

return InfluenceUIStateSpec
