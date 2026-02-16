local InfluenceExplain = {}

function InfluenceExplain.draw_details(opts)
  local forecast_ctx = opts.forecast_ctx
  local influence_ui = opts.influence_ui
  local snapshot = forecast_ctx.active_snapshot
  local focused_stat = influence_ui.focused_stat
  local value = snapshot[focused_stat]
  local help = opts.influence_help[focused_stat]
  local status, color = opts.get_stat_status(focused_stat, value)
  local coupling_signal = opts.terraforming_state:get_source_coupling_signal(focused_stat, snapshot)
  local coupling_rule_text = opts.terraforming_state:get_coupling_rule_text(focused_stat)

  local incoming_edges = {}
  for _, edge in ipairs(opts.influence_edges) do
    if edge.target == focused_stat then
      table.insert(incoming_edges, edge)
    end
  end

  local outgoing_edges = opts.get_edges_from_stat(focused_stat)
  local incoming_total = 0
  local incoming_active = 0
  for _, edge in ipairs(incoming_edges) do
    local delta = opts.get_context_edge_delta(forecast_ctx, edge)
    incoming_total = incoming_total + delta
    if delta ~= 0 then
      incoming_active = incoming_active + 1
    end
  end

  local outgoing_total = 0
  local outgoing_active = 0
  for _, edge in ipairs(outgoing_edges) do
    local delta = opts.get_context_edge_delta(forecast_ctx, edge)
    outgoing_total = outgoing_total + delta
    if delta ~= 0 then
      outgoing_active = outgoing_active + 1
    end
  end

  local mode_label = "Current"
  if forecast_ctx.active_mode == "do_nothing" then
    mode_label = "Do Nothing Forecast"
  elseif forecast_ctx.active_mode == "selected" then
    mode_label = "Selected Card Forecast"
  else
    mode_label = "Current State"
  end

  local rect = opts.rect
  love.graphics.setColor(0.06, 0.08, 0.12, 1)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 10, 10)

  local text_x = rect.x + 14
  local text_w = rect.w - 28
  local line_y = rect.y + 14
  local bottom_y = rect.y + rect.h - 14

  line_y = opts.draw_wrapped_line("Focused Primitive: " .. opts.stat_labels[focused_stat], text_x, line_y, text_w, { 1, 1, 1, 1 }, 16)
  line_y = opts.draw_wrapped_line("Reference: " .. mode_label, text_x, line_y + 2, text_w, color, 16)
  line_y = opts.draw_wrapped_line("Notch: " .. opts.format_signed(value) .. " (" .. status .. ")", text_x, line_y + 2, text_w, color, 16)
  line_y = opts.draw_wrapped_line(help.summary, text_x, line_y + 2, text_w, { 1, 1, 1, 1 }, 16)
  line_y = opts.draw_wrapped_line("Incoming: " .. help.incoming, text_x, line_y + 2, text_w, { 1, 1, 1, 1 }, 16)

  local coupling_text = "Coupling signal: 0 (neutral) at this source state."
  local coupling_color = { 0.98, 0.82, 0.35, 1 }
  if coupling_signal > 0 then
    coupling_text = "Coupling signal: " .. opts.format_signed(coupling_signal) .. " (supportive) from this source state."
    coupling_color = { 0.45, 0.95, 0.45, 1 }
  elseif coupling_signal < 0 then
    coupling_text = "Coupling signal: " .. opts.format_signed(coupling_signal) .. " (stress) from this source state."
    coupling_color = { 0.98, 0.62, 0.42, 1 }
  end
  line_y = opts.draw_wrapped_line(coupling_text, text_x, line_y + 2, text_w, coupling_color, 16)
  line_y = opts.draw_wrapped_line(opts.terraforming_state:get_coupling_rules_summary(), text_x, line_y + 2, text_w, { 1, 1, 1, 1 }, 16)
  line_y = opts.draw_wrapped_line(coupling_rule_text, text_x, line_y + 2, text_w, { 1, 1, 1, 1 }, 16)
  line_y = opts.draw_wrapped_line(
    "Incoming net " .. opts.format_signed(incoming_total) .. " (" ..
      tostring(incoming_active) .. "/" .. tostring(#incoming_edges) .. " active) | Outgoing net " ..
      opts.format_signed(outgoing_total) .. " (" .. tostring(outgoing_active) .. "/" .. tostring(#outgoing_edges) .. " active)",
    text_x,
    line_y + 2,
    text_w,
    { 1, 1, 1, 1 },
    16
  )

  if opts.show_real_world_values and (line_y + 18) < bottom_y then
    opts.draw_wrapped_line(opts.get_real_world_mapping(focused_stat, value), text_x, line_y + 4, text_w, { 0.75, 0.87, 0.95, 1 }, 16)
  end
end

function InfluenceExplain.draw_forecast_panel(opts)
  local forecast_ctx = opts.forecast_ctx
  local baseline = forecast_ctx.baseline
  local scenario = forecast_ctx.scenario
  local mode_buttons = opts.mode_buttons
  local influence_ui = opts.influence_ui
  local current_population = forecast_ctx.current_economy.population
  local current_profit = forecast_ctx.current_economy.profit
  local rect = opts.rect

  love.graphics.setColor(0.06, 0.08, 0.12, 1)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 10, 10)

  local text_x = rect.x + 14
  local text_w = rect.w - 28
  local line_y = rect.y + 12

  line_y = opts.draw_wrapped_line("End-Turn Forecast", text_x, line_y, text_w, { 1, 1, 1, 1 }, 16)
  line_y = opts.draw_wrapped_line(
    "Hazard: " .. baseline.hazard .. " [" .. tostring(baseline.hazard_category or "Hazard") .. "]",
    text_x,
    line_y + 2,
    text_w,
    { 1, 1, 1, 1 },
    16
  )
  line_y = opts.draw_wrapped_line(
    "Hazard raw: " .. opts.format_delta_list(baseline.hazard_raw_deltas),
    text_x,
    line_y + 2,
    text_w,
    { 0.75, 0.87, 0.95, 1 },
    16
  )
  if baseline.hazard_blockable then
    line_y = opts.draw_wrapped_line(
      "Magnetosphere block: " .. opts.format_delta_list(baseline.hazard_blocked_deltas) ..
        " | Effective hazard: " .. opts.format_delta_list(baseline.hazard_effective_deltas),
      text_x,
      line_y + 2,
      text_w,
      { 0.75, 0.87, 0.95, 1 },
      16
    )
  else
    line_y = opts.draw_wrapped_line(
      "Hazard bypasses magnetosphere. Effective hazard: " .. opts.format_delta_list(baseline.hazard_effective_deltas),
      text_x,
      line_y + 2,
      text_w,
      { 0.75, 0.87, 0.95, 1 },
      16
    )
  end
  line_y = opts.draw_wrapped_line(
    "Map reference mode: " .. opts.get_forecast_mode_label(forecast_ctx.active_mode),
    text_x,
    line_y + 2,
    text_w,
    { 0.75, 0.87, 0.95, 1 },
    16
  )

  for _, button in ipairs(mode_buttons) do
    local active = forecast_ctx.active_mode == button.id
    local hovered = influence_ui.hovered_forecast_mode == button.id
    local fill = active and { 0.24, 0.42, 0.26, 0.98 } or { 0.13, 0.18, 0.25, 0.98 }
    local border = active and { 0.65, 0.95, 0.64, 1 } or { 0.62, 0.78, 0.95, 1 }
    if hovered and not active then
      fill = { 0.18, 0.24, 0.33, 0.98 }
    end

    love.graphics.setColor(unpack(fill))
    love.graphics.rectangle("fill", button.x, button.y, button.w, button.h, 7, 7)
    love.graphics.setColor(unpack(border))
    love.graphics.rectangle("line", button.x, button.y, button.w, button.h, 7, 7)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(button.text, button.x + 4, button.y + 6, button.w - 8, "center")
  end

  local function get_card_delta(summary, key)
    local start_stats = summary and summary.start_stats or {}
    local current = opts.terraforming_state.stats[key] or 0
    local start = start_stats[key] or current
    return start - current
  end

  local function format_edge_terms(summary)
    local terms = {}
    local edge_deltas = summary and summary.coupling_edge_deltas or {}
    for _, edge in ipairs(opts.influence_edges) do
      local key = edge.source .. "->" .. edge.target
      local delta = edge_deltas[key] or 0
      if delta ~= 0 then
        terms[#terms + 1] = edge.text .. " " .. opts.format_signed(delta)
      end
    end
    if #terms == 0 then
      return "Coupling edges: none"
    end
    return "Coupling edges: " .. table.concat(terms, " | ")
  end

  local function draw_outcome_column(column_x, column_y, column_w, heading, summary, baseline_net, affordable_now)
    local y = opts.draw_wrapped_line(heading, column_x, column_y, column_w, { 1, 1, 1, 1 }, 16)
    if not summary then
      opts.draw_wrapped_line("Select a card below to preview a one-card outcome.", column_x, y + 2, column_w, { 1, 1, 1, 1 }, 16)
      return
    end

    if affordable_now == false then
      y = opts.draw_wrapped_line("Card unaffordable now (preview only).", column_x, y + 2, column_w, { 0.98, 0.65, 0.35, 1 }, 16)
    end

    for _, key in ipairs(opts.stat_order) do
      local current = opts.terraforming_state.stats[key] or 0
      local card_delta = get_card_delta(summary, key)
      local hazard_delta = (summary.hazard_deltas and summary.hazard_deltas[key]) or 0
      local coupling_delta = (summary.coupling_target_deltas_applied and summary.coupling_target_deltas_applied[key]) or
        (summary.coupling_deltas and summary.coupling_deltas[key]) or 0
      local projected = (summary.projected_stats and summary.projected_stats[key]) or current
      local equation = opts.stat_labels[key] .. ": " .. opts.format_signed(current) ..
        " + card " .. opts.format_signed(card_delta) ..
        " + hazard " .. opts.format_signed(hazard_delta) ..
        " + coupling " .. opts.format_signed(coupling_delta) ..
        " = " .. opts.format_signed(projected)
      y = opts.draw_wrapped_line(equation, column_x, y + 1, column_w, { 1, 1, 1, 1 }, 15)
    end

    local net_line = "Net Habitability: " .. opts.format_signed(summary.net)
    if baseline_net then
      net_line = net_line .. " (" .. opts.format_signed(summary.net - baseline_net) .. " vs do-nothing)"
    end
    y = opts.draw_wrapped_line(net_line, column_x, y + 2, column_w, { 1, 1, 1, 1 }, 15)
    y = opts.draw_wrapped_line(
      "Population: " .. tostring(current_population) .. " + " .. opts.format_signed(summary.population_delta or 0) ..
        " = " .. tostring(summary.projected_population or current_population),
      column_x,
      y + 1,
      column_w,
      { 1, 1, 1, 1 },
      15
    )
    y = opts.draw_wrapped_line(
      "Profit: " .. tostring(current_profit) .. " + " .. opts.format_signed(summary.profit_delta or 0) ..
        " = " .. tostring(summary.projected_profit or current_profit),
      column_x,
      y + 1,
      column_w,
      { 1, 1, 1, 1 },
      15
    )
    opts.draw_wrapped_line(format_edge_terms(summary), column_x, y + 2, column_w, { 0.75, 0.87, 0.95, 1 }, 15)
  end

  local split_x = rect.x + math.floor(rect.w * 0.5)
  draw_outcome_column(rect.x + 14, rect.y + 146, rect.w * 0.46, "Do Nothing Outcome", baseline)
  draw_outcome_column(
    split_x + 8,
    rect.y + 146,
    rect.w * 0.46 - 12,
    "Selected Option Outcome",
    scenario and scenario.summary or nil,
    baseline.net,
    scenario and scenario.affordable
  )
end

return InfluenceExplain
