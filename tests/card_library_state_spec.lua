local CardLibraryState = require("app.card_library_state")

local CardLibraryStateSpec = {}

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

local function make_stub_card_types()
  local defs = {
    a = {
      id = "a",
      name = "Stabilize Alpha",
      category = "Terraform",
      cost = 1,
      description = "stabilize",
      effect_fn_name = "stabilize_system",
      properties = {
        stat_changes = { heat = 1 }
      }
    },
    b = {
      id = "b",
      name = "Mine Beta",
      category = "Industry",
      cost = 1,
      description = "install industry",
      effect_fn_name = "install_industry",
      properties = {
        industry_def = { name = "Mine", base_profit = 2 }
      }
    },
    c = {
      id = "c",
      name = "Survey Gamma",
      category = "Chance",
      cost = 1,
      description = "draw",
      effect_fn_name = "draw_cards",
      properties = {
        draw_amount = 2
      }
    }
  }

  return {
    getAllCardIds = function()
      return { "c", "a", "b" }
    end,
    createCardData = function(id)
      local card = defs[id]
      if not card then
        return nil
      end
      local clone = {}
      for k, v in pairs(card) do
        clone[k] = v
      end
      return clone
    end
  }
end

local function make_stub_card_class()
  return {
    new = function(_, data)
      return {
        name = data.name,
        data = data
      }
    end
  }
end

local function run_initialize_contract()
  local result = make_result()
  local state = CardLibraryState.new()
  local card_types = make_stub_card_types()
  local card_class = make_stub_card_class()

  add_log(result, "GIVEN unsorted card ids and mixed categories")
  CardLibraryState.initialize(state, {
    card_types = card_types,
    card_class = card_class,
    stat_labels = {
      heat = "Heat",
      air = "Air",
      water = "Water",
      soil = "Soil"
    }
  })
  add_log(result, "WHEN card library state initializes")

  expect_equal(result, "cards are category-sorted first", state.cards[1].id, "a")
  expect_equal(result, "industry card is second", state.cards[2].id, "b")
  expect_equal(result, "chance card is third", state.cards[3].id, "c")
  expect_equal(result, "selected topic defaults to All", state.selected_topic, "All")
  expect_equal(result, "selected card defaults to first entry", state.selected_card_id, "a")
  expect_equal(result, "topics include Terraform", state.topics[2], "Terraform")
  expect_equal(result, "topics include Industry", state.topics[3], "Industry")
  expect_equal(result, "topics include Chance", state.topics[4], "Chance")
  expect_equal(result, "topics include Heat from stat change", state.topics[5], "Heat")
  return result
end

local function run_filter_selection_contract()
  local result = make_result()
  local state = CardLibraryState.new()
  CardLibraryState.initialize(state, {
    card_types = make_stub_card_types(),
    card_class = make_stub_card_class(),
    stat_labels = { heat = "Heat" }
  })

  add_log(result, "GIVEN topic selection and stale card selection")
  CardLibraryState.select_topic(state, "Industry")
  state.selected_card_id = "does-not-exist"
  local filtered = CardLibraryState.get_filtered_entries(state)
  CardLibraryState.ensure_selection(state, filtered)
  add_log(result, "WHEN filtering by Industry and ensuring selection")

  expect_equal(result, "one card remains in Industry filter", #filtered, 1)
  expect_equal(result, "selected card corrected to available card", state.selected_card_id, "b")
  expect_equal(result, "selected entry resolves from filtered list", CardLibraryState.get_selected_entry(state, filtered).id, "b")
  return result
end

local function run_scroll_and_cycle_contract()
  local result = make_result()
  local state = CardLibraryState.new()
  state.topics = { "All", "Terraform", "Industry" }
  state.selected_topic = "All"

  add_log(result, "GIVEN topic cycling and scroll clamp behavior")
  local left_topic = CardLibraryState.cycle_topic(state, -1)
  expect_equal(result, "left cycle wraps to last topic", left_topic, "Industry")
  local right_topic = CardLibraryState.cycle_topic(state, 1)
  expect_equal(result, "right cycle returns to first topic", right_topic, "All")

  CardLibraryState.set_max_scroll(state, 120)
  CardLibraryState.scroll_by(state, -10, 44)
  expect_equal(result, "scroll clamps to max", state.scroll_offset, 120)
  CardLibraryState.scroll_by(state, 10, 44)
  expect_equal(result, "scroll clamps to min", state.scroll_offset, 0)

  state.scroll_offset = 77
  CardLibraryState.select_topic(state, "Terraform")
  expect_equal(result, "topic selection resets scroll", state.scroll_offset, 0)
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

function CardLibraryStateSpec.run()
  local scenarios = {
    { name = "Card Library State Initialize Contract", fn = run_initialize_contract },
    { name = "Card Library State Filter + Selection Contract", fn = run_filter_selection_contract },
    { name = "Card Library State Scroll + Topic Cycle Contract", fn = run_scroll_and_cycle_contract }
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

return CardLibraryStateSpec
