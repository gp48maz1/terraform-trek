local GameplayLayout = require("ui.layout.gameplay_layout")

local GameplayLayoutSpec = {}

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

local function expect_near(result, label, actual, expected, epsilon)
  local gap = math.abs((actual or 0) - expected)
  local ok = gap <= (epsilon or 0.0001)
  local status = ok and "PASS" or "FAIL"
  add_log(
    result,
    string.format("THEN %s: %s (expected %.4f, got %.4f, |delta|=%.6f)", status, label, expected, actual or 0, gap)
  )
  if not ok then
    result.failed = result.failed + 1
  end
end

local function run_baseline_geometry_contract()
  local result = make_result()
  local safe = { x = 96, y = 20, w = 1536, h = 758 }
  local hand_ui = { card_width = 150, card_height = 225, card_spacing = 175 }
  local pile_ui = { width = 90, height = 120 }
  local end_turn_ui = { width = 170, height = 50 }

  add_log(result, "GIVEN baseline mobile safe rect and gameplay UI constants")
  local planet = GameplayLayout.get_planet(safe)
  local hand = GameplayLayout.get_hand_layout(safe, 5, hand_ui)
  local deck = GameplayLayout.get_deck_rect(safe, pile_ui)
  local discard = GameplayLayout.get_discard_rect(safe, pile_ui)
  local end_turn = GameplayLayout.get_end_turn_rect(safe, hand, hand_ui, end_turn_ui, pile_ui)
  local hazard = GameplayLayout.get_hazard_card_rect(safe, planet)
  add_log(result, "WHEN computing gameplay positions")

  expect_near(result, "planet x", planet.x, safe.x + (safe.w * 0.72))
  expect_near(result, "planet y", planet.y, safe.y + (safe.h * 0.34))
  expect_equal(result, "planet radius", planet.radius, math.floor(math.min(safe.w, safe.h) * 0.28))

  expect_near(result, "hand start x", hand.start_x, 439.0)
  expect_near(result, "hand base y", hand.base_y, 529.0)

  expect_equal(result, "deck x", deck.x, 112)
  expect_equal(result, "deck y", deck.y, 646)
  expect_equal(result, "discard x", discard.x, 1526)
  expect_equal(result, "discard y", discard.y, 646)
  expect_equal(result, "end turn x", end_turn.x, 1448)
  expect_equal(result, "end turn y", end_turn.y, 582)
  expect_equal(result, "end turn sits above discard", end_turn.y + end_turn.h < discard.y, true)

  expect_near(result, "hazard x", hazard.x, 795.92, 0.001)
  expect_near(result, "hazard y", hazard.y, 193.72, 0.001)
  expect_equal(result, "hazard width", hazard.w, 170)
  expect_equal(result, "hazard height", hazard.h, 236)
  return result
end

local function run_hazard_clamp_contract()
  local result = make_result()
  local safe = { x = 0, y = 0, w = 420, h = 260 }
  local planet = { x = 120, y = 230, radius = 100 }

  add_log(result, "GIVEN a small safe rect where incoming hazard card would overflow")
  local hazard = GameplayLayout.get_hazard_card_rect(safe, planet)
  add_log(result, "WHEN hazard rect is clamped inside safe bounds")

  expect_equal(result, "hazard x clamps to min inset", hazard.x, 16)
  expect_equal(result, "hazard y clamps to max inset", hazard.y, 8)
  expect_equal(result, "hazard width fixed", hazard.w, 170)
  expect_equal(result, "hazard height fixed", hazard.h, 236)
  return result
end

local function run_compute_parity_contract()
  local result = make_result()
  local safe = { x = 96, y = 20, w = 1536, h = 758 }
  local ui_state = {
    hand_count = 5,
    hand_ui = { card_width = 150, card_height = 225, card_spacing = 175 },
    pile_ui = { width = 90, height = 120 },
    end_turn_ui = { width = 170, height = 50 }
  }

  add_log(result, "GIVEN full gameplay layout compute inputs")
  local combined = GameplayLayout.compute(safe, ui_state)
  local planet = GameplayLayout.get_planet(safe)
  local hand = GameplayLayout.get_hand_layout(safe, ui_state.hand_count, ui_state.hand_ui)
  local deck = GameplayLayout.get_deck_rect(safe, ui_state.pile_ui)
  local discard = GameplayLayout.get_discard_rect(safe, ui_state.pile_ui)
  local end_turn = GameplayLayout.get_end_turn_rect(safe, hand, ui_state.hand_ui, ui_state.end_turn_ui, ui_state.pile_ui)
  local hazard = GameplayLayout.get_hazard_card_rect(safe, planet)
  add_log(result, "WHEN comparing compute output to helper outputs")

  expect_near(result, "compute planet x parity", combined.planet.x, planet.x)
  expect_near(result, "compute hand start x parity", combined.hand.start_x, hand.start_x)
  expect_equal(result, "compute deck x parity", combined.deck.x, deck.x)
  expect_equal(result, "compute discard x parity", combined.discard.x, discard.x)
  expect_equal(result, "compute end-turn y parity", combined.end_turn.y, end_turn.y)
  expect_near(result, "compute hazard x parity", combined.incoming_hazard.x, hazard.x, 0.001)
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

function GameplayLayoutSpec.run()
  local scenarios = {
    { name = "Gameplay Baseline Geometry Contract", fn = run_baseline_geometry_contract },
    { name = "Gameplay Hazard Clamp Contract", fn = run_hazard_clamp_contract },
    { name = "Gameplay Compute Helper Parity Contract", fn = run_compute_parity_contract }
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

return GameplayLayoutSpec
