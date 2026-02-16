local Background = require("background")

local InfluenceLayout = require("ui.layout.influence_layout")

local ObjectivesPanel = require("ui.components.objectives_panel")
local InfluenceExplain = require("ui.components.influence_explain")
local HazardCard = require("ui.components.hazard_card")

local RuntimeInfluence = {}
RuntimeInfluence.__index = RuntimeInfluence

function RuntimeInfluence.new(ctx)
  return setmetatable({ ctx = ctx }, RuntimeInfluence)
end

function RuntimeInfluence:get_influence_layout()
  return InfluenceLayout.compute(self.ctx:get_safe_rect())
end

function RuntimeInfluence:get_map_toggle_buttons(layout)
  return InfluenceLayout.get_map_toggle_buttons(layout)
end

function RuntimeInfluence:get_forecast_mode_buttons(rect)
  return InfluenceLayout.get_forecast_mode_buttons(rect)
end

function RuntimeInfluence:get_preview_explain_button(layout)
  return InfluenceLayout.get_preview_explain_button(layout)
end

function RuntimeInfluence:get_objectives_explain_button(layout)
  return InfluenceLayout.get_objectives_explain_button(layout)
end

function RuntimeInfluence:get_influence_card_rects(layout)
  return InfluenceLayout.get_card_rects(layout, self.ctx.player_deck.hand)
end

function RuntimeInfluence:edge_is_visible(edge)
  return self.ctx.influence_ui:edge_is_visible(edge)
end

function RuntimeInfluence:draw_influence_edge(source, target, edge, highlight, current_delta)
  local is_active = current_delta ~= 0
  local dx = target.x - source.x
  local dy = target.y - source.y
  local distance = math.sqrt(dx * dx + dy * dy)
  if distance == 0 then
    return
  end

  local ux = dx / distance
  local uy = dy / distance
  local start_x = source.x + ux * source.r
  local start_y = source.y + uy * source.r
  local end_x = target.x - ux * target.r
  local end_y = target.y - uy * target.r

  local curve = edge.curve or 0
  local mid_x = (start_x + end_x) / 2
  local mid_y = (start_y + end_y) / 2
  local perp_x = -uy
  local perp_y = ux
  local control_x = mid_x + perp_x * curve
  local control_y = mid_y + perp_y * curve

  local color = { 0.55, 0.6, 0.67, 0.45 }
  if current_delta > 0 then
    color = highlight and { 0.45, 0.95, 0.45, 1 } or { 0.33, 0.72, 0.37, 0.78 }
  elseif current_delta < 0 then
    color = highlight and { 0.98, 0.45, 0.45, 1 } or { 0.76, 0.34, 0.34, 0.78 }
  end

  love.graphics.setColor(unpack(color))
  love.graphics.setLineWidth(highlight and 3 or (is_active and 2.5 or 1.5))
  if math.abs(curve) < 0.001 then
    love.graphics.line(start_x, start_y, end_x, end_y)
  else
    local points = {}
    local segments = 18
    for i = 0, segments do
      local t = i / segments
      local omt = 1 - t
      local px = omt * omt * start_x + 2 * omt * t * control_x + t * t * end_x
      local py = omt * omt * start_y + 2 * omt * t * control_y + t * t * end_y
      table.insert(points, px)
      table.insert(points, py)
    end
    love.graphics.line(points)
  end
  love.graphics.setLineWidth(1)

  local arrow_size = 8
  local arrow_angle = math.pi / 7
  local tangent_x = end_x - control_x
  local tangent_y = end_y - control_y
  if math.abs(curve) < 0.001 then
    tangent_x = end_x - start_x
    tangent_y = end_y - start_y
  end
  local angle = self.ctx:safe_atan2(tangent_y, tangent_x)
  local ax1 = end_x - arrow_size * math.cos(angle - arrow_angle)
  local ay1 = end_y - arrow_size * math.sin(angle - arrow_angle)
  local ax2 = end_x - arrow_size * math.cos(angle + arrow_angle)
  local ay2 = end_y - arrow_size * math.sin(angle + arrow_angle)
  love.graphics.line(end_x, end_y, ax1, ay1)
  love.graphics.line(end_x, end_y, ax2, ay2)

  local badge_x = (start_x + end_x + control_x) / 3
  local badge_y = (start_y + end_y + control_y) / 3
  love.graphics.setColor(0.08, 0.1, 0.14, 0.92)
  love.graphics.circle("fill", badge_x, badge_y, 10)
  love.graphics.setColor(unpack(color))
  love.graphics.circle("line", badge_x, badge_y, 10)
  love.graphics.setColor(1, 1, 1, 1)
  local badge_text = self.ctx:format_signed(current_delta)
  love.graphics.printf(badge_text, badge_x - 10, badge_y - 7, 20, "center")
