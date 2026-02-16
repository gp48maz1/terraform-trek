local InfluenceLayout = {}

local function clamp_value(value, min_value, max_value)
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
end

function InfluenceLayout.compute(safe_rect)
  local safe = safe_rect
  local panel_gap = 14
  local top_y = safe.y + 76
  local cards_h = clamp_value(math.floor(safe.h * 0.24), 170, 196)
  local cards_y = safe.y + safe.h - cards_h
  local top_h = cards_y - top_y - 12

  local hazard_w = math.max(220, math.floor(safe.w * 0.18))
  local objectives_w = math.max(430, math.floor(safe.w * 0.285))
  local map_w = safe.w - hazard_w - objectives_w - (panel_gap * 2)
  if map_w < 520 then
    local deficit = 520 - map_w
    objectives_w = math.max(360, objectives_w - deficit)
    map_w = safe.w - hazard_w - objectives_w - (panel_gap * 2)
  end

  local hazard_rect = {
    x = safe.x,
    y = top_y,
    w = hazard_w,
    h = top_h
  }

  local map_rect = {
    x = hazard_rect.x + hazard_rect.w + panel_gap,
    y = top_y,
    w = map_w,
    h = top_h
  }

  local map_header_h = 120
  local map_footer_h = 44
  local map_graph_rect = {
    x = map_rect.x + 14,
    y = map_rect.y + map_header_h,
    w = map_rect.w - 28,
    h = map_rect.h - map_header_h - map_footer_h
  }

  local map_center_x = map_graph_rect.x + math.floor(map_graph_rect.w * 0.5)
  local map_center_y = map_graph_rect.y + math.floor(map_graph_rect.h * 0.52)
  local offset_x = math.floor(map_graph_rect.w * 0.29)
  local offset_y = math.floor(map_graph_rect.h * 0.24)
  local node_radius = math.max(48, math.floor(math.min(map_graph_rect.w, map_graph_rect.h) * 0.125))
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
    x = map_graph_rect.x + 8,
    y = map_graph_rect.y + 8,
    w = map_graph_rect.w - 16,
    h = map_graph_rect.h - 16
  }

  local turn_explain_rect = {
    x = safe.x + 12,
    y = map_rect.y + 98,
    w = safe.w - 24,
    h = map_rect.h - 90
  }

  local cards_rect = {
    x = safe.x,
    y = cards_y,
    w = safe.w,
    h = cards_h
  }

  local magnetosphere_base_r = math.floor(math.max(offset_x + node_radius, offset_y + node_radius) + 10)
  local magnetosphere = {
    x = map_center_x,
    y = map_center_y,
    base_r = magnetosphere_base_r
  }

  local hazard_card_w = math.min(hazard_rect.w - 20, 236)
  local hazard_card_h = math.max(190, math.min(hazard_rect.h - 62, 266))
  local hazard_card_y = hazard_rect.y + 42
  local hazard_bottom = hazard_rect.y + hazard_rect.h - 10
  if hazard_card_y + hazard_card_h > hazard_bottom then
    hazard_card_h = math.max(160, hazard_bottom - hazard_card_y)
  end
  local hazard_card_rect = {
    x = hazard_rect.x + math.floor((hazard_rect.w - hazard_card_w) * 0.5),
    y = hazard_card_y,
    w = hazard_card_w,
    h = hazard_card_h
  }

  return {
    hazard_rect = hazard_rect,
    hazard_card_rect = hazard_card_rect,
    map_rect = map_rect,
    map_graph_rect = map_graph_rect,
    nodes = nodes,
    magnetosphere = magnetosphere,
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
  local card_w = 166
  local card_h = 56
  local gap_x = 12
  local gap_y = 8
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
