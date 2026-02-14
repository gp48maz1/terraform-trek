local CardEffects = {}

function CardEffects.draw_cards(context)
  local card = context.card
  local deck = context.deck
  local draw_amount = card.properties.draw_amount or 0

  if deck and draw_amount > 0 then
    deck:draw(draw_amount)
  else
    print("  Warning: Could not draw cards (deck missing or draw_amount is zero).")
  end
end

function CardEffects.apply_stat_changes(context)
  local card = context.card
  local terraforming_state = context.terraforming_state
  if not terraforming_state then
    print("Warning: Missing terraforming_state in card context.")
    return
  end

  local stat_changes = card.properties.stat_changes or {}
  terraforming_state:apply_player_changes(stat_changes)
end

function CardEffects.stabilize_system(context)
  local terraforming_state = context.terraforming_state
  if not terraforming_state then
    print("Warning: Missing terraforming_state in card context.")
    return
  end

  terraforming_state:adjust_toward_targets(1)
end

return CardEffects
