local TurnResolver = {}

local function apply_action_to_state(state, action)
  if not action or action.type == "do_nothing" then
    return
  end

  if action.type == "stats_delta" then
    state:apply_stat_changes(action.changes or {})
    return
  end

  if action.type ~= "card" then
    return
  end

  local card = action.card
  if not card then
    return
  end

  local effect_name = card.effect_fn_name
  if effect_name == "apply_stat_changes" then
    state:apply_player_changes((card.properties and card.properties.stat_changes) or {})
  elseif effect_name == "stabilize_system" then
    state:adjust_toward_targets(1)
  elseif effect_name == "install_industry" then
    local def = card.properties and card.properties.industry_def
    if def then
      state:install_industry(def)
    end
  end
end

function TurnResolver.resolve_end_turn(run_state, action, _rng)
  local state = run_state and run_state.terraforming_state or run_state
  apply_action_to_state(state, action)
  local report = state:end_turn()
  return run_state, report
end

return TurnResolver