end

function RuntimeInfluence:value_to_track_x(bounds, value, x, w)
  local span = bounds.max - bounds.min
  if span <= 0 then
    return x + (w * 0.5)
  end
  local t = (value - bounds.min) / span
  return x + t * w
end

function RuntimeInfluence:lerp(a, b, t)
  return a + (b - a) * t
end

function RuntimeInfluence:draw_diamond(x, y, size, fill_color, border_color)
  love.graphics.setColor(unpack(fill_color))
  love.graphics.polygon(
    "fill",
    x, y - size,
    x + size, y,
    x, y + size,
    x - size, y
  )
  if border_color then
    love.graphics.setColor(unpack(border_color))
    love.graphics.polygon(
      "line",
      x, y - size,
      x + size, y,
      x, y + size,
      x - size, y
    )
  end
end

function RuntimeInfluence:draw_stat_track(map_graph_rect, node, stat_key, current_value, preview_value, target_value)
  local bounds = self.ctx.terraforming_state:get_stat_bounds(stat_key)
  local track_w = math.floor(node.r * 1.6)
  local track_h = 12
  local track_x = math.floor(node.x - (track_w * 0.5))
  local track_y = math.floor(node.y - node.r - 20)
  local min_track_y = map_graph_rect.y + 8
  if track_y < min_track_y then
    track_y = min_track_y
  end
  local current_x = self:value_to_track_x(bounds, current_value, track_x, track_w)
  local marker_min_x = track_x + 5
  local marker_max_x = track_x + track_w - 5
  current_x = self.ctx:clamp_value(current_x, marker_min_x, marker_max_x)
  local max_distance = math.max(math.abs(bounds.min - target_value), math.abs(bounds.max - target_value))
  if max_distance < 1 then
    max_distance = 1
  end

  love.graphics.setColor(0.08, 0.1, 0.14, 0.96)
  love.graphics.rectangle("fill", track_x, track_y, track_w, track_h, 4, 4)
  for i = 0, track_w - 1 do
    local t = i / math.max(1, track_w - 1)
    local value = bounds.min + (bounds.max - bounds.min) * t
    local severity = math.min(1, math.abs(value - target_value) / max_distance)
    local r = self:lerp(0.12, 0.8, severity)
    local g = self:lerp(0.42, 0.16, severity)
    local b = self:lerp(0.14, 0.18, severity)
    love.graphics.setColor(r, g, b, 0.95)
    love.graphics.rectangle("fill", track_x + i, track_y + 2, 1, track_h - 4)
  end

  love.graphics.setColor(0.58, 0.67, 0.78, 0.95)
  love.graphics.rectangle("line", track_x, track_y, track_w, track_h, 4, 4)

  local marker_y = track_y + math.floor(track_h * 0.5)
  self:draw_diamond(current_x, marker_y, 5, { 1, 1, 1, 1 }, { 0.05, 0.08, 0.12, 1 })

  if preview_value then
    local preview_x = self:value_to_track_x(bounds, preview_value, track_x, track_w)
    preview_x = self.ctx:clamp_value(preview_x, marker_min_x, marker_max_x)
    if math.abs(preview_x - current_x) < 3 then
      self:draw_diamond(preview_x, marker_y, 7, { 0.25, 0.48, 0.66, 0.15 }, { 0.45, 0.78, 1.0, 1 })
    else
      self:draw_diamond(preview_x, marker_y, 5, { 0.45, 0.78, 1.0, 1 }, { 0.05, 0.08, 0.12, 1 })
    end
  end
end

function RuntimeInfluence:draw_magnetosphere_field(layout)
  local magnetosphere = layout.magnetosphere
  if not magnetosphere then
    return
  end

  local mag_level = self.ctx.terraforming_state:get_magnetosphere_level()
  local strength = self.ctx:clamp_value((mag_level - 1) / 3, 0, 1)
  local cx = magnetosphere.x
  local cy = magnetosphere.y
  local base_r = magnetosphere.base_r

  love.graphics.push()
  love.graphics.translate(cx, cy)

  for i = 1, 5 do
    local t = i / 5
    local radius = base_r + (i - 1) * 18
    local stretch = 1.0 + t * 0.55
    local alpha = (0.05 + strength * 0.05) * (1.0 - t * 0.25)
    love.graphics.push()
    love.graphics.scale(stretch, 1)
    love.graphics.setColor(0.38, 0.68, 1.0, alpha)
    love.graphics.circle("line", 0, 0, radius)
    love.graphics.pop()
  end

  for i = 1, 3 do
    local radius = base_r + 46 + i * 16
    local warm_alpha = 0.03 + (1.0 - strength) * 0.05
    love.graphics.setColor(0.96, 0.55, 0.25, warm_alpha)
    love.graphics.arc("line", "open", math.pi * 0.73, math.pi * 1.27, radius)
  end

  love.graphics.pop()
  love.graphics.setColor(1, 1, 1, 1)
