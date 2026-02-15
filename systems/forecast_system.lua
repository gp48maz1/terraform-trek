local ForecastSystem = {}

local function copy_table(input)
  local out = {}
  for k, v in pairs(input or {}) do
    out[k] = v
  end
  return out
end

local function apply_preview_action(state, snapshot, economy, action)
  if not action or action.type == "do_nothing" then
    return
  end

  if action.type == "stats_delta" then
    state:apply_stat_changes_to(action.changes or {}, snapshot)
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
    state:apply_stat_changes_to((card.properties and card.properties.stat_changes) or {}, snapshot)
  elseif effect_name == "stabilize_system" then
    state:adjust_snapshot_toward_targets(snapshot, 1)
  elseif effect_name == "install_industry" then
    local def = card.properties and card.properties.industry_def
    if def then
      state:install_industry_in_slots(def, economy.industries)
    end
  end
end

function ForecastSystem.preview(run_state, action)
  local state = run_state and run_state.terraforming_state or run_state
  local snapshot = copy_table(state.stats)
  local economy = state:get_economy_snapshot()

  apply_preview_action(state, snapshot, economy, action)

  return state:forecast_end_turn(snapshot, {
    economy_state = economy
  })
end

return ForecastSystem
