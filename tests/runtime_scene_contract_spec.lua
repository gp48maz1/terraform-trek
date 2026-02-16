local RuntimeGameplay = require("app.runtime_gameplay")
local RuntimeInfluence = require("app.runtime_influence")
local RuntimeCardLibrary = require("app.runtime_card_library")

local RuntimeSceneContractSpec = {}

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

local function expect_type(result, label, value, expected_type)
  expect_equal(result, label .. " type", type(value), expected_type)
end

local REQUIRED_METHODS = { "update", "draw", "keypressed", "mousepressed", "wheelmoved" }

local function verify_controller_contract(result, name, controller)
  add_log(result, "WHEN checking scene controller API for " .. name)
  for _, method_name in ipairs(REQUIRED_METHODS) do
    expect_type(result, name .. "." .. method_name, controller[method_name], "function")
  end
end

local function run_controller_api_contract()
  local result = make_result()

  local gameplay_ctx = {
    campaign_state = "campaign_lost",
    unrelated_token = 11
  }
  local influence_ctx = {
    campaign_state = "campaign_lost",
    unrelated_token = 22
  }
  local card_library_ctx = {
    unrelated_token = 33
  }

  add_log(result, "GIVEN stub runtime contexts")
  local gameplay = RuntimeGameplay.new(gameplay_ctx)
  local influence = RuntimeInfluence.new(influence_ctx)
  local card_library = RuntimeCardLibrary.new(card_library_ctx)

  verify_controller_contract(result, "gameplay", gameplay)
  verify_controller_contract(result, "influence", influence)
  verify_controller_contract(result, "card_library", card_library)

  add_log(result, "WHEN invoking no-op safe handlers on stub contexts")
  gameplay:keypressed("?")
  gameplay:mousepressed(0, 0, 2)
  gameplay:wheelmoved(0, 0)

  influence:keypressed("?")
  influence:mousepressed(0, 0, 2)
  influence:wheelmoved(0, 0)

  card_library:keypressed("?")
  card_library:mousepressed(0, 0, 2)

  expect_equal(result, "gameplay context unrelated value unchanged", gameplay_ctx.unrelated_token, 11)
  expect_equal(result, "influence context unrelated value unchanged", influence_ctx.unrelated_token, 22)
  expect_equal(result, "card library context unrelated value unchanged", card_library_ctx.unrelated_token, 33)

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

function RuntimeSceneContractSpec.run()
  local scenarios = {
    { name = "Scene Runtime Controller Contract", fn = run_controller_api_contract }
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

return RuntimeSceneContractSpec