end

function RuntimeInfluence:draw_incoming_hazard_panel(layout)
  local hazard_rect = layout.hazard_rect
  local hazard_card_rect = layout.hazard_card_rect
  if not hazard_rect or not hazard_card_rect then
    return
  end

  local projection = self.ctx.terraforming_state:preview_next_hazard()
  local hazard = projection.hazard or {}
  local mag_level = self.ctx.terraforming_state:get_magnetosphere_level()
  local mag_tier = self.ctx.terraforming_state:get_magnetosphere_tier(mag_level)
  local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 3.1)

  love.graphics.setColor(0.06, 0.08, 0.12, 0.9)
  love.graphics.rectangle("fill", hazard_rect.x, hazard_rect.y, hazard_rect.w, hazard_rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", hazard_rect.x, hazard_rect.y, hazard_rect.w, hazard_rect.h, 10, 10)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Incoming Hazard", hazard_rect.x + 10, hazard_rect.y + 10, hazard_rect.w - 20, "left")
  love.graphics.setColor(0.75, 0.87, 0.95, 1)
  love.graphics.printf(
    "Magnetosphere L" .. tostring(mag_level) .. " (" .. mag_tier .. ")",
    hazard_rect.x + 10,
    hazard_rect.y + 30,
    hazard_rect.w - 20,
    "left"
  )

  HazardCard.draw({
    rect = hazard_card_rect,
    projection = projection,
    target = {
      x = layout.magnetosphere.x,
      y = layout.magnetosphere.y,
      radius = math.floor(layout.magnetosphere.base_r * 0.62)
    },
    pulse = pulse,
    format_delta_list = function(deltas)
      return self.ctx:format_delta_list(deltas)
    end,
    magnetosphere_level = mag_level,
    magnetosphere_tier = mag_tier
  })

  local footer_y = hazard_rect.y + hazard_rect.h - 44
  local footer_text
  if hazard.magnetosphere_blockable then
    footer_text = "After block: " .. self.ctx:format_delta_list(projection.effective_deltas)
    love.graphics.setColor(0.7, 0.9, 1.0, 1)
  else
    footer_text = "Bypasses magnetosphere"
    love.graphics.setColor(0.93, 0.8, 0.42, 1)
  end
  love.graphics.printf(footer_text, hazard_rect.x + 10, footer_y, hazard_rect.w - 20, "left")
  love.graphics.setColor(1, 1, 1, 1)
end

