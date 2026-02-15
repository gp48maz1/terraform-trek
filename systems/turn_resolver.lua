local TurnResolver = {}
local ActionApplier = require("systems.action_applier")

function TurnResolver.resolve_end_turn(run_state, action, _rng)
  local state = run_state and run_state.terraforming_state or run_state
  ActionApplier.apply_action_live(state, action)
  local report = state:end_turn()
  return run_state, report
end

return TurnResolver
