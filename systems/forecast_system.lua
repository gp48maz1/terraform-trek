local ForecastSystem = {}
local ActionApplier = require("systems.action_applier")

local function copy_table(input)
  local out = {}
  for k, v in pairs(input or {}) do
    out[k] = v
  end
  return out
end

function ForecastSystem.preview(run_state, action)
  local state = run_state and run_state.terraforming_state or run_state
  local snapshot = copy_table(state.stats)
  local economy = state:get_economy_snapshot()

  ActionApplier.apply_action_preview(state, snapshot, economy, action)

  return state:forecast_end_turn(snapshot, {
    economy_state = economy
  })
end

return ForecastSystem