function RuntimeInfluence:draw_influence_nodes(layout, forecast_ctx)
  local map_rect = layout.map_rect
  local graph_rect = layout.map_graph_rect
  local snapshot = forecast_ctx.active_snapshot
  local toggle_buttons = self:get_map_toggle_buttons(layout)
  local projection_label = "Viewing Current State"
  if forecast_ctx.active_mode ~= "current" then
    projection_label = "Viewing End-Turn Projection"
  end

  love.graphics.setColor(0.06, 0.08, 0.12, 0.88)
  love.graphics.rectangle("fill", map_rect.x, map_rect.y, map_rect.w, map_rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", map_rect.x, map_rect.y, map_rect.w, map_rect.h, 10, 10)

  love.graphics.setColor(1, 1, 1, 1)
  local font_h = love.graphics.getFont():getHeight()
  local title_y = map_rect.y + 10
  local subtitle_y = title_y + font_h + 2
  local projection_y = subtitle_y + font_h + 2
  love.graphics.printf("Core Influence Graph", map_rect.x + 12, title_y, map_rect.w - 24, "left")
  love.graphics.printf("Use Explain Graph for detailed coupling rules and focused primitive breakdown.", map_rect.x + 12, subtitle_y, map_rect.w - 24, "left")
  love.graphics.setColor(0.75, 0.87, 0.95, 1)
  love.graphics.printf(projection_label, map_rect.x + 12, projection_y, map_rect.w - 24, "left")

  local filter_fill = self.ctx.influence_ui.hovered_edge_filter_button and { 0.2, 0.3, 0.4, 0.95 } or { 0.14, 0.19, 0.27, 0.95 }
  love.graphics.setColor(unpack(filter_fill))
  love.graphics.rectangle("fill", toggle_buttons.filter.x, toggle_buttons.filter.y, toggle_buttons.filter.w, toggle_buttons.filter.h, 7, 7)
  love.graphics.setColor(0.7, 0.82, 0.96, 1)
  love.graphics.rectangle("line", toggle_buttons.filter.x, toggle_buttons.filter.y, toggle_buttons.filter.w, toggle_buttons.filter.h, 7, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Flow: " .. self.ctx.influence_ui:get_edge_filter_label(), toggle_buttons.filter.x + 8, toggle_buttons.filter.y + 6, toggle_buttons.filter.w - 12, "left")

  local graph_fill = self.ctx.influence_ui.show_graph_explain and { 0.24, 0.42, 0.26, 1 } or { 0.13, 0.18, 0.25, 1 }
  if self.ctx.influence_ui.hovered_graph_explain_button and not self.ctx.influence_ui.show_graph_explain then
    graph_fill = { 0.18, 0.24, 0.33, 1 }
  end
  local graph_border = self.ctx.influence_ui.show_graph_explain and { 0.65, 0.95, 0.64, 1 } or { 0.62, 0.78, 0.95, 1 }
  love.graphics.setColor(unpack(graph_fill))
  love.graphics.rectangle("fill", toggle_buttons.explain_graph.x, toggle_buttons.explain_graph.y, toggle_buttons.explain_graph.w, toggle_buttons.explain_graph.h, 7, 7)
  love.graphics.setColor(unpack(graph_border))
  love.graphics.rectangle("line", toggle_buttons.explain_graph.x, toggle_buttons.explain_graph.y, toggle_buttons.explain_graph.w, toggle_buttons.explain_graph.h, 7, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(self.ctx.influence_ui.show_graph_explain and "Hide Graph" or "Explain Graph", toggle_buttons.explain_graph.x + 4, toggle_buttons.explain_graph.y + 6, toggle_buttons.explain_graph.w - 8, "center")

  local legend_row1_y = projection_y + font_h + 6
  local legend_row2_y = legend_row1_y + font_h + 4

  love.graphics.setColor(0.45, 0.95, 0.45, 1)
  love.graphics.circle("fill", map_rect.x + 18, legend_row1_y + 7, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("+ target impact", map_rect.x + 30, legend_row1_y)
  love.graphics.setColor(0.98, 0.45, 0.45, 1)
  love.graphics.circle("fill", map_rect.x + 166, legend_row1_y + 7, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("- target impact", map_rect.x + 178, legend_row1_y)
  love.graphics.setColor(0.62, 0.66, 0.74, 1)
  love.graphics.circle("fill", map_rect.x + 314, legend_row1_y + 7, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("0 neutral", map_rect.x + 326, legend_row1_y)

  self:draw_diamond(map_rect.x + 18, legend_row2_y + 8, 5, { 1, 1, 1, 1 }, { 0.05, 0.08, 0.12, 1 })
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("current", map_rect.x + 30, legend_row2_y + 1)
  self:draw_diamond(map_rect.x + 124, legend_row2_y + 8, 5, { 0.45, 0.78, 1.0, 1 }, { 0.05, 0.08, 0.12, 1 })
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("preview (card push)", map_rect.x + 136, legend_row2_y + 1)

  self:draw_magnetosphere_field(layout)

  for _, edge in ipairs(self.ctx.INFLUENCE_EDGES) do
    if self:edge_is_visible(edge) then
      local source = layout.nodes[edge.source]
      local target = layout.nodes[edge.target]
      local highlight = edge.source == self.ctx.influence_ui.focused_stat or edge.target == self.ctx.influence_ui.focused_stat
      local edge_delta = self.ctx:get_context_edge_delta(forecast_ctx, edge)
      self:draw_influence_edge(source, target, edge, highlight, edge_delta)
    end
  end

  for _, key in ipairs(self.ctx.STAT_ORDER) do
    local node = layout.nodes[key]
    local value = snapshot[key]
    local current_value = self.ctx.terraforming_state.stats[key]
    local preview_value = nil
    if forecast_ctx.active_mode == "selected" and forecast_ctx.card_push_snapshot then
      preview_value = forecast_ctx.card_push_snapshot[key]
    end
    local status, color = self.ctx:get_stat_status(key, value)
    local is_focused = key == self.ctx.influence_ui.focused_stat
    local is_hovered = key == self.ctx.influence_ui.hovered_influence_stat

    self:draw_stat_track(graph_rect, node, key, current_value, preview_value, self.ctx.terraforming_state.targets[key])

    love.graphics.setColor(0.08, 0.1, 0.14, 0.95)
    love.graphics.circle("fill", node.x, node.y, node.r)
    love.graphics.setColor(is_focused and 0.98 or color[1], is_focused and 0.98 or color[2], is_focused and 0.98 or color[3], 1)
    love.graphics.setLineWidth(is_focused and 4 or (is_hovered and 3 or 2))
    love.graphics.circle("line", node.x, node.y, node.r)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(self.ctx.STAT_LABELS[key], node.x - node.r + 8, node.y - 26, node.r * 2 - 16, "center")
    love.graphics.printf(self.ctx:format_signed(value) .. " (" .. status .. ")", node.x - node.r + 8, node.y - 6, node.r * 2 - 16, "center")
  end
end

function RuntimeInfluence:get_forecast_mode_label(active_mode)
  if active_mode == "do_nothing" then
    return "Do Nothing"
  elseif active_mode == "selected" then
    return "Selected Card"
  end
  return "Current"
end

function RuntimeInfluence:draw_end_objectives_panel(layout, forecast_ctx)
  ObjectivesPanel.draw({
    rect = layout.objectives_rect,
    layout = layout,
    forecast_ctx = forecast_ctx,
    influence_ui = self.ctx.influence_ui,
    terraforming_state = self.ctx.terraforming_state,
    stat_order = self.ctx.STAT_ORDER,
    stat_labels = self.ctx.STAT_LABELS,
    format_signed = function(value)
      return self.ctx:format_signed(value)
    end,
    clamp_value = function(value, min_value, max_value)
      return self.ctx:clamp_value(value, min_value, max_value)
    end,
    get_forecast_mode_label = function(mode)
      return self:get_forecast_mode_label(mode)
    end,
    get_objectives_explain_button = function(inner_layout)
      return self:get_objectives_explain_button(inner_layout)
    end
  })
end

function RuntimeInfluence:draw_influence_details(rect, forecast_ctx)
  InfluenceExplain.draw_details({
    rect = rect,
    forecast_ctx = forecast_ctx,
    influence_ui = self.ctx.influence_ui,
    terraforming_state = self.ctx.terraforming_state,
    influence_edges = self.ctx.INFLUENCE_EDGES,
    influence_help = self.ctx.INFLUENCE_HELP,
    stat_order = self.ctx.STAT_ORDER,
    stat_labels = self.ctx.STAT_LABELS,
    format_signed = function(value)
      return self.ctx:format_signed(value)
    end,
    show_real_world_values = self.ctx.show_real_world_values,
    get_real_world_mapping = function(stat, value)
      return self.ctx:get_real_world_mapping(stat, value)
    end,
    get_edges_from_stat = function(stat)
      return self.ctx:get_edges_from_stat(stat)
    end,
    get_context_edge_delta = function(context, edge)
      return self.ctx:get_context_edge_delta(context, edge)
    end,
    draw_wrapped_line = function(text, x, y, width, color, line_height)
      return self.ctx:draw_wrapped_line(text, x, y, width, color, line_height)
    end,
    get_stat_status = function(stat, value)
      return self.ctx:get_stat_status(stat, value)
    end
  })
end

function RuntimeInfluence:draw_forecast_panel(rect, forecast_ctx)
  InfluenceExplain.draw_forecast_panel({
    rect = rect,
    forecast_ctx = forecast_ctx,
    mode_buttons = self:get_forecast_mode_buttons(rect),
    influence_ui = self.ctx.influence_ui,
    terraforming_state = self.ctx.terraforming_state,
    influence_edges = self.ctx.INFLUENCE_EDGES,
    stat_order = self.ctx.STAT_ORDER,
    stat_labels = self.ctx.STAT_LABELS,
    format_signed = function(value)
      return self.ctx:format_signed(value)
    end,
    format_delta_list = function(deltas)
      return self.ctx:format_delta_list(deltas)
    end,
    draw_wrapped_line = function(text, x, y, width, color, line_height)
      return self.ctx:draw_wrapped_line(text, x, y, width, color, line_height)
    end,
    get_forecast_mode_label = function(mode)
      return self:get_forecast_mode_label(mode)
    end
  })
end

function RuntimeInfluence:draw_influence_cards(layout)
  local rect = layout.cards_rect
  local card_rects = self:get_influence_card_rects(layout)
  local explain_button = self:get_preview_explain_button(layout)

  love.graphics.setColor(0.06, 0.08, 0.12, 0.92)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 10, 10)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Preview Selector (Do Nothing or card). Use Current above to clear preview.", rect.x + 10, rect.y + 10, rect.w - 20, "left")

  local turn_fill = self.ctx.influence_ui.show_turn_explain and { 0.24, 0.42, 0.26, 1 } or { 0.13, 0.18, 0.25, 1 }
  if self.ctx.influence_ui.hovered_turn_explain_button and not self.ctx.influence_ui.show_turn_explain then
    turn_fill = { 0.18, 0.24, 0.33, 1 }
  end
  local turn_border = self.ctx.influence_ui.show_turn_explain and { 0.65, 0.95, 0.64, 1 } or { 0.62, 0.78, 0.95, 1 }
  love.graphics.setColor(unpack(turn_fill))
  love.graphics.rectangle("fill", explain_button.x, explain_button.y, explain_button.w, explain_button.h, 7, 7)
  love.graphics.setColor(unpack(turn_border))
  love.graphics.rectangle("line", explain_button.x, explain_button.y, explain_button.w, explain_button.h, 7, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(self.ctx.influence_ui.show_turn_explain and "Hide Turn" or "Explain Next Turn", explain_button.x + 4, explain_button.y + 6, explain_button.w - 8, "center")

  for i, card_rect in ipairs(card_rects) do
    local option = card_rect.option
    local is_do_nothing = option.kind == "do_nothing"
    local card = option.card
    local selected = false
    local affordable = true
    if is_do_nothing then
      selected = self.ctx.influence_ui.forecast_mode == "do_nothing"
    else
      selected = self.ctx.influence_ui.forecast_mode == "selected" and self.ctx.influence_ui.selected_forecast_card_index == option.card_index
      affordable = self.ctx:can_afford(card.cost or 0)
    end
    local hovered = (self.ctx.influence_ui.hovered_forecast_option_index == i)

    local fill = selected and { 0.22, 0.38, 0.25, 0.98 } or { 0.12, 0.14, 0.18, 0.98 }
    local border = selected and { 0.64, 0.93, 0.62, 1 } or { 0.48, 0.58, 0.7, 1 }
    if hovered and not selected then
      fill = { 0.16, 0.2, 0.26, 0.98 }
    end
    if not affordable and not selected then
      fill = { 0.22, 0.12, 0.12, 0.92 }
      border = { 0.82, 0.46, 0.42, 1 }
    end

    love.graphics.setColor(unpack(fill))
    love.graphics.rectangle("fill", card_rect.x, card_rect.y, card_rect.w, card_rect.h, 8, 8)
    love.graphics.setColor(unpack(border))
    love.graphics.rectangle("line", card_rect.x, card_rect.y, card_rect.w, card_rect.h, 8, 8)

    local text_color = affordable and { 1, 1, 1, 1 } or { 1, 0.75, 0.6, 1 }
    love.graphics.setColor(unpack(text_color))
    if is_do_nothing then
      love.graphics.printf("0. Do Nothing", card_rect.x + 8, card_rect.y + 8, card_rect.w - 16, "left")
      love.graphics.printf("Preview end-turn outcome without playing a card.", card_rect.x + 8, card_rect.y + 28, card_rect.w - 16, "left")
    else
      love.graphics.printf(option.card_index .. ". " .. card.name, card_rect.x + 8, card_rect.y + 8, card_rect.w - 16, "left")
      love.graphics.printf(
        "Cost " .. tostring(card.cost or 0) .. " | " .. card.description,
        card_rect.x + 8,
        card_rect.y + 28,
        card_rect.w - 16,
        "left"
      )
    end
  end
end

function RuntimeInfluence:draw_influence_screen()
  local safe = self.ctx:get_safe_rect()
  local heading_x = safe.x
  local heading_y = safe.y - 8
  local layout = self:get_influence_layout()
  local forecast_ctx = self.ctx:get_forecast_context()

  Background.draw_fill()
  Background.draw_stars()

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("Core Influence Map (V)", heading_x, heading_y)
  love.graphics.print("Click primitive to focus. Arrows show coupling for the selected reference mode; blue marker shows card push.", heading_x, heading_y + 20)
  love.graphics.print("Use Explain Graph, Explain Next Turn, and Explain Objectives for detailed breakdowns.", heading_x, heading_y + 40)
  love.graphics.print("M mapping, C clear card, I flow, Z current, X do nothing, P selected card, V gameplay.", heading_x, heading_y + 60)

  self:draw_incoming_hazard_panel(layout)
  self:draw_influence_nodes(layout, forecast_ctx)
  self:draw_end_objectives_panel(layout, forecast_ctx)
  if self.ctx.influence_ui.show_graph_explain then
    self:draw_influence_details(layout.graph_explain_rect, forecast_ctx)
  end
  if self.ctx.influence_ui.show_turn_explain then
    self:draw_forecast_panel(layout.turn_explain_rect, forecast_ctx)
  end
  self:draw_influence_cards(layout)

  if self.ctx.campaign_state ~= "playing" then
    self:draw_status_overlay()
  end
end

function RuntimeInfluence:draw_status_overlay()
  local width = love.graphics.getWidth()
  local box_w = 620
  local box_h = 130
  local box_x = (width - box_w) / 2
  local box_y = 140

  love.graphics.setColor(0.05, 0.05, 0.08, 0.85)
  love.graphics.rectangle("fill", box_x, box_y, box_w, box_h, 8, 8)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("line", box_x, box_y, box_w, box_h, 8, 8)

  if self.ctx.campaign_state == "world_won" then
    love.graphics.printf("World Terraformed!", box_x, box_y + 24, box_w, "center")
    love.graphics.printf("Press N for the next world.", box_x, box_y + 56, box_w, "center")
  elseif self.ctx.campaign_state == "campaign_won" then
    love.graphics.printf("Campaign Complete", box_x, box_y + 24, box_w, "center")
    love.graphics.printf("You terraformed all worlds. Press R to restart.", box_x, box_y + 56, box_w, "center")
  elseif self.ctx.campaign_state == "campaign_lost" then
    love.graphics.printf("Terraforming Failed", box_x, box_y + 24, box_w, "center")
    love.graphics.printf("Turn limit reached before habitability target. Press R to restart.", box_x, box_y + 56, box_w, "center")
  end
end

function RuntimeInfluence:update(_dt)
  self.ctx:update_viewport_from_graphics()

  if not self.ctx.target or not self.ctx.player_deck then
    return
  end

  self.ctx.target:update(0)
  self.ctx.influence_ui:sanitize_selection(#self.ctx.player_deck.hand)
  self.ctx.hovered_card_index = nil
  self.ctx.hovered_draw_pile = false
  self.ctx.hovered_discard_pile = false
  self.ctx.hovered_end_turn = false
  self.ctx.influence_ui:reset_hover_state()

  if self.ctx.campaign_state ~= "playing" then
    return
  end

  local raw_mx, raw_my = love.mouse.getPosition()
  local has_pointer, mx, my = self.ctx:map_pointer_to_ui(raw_mx, raw_my)
  if not has_pointer then
    return
  end

  local layout = self:get_influence_layout()
  local toggle_buttons = self:get_map_toggle_buttons(layout)
  self.ctx.influence_ui.hovered_edge_filter_button = self.ctx:point_in_rect(mx, my, toggle_buttons.filter.x, toggle_buttons.filter.y, toggle_buttons.filter.w, toggle_buttons.filter.h)
  self.ctx.influence_ui.hovered_graph_explain_button = self.ctx:point_in_rect(mx, my, toggle_buttons.explain_graph.x, toggle_buttons.explain_graph.y, toggle_buttons.explain_graph.w, toggle_buttons.explain_graph.h)

  local explain_button = self:get_preview_explain_button(layout)
  self.ctx.influence_ui.hovered_turn_explain_button = self.ctx:point_in_rect(mx, my, explain_button.x, explain_button.y, explain_button.w, explain_button.h)

  local objectives_explain_button = self:get_objectives_explain_button(layout)
  self.ctx.influence_ui.hovered_objectives_explain_button = self.ctx:point_in_rect(
    mx,
    my,
    objectives_explain_button.x,
    objectives_explain_button.y,
    objectives_explain_button.w,
    objectives_explain_button.h
  )

  if self.ctx.influence_ui.show_turn_explain then
    local forecast_buttons = self:get_forecast_mode_buttons(layout.turn_explain_rect)
    for _, button in ipairs(forecast_buttons) do
      if self.ctx:point_in_rect(mx, my, button.x, button.y, button.w, button.h) then
        self.ctx.influence_ui.hovered_forecast_mode = button.id
        break
      end
    end
  end

  for _, key in ipairs(self.ctx.STAT_ORDER) do
    local node = layout.nodes[key]
    if self.ctx:point_in_circle(mx, my, node.x, node.y, node.r) then
      self.ctx.influence_ui.hovered_influence_stat = key
      break
    end
  end

  local card_rects = self:get_influence_card_rects(layout)
  for i, rect in ipairs(card_rects) do
    if self.ctx:point_in_rect(mx, my, rect.x, rect.y, rect.w, rect.h) then
      self.ctx.influence_ui.hovered_forecast_option_index = i
      break
    end
  end
end

function RuntimeInfluence:draw()
  if not self.ctx.player_deck or not self.ctx.terraforming_state then
    return
  end

  if self.ctx.viewport then
    self.ctx.viewport:begin_draw()
  end
  self:draw_influence_screen()
  if self.ctx.viewport then
    self.ctx.viewport:end_draw()
  end
end

function RuntimeInfluence:keypressed(key)
  if key == "r" then
    self.ctx:start_campaign()
    return
  end

  if key == "v" then
    self.ctx.view_mode = "gameplay"
    return
  end

  if key == "m" then
    self.ctx.show_real_world_values = not self.ctx.show_real_world_values
    return
  end

  if self.ctx.campaign_state == "world_won" then
    if key == "n" then
      self.ctx:setup_world(self.ctx.world_index + 1)
    end
    return
  end

  if self.ctx.campaign_state ~= "playing" then
    return
  end

  if key == "e" then
    self.ctx:end_turn()
    return
  end

  if key == "i" then
    self.ctx.influence_ui:cycle_edge_filter_mode()
    return
  end

  if key == "z" then
    self.ctx.influence_ui:set_current_mode()
    return
  end

  if key == "x" then
    self.ctx.influence_ui:set_do_nothing_mode(false)
    return
  end

  if key == "p" then
    self.ctx.influence_ui:set_selected_or_do_nothing_mode()
    return
  end

  if key == "c" then
    self.ctx.influence_ui:set_current_mode()
    return
  end

  local num = tonumber(key)
  if num and num >= 1 and num <= #self.ctx.player_deck.hand then
    self.ctx.influence_ui:set_selected_mode(num)
  end
end

function RuntimeInfluence:mousepressed(x, y, button)
  if button ~= 1 then
    return
  end

  local has_pointer, mapped_x, mapped_y = self.ctx:map_pointer_to_ui(x, y)
  if not has_pointer then
    return
  end

  if self.ctx.campaign_state ~= "playing" then
    return
  end

  local layout = self:get_influence_layout()
  local toggle_buttons = self:get_map_toggle_buttons(layout)
  if self.ctx:point_in_rect(mapped_x, mapped_y, toggle_buttons.filter.x, toggle_buttons.filter.y, toggle_buttons.filter.w, toggle_buttons.filter.h) then
    self.ctx.influence_ui:cycle_edge_filter_mode()
    return
  end

  if self.ctx:point_in_rect(mapped_x, mapped_y, toggle_buttons.explain_graph.x, toggle_buttons.explain_graph.y, toggle_buttons.explain_graph.w, toggle_buttons.explain_graph.h) then
    self.ctx.influence_ui:toggle_graph_explain()
    return
  end

  local explain_button = self:get_preview_explain_button(layout)
  if self.ctx:point_in_rect(mapped_x, mapped_y, explain_button.x, explain_button.y, explain_button.w, explain_button.h) then
    self.ctx.influence_ui:toggle_turn_explain()
    return
  end

  local objectives_explain_button = self:get_objectives_explain_button(layout)
  if self.ctx:point_in_rect(
    mapped_x,
    mapped_y,
    objectives_explain_button.x,
    objectives_explain_button.y,
    objectives_explain_button.w,
    objectives_explain_button.h
  ) then
    self.ctx.influence_ui:toggle_objectives_explain()
    return
  end

  if self.ctx.influence_ui.show_turn_explain then
    local forecast_buttons = self:get_forecast_mode_buttons(layout.turn_explain_rect)
    for _, forecast_button in ipairs(forecast_buttons) do
      if self.ctx:point_in_rect(mapped_x, mapped_y, forecast_button.x, forecast_button.y, forecast_button.w, forecast_button.h) then
        self.ctx.influence_ui:set_current_mode()
        return
      end
    end
  end

  for _, key in ipairs(self.ctx.STAT_ORDER) do
    local node = layout.nodes[key]
    if self.ctx:point_in_circle(mapped_x, mapped_y, node.x, node.y, node.r) then
      self.ctx.influence_ui.focused_stat = key
      return
    end
  end

  local card_rects = self:get_influence_card_rects(layout)
  for _, card_rect in ipairs(card_rects) do
    if self.ctx:point_in_rect(mapped_x, mapped_y, card_rect.x, card_rect.y, card_rect.w, card_rect.h) then
      local option = card_rect.option
      if option.kind == "do_nothing" then
        self.ctx.influence_ui:set_do_nothing_mode(true)
      else
        self.ctx.influence_ui:set_selected_mode(option.card_index)
      end
      return
    end
  end
end

function RuntimeInfluence:wheelmoved(_, _)
end

return RuntimeInfluence
