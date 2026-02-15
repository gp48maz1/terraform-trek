local TerraformingState = require("terraforming_state")
local ForecastSystem = require("systems.forecast_system")
local TurnResolver = require("systems.turn_resolver")

local function assert_equal(actual, expected, label)
  if actual ~= expected then
    error(label .. " expected " .. tostring(expected) .. " got " .. tostring(actual))
  end
end

local function run_baseline()
  love.math.setRandomSeed(12345)

  local state = TerraformingState.new({
    name = "Test World",
    goal = 20,
    turn_limit = 10,
    magnetosphere_level = 3,
    starting_stats = { heat = 1, air = -3, water = 2, soil = -2 }
  })

  local run_state = { terraforming_state = state }

  local forecast = ForecastSystem.preview(run_state, { type = "do_nothing" })
  assert_equal(type(forecast.net), "number", "forecast.net type")

  local _, report = TurnResolver.resolve_end_turn(run_state, { type = "do_nothing" })
  assert_equal(report.turn, 1, "turn index")
  assert_equal(state.turn, 2, "state turn advanced")

  return {
    forecast_hazard = forecast.hazard,
    realized_hazard = report.hazard,
    realized_net = report.net,
    population = state.population,
    profit = state.profit
  }
end

return {
  run_baseline = run_baseline
}
