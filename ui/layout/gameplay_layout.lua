local GameplayLayout = {}

local function clamp_value(value, min_value, max_value)
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
end

function GameplayLayout.get_planet(safe_rect)
  local safe = safe_rect
  return {
    x = safe.x + (safe.w * 0.72),
    y = safe.y + (safe.h * 0.34),
    radius = math.floor(math.min(safe.w, safe.h) * 0.28)
  }
end

function GameplayLayout.get_hand_layout(safe_rect, num_cards, hand_ui)
  local safe = safe_rect
  local hand = hand_ui or {}
  local card_width = hand.card_width or 150
  local card_height = hand.card_height or 225
  local card_spacing = hand.card_spacing or 175
  local total_hand_width = 0
  if num_cards and num_cards > 0 then
    total_hand_width = card_width + (num_cards - 1) * card_spacing
  end
  return {
    start_x = safe.x + ((safe.w - total_hand_width) * 0.5),
    base_y = safe.y + safe.h - card_height - 24
  }
end

function GameplayLayout.get_deck_rect(safe_rect, pile_ui)
  local safe = safe_rect
  local pile = pile_ui or {}
  local w = pile.width or 90
  local h = pile.height or 120
  local y = safe.y + safe.h - h - 12
  return {
    x = safe.x + 16,
    y = y,
    w = w,
    h = h
  }
end

function GameplayLayout.get_discard_rect(safe_rect, pile_ui)
  local safe = safe_rect
  local pile = pile_ui or {}
  local w = pile.width or 90
  local h = pile.height or 120
  local y = safe.y + safe.h - h - 12
  return {
    x = safe.x + safe.w - w - 16,
    y = y,
    w = w,
    h = h
  }
end

function GameplayLayout.get_end_turn_rect(safe_rect, hand_layout, hand_ui, end_turn_ui, pile_ui)
  local safe = safe_rect
  local end_turn = end_turn_ui or {}
  local h = end_turn.height or 44
  local w = end_turn.width or 142
  local discard = GameplayLayout.get_discard_rect(safe, pile_ui)
  local x = discard.x + math.floor((discard.w - w) * 0.5)
  local y = discard.y - h - 14
  x = clamp_value(x, safe.x + 14, safe.x + safe.w - w - 14)
  y = clamp_value(y, safe.y + 14, safe.y + safe.h - h - 14)
  return {
    x = x,
    y = y,
    w = w,
    h = h
  }
end

function GameplayLayout.get_hazard_card_rect(safe_rect, planet)
  local safe = safe_rect
  local card_w = 170
  local card_h = 236
  local desired_x = planet.x - planet.radius - card_w - 24
  local min_x = safe.x + 16
  local max_x = safe.x + safe.w - card_w - 16
  local x = clamp_value(desired_x, min_x, max_x)
  local y = clamp_value(
    planet.y - math.floor(card_h * 0.36),
    safe.y + 16,
    safe.y + safe.h - card_h - 16
  )
  return {
    x = x,
    y = y,
    w = card_w,
    h = card_h
  }
end

function GameplayLayout.compute(safe_rect, ui_state)
  local safe = safe_rect
  local hand = (ui_state and ui_state.hand_ui) or nil
  local pile = (ui_state and ui_state.pile_ui) or nil
  local end_turn = (ui_state and ui_state.end_turn_ui) or nil
  local hand_count = (ui_state and ui_state.hand_count) or 0
  local planet = GameplayLayout.get_planet(safe)
  local hand_layout = GameplayLayout.get_hand_layout(safe, hand_count, hand)

  return {
    planet = planet,
    hand = hand_layout,
    deck = GameplayLayout.get_deck_rect(safe, pile),
    discard = GameplayLayout.get_discard_rect(safe, pile),
    end_turn = GameplayLayout.get_end_turn_rect(safe, hand_layout, hand, end_turn, pile),
    incoming_hazard = GameplayLayout.get_hazard_card_rect(safe, planet)
  }
end

return GameplayLayout
