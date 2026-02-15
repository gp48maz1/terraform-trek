local GameplayLayout = {}

function GameplayLayout.compute(safe_rect, ui_state)
  local safe = safe_rect
  local card_w = ((ui_state and ui_state.hand_ui and ui_state.hand_ui.card_width) or 150)
  local card_h = ((ui_state and ui_state.hand_ui and ui_state.hand_ui.card_height) or 225)
  local hand_y = safe.y + safe.h - card_h - 12

  local deck_w = 88
  local deck_h = 118

  return {
    planet = {
      x = safe.x + safe.w * 0.72,
      y = safe.y + safe.h * 0.34,
      radius = math.floor(math.min(safe.w, safe.h) * 0.28)
    },
    hand = {
      baseline_y = hand_y
    },
    deck = {
      x = safe.x + 8,
      y = hand_y - deck_h - 24,
      w = deck_w,
      h = deck_h
    },
    discard = {
      x = safe.x + safe.w - deck_w - 8,
      y = hand_y - deck_h - 24,
      w = deck_w,
      h = deck_h
    },
    end_turn = {
      w = 170,
      h = 50,
      x = safe.x + safe.w - 186,
      y = hand_y + card_h - 58
    },
    incoming_hazard = {
      x = safe.x + safe.w * 0.53,
      y = safe.y + safe.h * 0.25,
      w = 140,
      h = 180
    }
  }
end

return GameplayLayout
