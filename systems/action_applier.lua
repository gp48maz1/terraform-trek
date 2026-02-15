local ActionApplier = {}

local function is_do_nothing(action)
  return (not action) or action.type == "do_nothing"
end

function ActionApplier.apply_card_preview(state, card, snapshot, economy_state)
  if not card then
    return
  end

  local effect_name = card.effect_fn_name
  if effect_name == "apply_stat_changes" then
    state:apply_stat_changes_to((card.properties and card.properties.stat_changes) or {}, snapshot)
  elseif effect_name == "stabilize_system" then
    state:adjust_snapshot_toward_targets(snapshot, 1)
  elseif effect_name == "install_industry" then
    local industry_def = card.properties and card.properties.industry_def
    if industry_def and economy_state and economy_state.industries then
      state:install_industry_in_slots(industry_def, economy_state.industries)
    end
  end
end

function ActionApplier.apply_action_preview(state, snapshot, economy_state, action)
  if is_do_nothing(action) then
    return
  end

  if action.type == "stats_delta" then
    state:apply_stat_changes_to(action.changes or {}, snapshot)
    return
  end

  if action.type == "card" then
    ActionApplier.apply_card_preview(state, action.card, snapshot, economy_state)
  end
end

function ActionApplier.apply_card_live(state, card)
  if not card then
    return
  end

  local effect_name = card.effect_fn_name
  if effect_name == "apply_stat_changes" then
    state:apply_player_changes((card.properties and card.properties.stat_changes) or {})
  elseif effect_name == "stabilize_system" then
    state:adjust_toward_targets(1)
  elseif effect_name == "install_industry" then
    local industry_def = card.properties and card.properties.industry_def
    if industry_def then
      state:install_industry(industry_def)
    end
  end
end

function ActionApplier.apply_action_live(state, action)
  if is_do_nothing(action) then
    return
  end

  if action.type == "stats_delta" then
    state:apply_stat_changes(action.changes or {})
    return
  end

  if action.type == "card" then
    ActionApplier.apply_card_live(state, action.card)
  end
end

return ActionApplier
