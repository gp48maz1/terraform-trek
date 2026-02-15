local CardLibraryLayout = require("ui.layout.card_library_layout")

local CardLibraryLayoutSpec = {}

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

local function run_compute_window_contract()
  local result = make_result()
  local topics = { "All", "Terraform", "Industry" }
  local measure = function(text)
    return #text * 8
  end

  add_log(result, "GIVEN a compact card-library window and deterministic text widths")
  local layout = CardLibraryLayout.compute_for_window(400, 300, topics, measure)
  add_log(result, "WHEN computing filter row + content panes")

  expect_equal(result, "three filter chips are produced", #layout.filter_rects, 3)
  expect_equal(result, "first filter x", layout.filter_rects[1].x, 20)
  expect_equal(result, "second filter x", layout.filter_rects[2].x, 112)
  expect_equal(result, "third filter x", layout.filter_rects[3].x, 214)
  expect_equal(result, "grid x", layout.grid_rect.x, 20)
  expect_equal(result, "grid y", layout.grid_rect.y, 128)
  expect_equal(result, "grid width after narrow fallback", layout.grid_rect.w, 88)
  expect_equal(result, "detail panel width after fallback", layout.detail_rect.w, 260)
  expect_equal(result, "detail panel x", layout.detail_rect.x, 120)
  return result
end

local function run_filter_wrap_contract()
  local result = make_result()
  local topics = { "TopicA", "TopicB", "TopicC" }
  local measure = function(_)
    return 88
  end

  add_log(result, "GIVEN chip widths that force filter wrapping")
  local layout = CardLibraryLayout.compute_for_window(260, 380, topics, measure)
  add_log(result, "WHEN computing filter chip positions")

  expect_equal(result, "first chip first row", layout.filter_rects[1].y, 88)
  expect_equal(result, "second chip wraps to second row", layout.filter_rects[2].y, 124)
  expect_equal(result, "third chip wraps to third row", layout.filter_rects[3].y, 160)
  return result
end

local function run_card_rects_contract()
  local result = make_result()
  local grid_rect = { x = 20, y = 120, w = 500, h = 320 }
  local entries = {}
  for i = 1, 7 do
    entries[i] = { id = i }
  end

  add_log(result, "GIVEN a grid rect and seven card entries")
  local rects, max_scroll = CardLibraryLayout.get_card_rects(grid_rect, entries, 44)
  add_log(result, "WHEN generating scrolled card rects")

  expect_equal(result, "all entries produce rects", #rects, 7)
  expect_equal(result, "first rect x", rects[1].x, 31)
  expect_equal(result, "first rect y applies scroll offset", rects[1].y, 86)
  expect_equal(result, "fourth rect starts second row", rects[4].y, 327)
  expect_equal(result, "computed max scroll", max_scroll, 407)
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

function CardLibraryLayoutSpec.run()
  local scenarios = {
    { name = "Card Library Window Layout Contract", fn = run_compute_window_contract },
    { name = "Card Library Filter Wrap Contract", fn = run_filter_wrap_contract },
    { name = "Card Library Card Rects Contract", fn = run_card_rects_contract }
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

return CardLibraryLayoutSpec
