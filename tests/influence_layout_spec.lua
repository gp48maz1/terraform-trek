local InfluenceLayout = require("ui.layout.influence_layout")

local InfluenceLayoutSpec = {}

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

local function run_compute_contract()
  local result = make_result()
  local safe = { x = 96, y = 20, w = 1536, h = 758 }

  add_log(result, "GIVEN a mobile safe rect")
  local layout = InfluenceLayout.compute(safe)
  add_log(result, "WHEN computing influence layout panels and nodes")

  expect_equal(result, "hazard x anchors to safe left", layout.hazard_rect.x, safe.x)
  expect_equal(result, "hazard y offset", layout.hazard_rect.y, safe.y + 44)
  expect_equal(result, "hazard width ratio floor", layout.hazard_rect.w, math.max(220, math.floor(safe.w * 0.18)))

  local expected_cards_h = math.max(150, math.min(170, math.floor(safe.h * 0.20)))
  expect_equal(result, "cards fixed compact height", layout.cards_rect.h, expected_cards_h)
  expect_equal(result, "cards pinned to safe bottom", layout.cards_rect.y, safe.y + safe.h - expected_cards_h)

  local expected_top_h = layout.cards_rect.y - layout.hazard_rect.y - 12
  expect_equal(result, "hazard and top panels share computed top height", layout.hazard_rect.h, expected_top_h)
  expect_equal(result, "map panel shares top height", layout.map_rect.h, expected_top_h)

  local expected_map_x = layout.hazard_rect.x + layout.hazard_rect.w + 14
  expect_equal(result, "map x follows hazard + gap", layout.map_rect.x, expected_map_x)
  expect_equal(result, "map y offset", layout.map_rect.y, safe.y + 44)
  expect_equal(result, "map width uses remainder split", layout.map_rect.w, safe.w - layout.hazard_rect.w - layout.objectives_rect.w - 28)

  local right_x = layout.map_rect.x + layout.map_rect.w + 14
  expect_equal(result, "objectives x follows map + gap", layout.objectives_rect.x, right_x)
  expect_equal(result, "objectives width fills remaining space", layout.objectives_rect.w, safe.x + safe.w - right_x)
  expect_equal(result, "cards span full safe width", layout.cards_rect.w, safe.w)

  expect_equal(result, "graph rect is inset inside map panel", layout.map_graph_rect.x, layout.map_rect.x + 14)
  expect_equal(result, "graph rect y offset", layout.map_graph_rect.y, layout.map_rect.y + 118)
  expect_equal(result, "graph rect width inset", layout.map_graph_rect.w, layout.map_rect.w - 28)
  expect_equal(result, "graph rect height reserves footer", layout.map_graph_rect.h, layout.map_rect.h - 162)

  expect_equal(result, "hazard card width cap", layout.hazard_card_rect.w, math.min(layout.hazard_rect.w - 20, 236))
  local expected_hazard_card_h = math.max(190, math.min(layout.hazard_rect.h - 62, 266))
  local expected_hazard_card_y = layout.hazard_rect.y + 42
  local expected_hazard_bottom = layout.hazard_rect.y + layout.hazard_rect.h - 10
  if expected_hazard_card_y + expected_hazard_card_h > expected_hazard_bottom then
    expected_hazard_card_h = math.max(160, expected_hazard_bottom - expected_hazard_card_y)
  end
  expect_equal(result, "hazard card height cap", layout.hazard_card_rect.h, expected_hazard_card_h)

  expect_equal(result, "heat and soil share x", layout.nodes.heat.x, layout.nodes.soil.x)
  expect_equal(result, "air and water share y", layout.nodes.air.y, layout.nodes.water.y)
  expect_equal(result, "all nodes share radius", layout.nodes.heat.r, layout.nodes.air.r)
  expect_equal(result, "magnetosphere center x aligns with node axis", layout.magnetosphere.x, layout.nodes.heat.x)
  expect_equal(result, "magnetosphere center y aligns with node axis", layout.magnetosphere.y, layout.nodes.air.y)
  return result
end

local function run_controls_contract()
  local result = make_result()
  local layout = InfluenceLayout.compute({ x = 0, y = 0, w = 1728, h = 798 })

  add_log(result, "GIVEN computed influence layout")
  local toggles = InfluenceLayout.get_map_toggle_buttons(layout)
  local mode_buttons = InfluenceLayout.get_forecast_mode_buttons(layout.turn_explain_rect)
  local help_button = InfluenceLayout.get_help_button(layout)
  local preview_button = InfluenceLayout.get_preview_explain_button(layout)
  local objectives_button = InfluenceLayout.get_objectives_explain_button(layout)
  add_log(result, "WHEN resolving button geometry")

  expect_equal(result, "map filter button width", toggles.filter.w, 198)
  expect_equal(result, "map explain button width", toggles.explain_graph.w, 154)
  expect_equal(result, "single forecast mode button currently available", #mode_buttons, 1)
  expect_equal(result, "forecast button id", mode_buttons[1].id, "current")
  expect_equal(result, "help button width", help_button.w, 24)
  expect_equal(result, "help button is left of preview explain", help_button.x, layout.cards_rect.x + 12)
  expect_equal(result, "preview explain button width", preview_button.w, 176)
  expect_equal(result, "preview explain button shifted for help icon", preview_button.x, layout.cards_rect.x + 44)
  expect_equal(result, "objectives explain button width", objectives_button.w, 188)
  expect_equal(result, "graph explain button remains in map footer", toggles.explain_graph.y, layout.map_rect.y + layout.map_rect.h - 34)
  return result
end

local function run_card_rects_contract()
  local result = make_result()
  local layout = InfluenceLayout.compute({ x = 0, y = 0, w = 1728, h = 798 })
  local hand = {
    { name = "Card A" },
    { name = "Card B" },
    { name = "Card C" },
    { name = "Card D" },
    { name = "Card E" }
  }

  add_log(result, "GIVEN five hand cards for influence preview selector")
  local card_rects = InfluenceLayout.get_card_rects(layout, hand)
  add_log(result, "WHEN generating card rect options")

  expect_equal(result, "do-nothing + five cards", #card_rects, 6)
  expect_equal(result, "first option is do-nothing", card_rects[1].option.kind, "do_nothing")
  expect_equal(result, "second option is first hand card", card_rects[2].option.card_index, 1)
  expect_equal(result, "last option is fifth hand card", card_rects[6].option.card_index, 5)
  expect_equal(result, "card width preserved", card_rects[1].w, 166)
  expect_equal(result, "card height preserved", card_rects[1].h, 56)
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

function InfluenceLayoutSpec.run()
  local scenarios = {
    { name = "Influence Panel Compute Contract", fn = run_compute_contract },
    { name = "Influence Button Geometry Contract", fn = run_controls_contract },
    { name = "Influence Card Rects Contract", fn = run_card_rects_contract }
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

return InfluenceLayoutSpec
