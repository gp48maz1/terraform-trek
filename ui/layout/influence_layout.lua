local InfluenceLayout = {}

function InfluenceLayout.compute(safe_rect)
  local safe = safe_rect
  local panel_gap = 14
  local top_y = safe.y + 76
  local top_h = math.floor(safe.h * 0.62)
  local map_w = math.floor(safe.w * 0.54)
  local map_rect = {
    x = safe.x,
    y = top_y,
    w = map_w,
    h = top_h
  }

  local map_center_x = map_rect.x + math.floor(map_rect.w * 0.5)
  local map_center_y = map_rect.y + math.floor(map_rect.h * 0.6)
  local offset_x = math.floor(map_rect.w * 0.29)
  local offset_y = math.floor(map_rect.h * 0.24)
  local node_radius = math.max(48, math.floor(math.min(map_rect.w, map_rect.h) * 0.11))
  local nodes = {
    heat = { x = map_center_x, y = map_center_y - offset_y, r = node_radius },
    water = { x = map_center_x + offset_x, y = map_center_y, r = node_radius },
    soil = { x = map_center_x, y = map_center_y + offset_y, r = node_radius },
    air = { x = map_center_x - offset_x, y = map_center_y, r = node_radius }
  }

  local right_x = map_rect.x + map_rect.w + panel_gap
  local right_w = safe.x + safe.w - right_x
  local objectives_rect = {
    x = right_x,
    y = map_rect.y,
    w = right_w,
    h = top_h
  }

  local graph_explain_rect = {
    x = map_rect.x + 22,
    y = map_rect.y + 92,
    w = map_rect.w - 44,
    h = map_rect.h - 120
  }

  local turn_explain_rect = {
    x = safe.x + 12,
    y = map_rect.y + 92,
    w = safe.w - 24,
    h = map_rect.h - 82
  }

  local cards_y = map_rect.y + map_rect.h + 12
  local cards_rect = {
    x = safe.x,
    y = cards_y,
    w = safe.w,
    h = (safe.y + safe.h) - cards_y
  }

  return {
    map_rect = map_rect,
    nodes = nodes,
    objectives_rect = objectives_rect,
    graph_explain_rect = graph_explain_rect,
    turn_explain_rect = turn_explain_rect,
    cards_rect = cards_rect
  }
end

function InfluenceLayout.get_map_toggle_buttons(layout)
  local map_rect = layout.map_rect
  local button_h = 26
  local filter_w = 198
  local right = map_rect.x + map_rect.w - 12
  local filter_x = right - filter_w
  local y = map_rect.y + 8
  local explain_w = 154
  local explain_y = map_rect.y + map_rect.h - button_h - 8

  return {
    filter = { x = filter_x, y = y, w = filter_w, h = button_h },
    explain_graph = { x = map_rect.x + 12, y = explain_y, w = explain_w, h = button_h }
  }
end

function InfluenceLayout.get_forecast_mode_buttons(rect)
  return {
    {
      id = "current",
      text = "Current",
      x = rect.x + 14,
      y = rect.y + 108,
      w = 168,
      h = 24
    }
  }
end

function InfluenceLayout.get_preview_explain_button(layout)
  local rect = layout.cards_rect
  return {
    x = rect.x + 12,
    y = rect.y + rect.h - 30,
    w = 176,
    h = 24
  }
end

function InfluenceLayout.get_objectives_explain_button(layout)
  local rect = layout.objectives_rect
  return {
    x = rect.x + 14,
    y = rect.y + rect.h - 34,
    w = 188,
    h = 24
  }
end

function InfluenceLayout.get_card_rects(layout, hand)
  local rows = {}
  local options = {
    { kind = "do_nothing" }
  }
  for i, card in ipairs(hand or {}) do
    table.insert(options, { kind = "card", card = card, card_index = i })
  end

  local rect = layout.cards_rect
  local card_w = 170
  local card_h = 58
  local gap_x = 12
  local gap_y = 10
  local footer_reserved = 42
  local cards_per_row = math.max(1, math.floor((rect.w - 20 + gap_x) / (card_w + gap_x)))
  local max_rows = math.max(1, math.floor((rect.h - 34 - footer_reserved + gap_y) / (card_h + gap_y)))
  local used_width = cards_per_row * card_w + (cards_per_row - 1) * gap_x
  local start_x = rect.x + math.floor((rect.w - used_width) / 2)

  for i, option in ipairs(options) do
    local row = math.floor((i - 1) / cards_per_row)
    if row >= max_rows then
      break
    end
    local col = (i - 1) % cards_per_row
    local x = start_x + col * (card_w + gap_x)
    local y = rect.y + 34 + row * (card_h + gap_y)
    rows[i] = {
      x = x,
      y = y,
      w = card_w,
      h = card_h,
      option = option
    }
  end

  return rows
end

return InfluenceLayout
