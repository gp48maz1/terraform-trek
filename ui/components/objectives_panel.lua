local ObjectivesPanel = {}

local function get_quality_label(quality)
  if quality == "good" then
    return "Good"
  elseif quality == "ok" then
    return "Ok"
  end
  return "Bad"
end

local function get_quality_score(quality)
  if quality == "good" then
    return 1
  elseif quality == "ok" then
    return 0
  end
  return -1
end

local function build_population_snapshot_breakdown(terraforming_state, stat_order, snapshot)
  local quality = {}
  local scores = {}
  local primitive_sum = 0
  local good_count = 0

  for _, key in ipairs(stat_order) do
    local grade = terraforming_state:get_stat_quality(key, snapshot[key])
    local score = get_quality_score(grade)
    quality[key] = grade
    scores[key] = score
    primitive_sum = primitive_sum + score
    if score > 0 then
      good_count = good_count + 1
    end
  end

  local synergy = 0
  if good_count >= 2 then
    synergy = math.min(4, good_count)
  end

  return {
    quality = quality,
    scores = scores,
    primitive = primitive_sum,
    good_count = good_count,
    synergy = synergy,
    delta = 1 + primitive_sum + synergy
  }
end

local function build_profit_snapshot_breakdown(active_summary, slot_count)
  if not active_summary or not active_summary.industry_report then
    return nil
  end

  local report = active_summary.industry_report
  local terms = {}
  local term_text = {}
  local total = 0
  for i = 1, slot_count do
    local slot = report[i]
    local income = 0
    local status = "open"
    if slot and not slot.empty then
      if slot.destroyed then
        status = "destroyed"
      else
        income = slot.income or 0
        status = "active"
      end
    end
    total = total + income
    terms[i] = { income = income, status = status }
    table.insert(term_text, "S" .. tostring(i) .. " " .. (income > 0 and ("+" .. tostring(income)) or tostring(income)))
  end

  return {
    terms = terms,
    term_text = term_text,
    total = total
  }
end

local function get_score_color(score)
  if score > 0 then
    return { 0.66, 0.92, 0.64, 1 }, { 0.12, 0.24, 0.16, 1 }
  elseif score < 0 then
    return { 0.98, 0.62, 0.58, 1 }, { 0.24, 0.13, 0.13, 1 }
  end
  return { 0.76, 0.84, 0.95, 1 }, { 0.12, 0.16, 0.22, 1 }
end

local function draw_end_objective_metric_graph(rect, y, label, current_value, active_value, bar_color, format_signed, clamp_value)
  local bar_x = rect.x + 14
  local bar_y = y + 18
  local bar_w = rect.w - 28
  local bar_h = 14
  local scale_max = math.max(10, current_value, active_value)
  local current_t = clamp_value(current_value / scale_max, 0, 1)
  local active_t = clamp_value(active_value / scale_max, 0, 1)

  local line = label .. ": " .. tostring(current_value)
  if active_value ~= current_value then
    line = line .. " -> " .. tostring(active_value) .. " (" .. format_signed(active_value - current_value) .. ")"
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(line, rect.x + 14, y, rect.w - 28, "left")

  love.graphics.setColor(0.08, 0.1, 0.14, 1)
  love.graphics.rectangle("fill", bar_x, bar_y, bar_w, bar_h, 5, 5)
  love.graphics.setColor(bar_color[1], bar_color[2], bar_color[3], 0.95)
  love.graphics.rectangle("fill", bar_x + 1, bar_y + 1, math.floor((bar_w - 2) * current_t), bar_h - 2, 4, 4)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", bar_x, bar_y, bar_w, bar_h, 5, 5)

  local marker_x = bar_x + math.floor((bar_w - 2) * active_t)
  love.graphics.setColor(0.48, 0.74, 1.0, 1)
  love.graphics.setLineWidth(2)
  love.graphics.line(marker_x, bar_y - 1, marker_x, bar_y + bar_h + 1)
  love.graphics.setLineWidth(1)
end

local function draw_wrapped_line(text, x, y, width, color, line_height)
  if color then
    love.graphics.setColor(unpack(color))
  else
    love.graphics.setColor(1, 1, 1, 1)
  end
  love.graphics.printf(text, x, y, width, "left")
  local font = love.graphics.getFont()
  local _, wrapped = font:getWrap(text, width)
  return y + (math.max(1, #wrapped) * (line_height or 16))
end

local function fit_single_line(text, max_width)
  local font = love.graphics.getFont()
  if font:getWidth(text) <= max_width then
    return text
  end

  local suffix = "..."
  local suffix_w = font:getWidth(suffix)
  local trimmed = text
  while #trimmed > 0 and (font:getWidth(trimmed) + suffix_w) > max_width do
    trimmed = string.sub(trimmed, 1, #trimmed - 1)
  end

  if #trimmed == 0 then
    return suffix
  end
  return trimmed .. suffix
end

local function calculate_profit_flow_totals(active_industries, profit_breakdown, population_value, slot_count)
  local base_total = 0
  local pop_bonus_total = 0
  local income_total = 0

  for i = 1, slot_count do
    local industry = active_industries[i]
    if industry then
      local base_income = industry.base_profit or 0
      local income = nil
      if profit_breakdown and profit_breakdown.terms and profit_breakdown.terms[i] then
        income = profit_breakdown.terms[i].income
      end
      if income == nil then
        local pop_bonus = math.floor((population_value or 0) * (industry.population_factor or 0) + 0.5)
        income = base_income + pop_bonus
      end
      base_total = base_total + base_income
      pop_bonus_total = pop_bonus_total + (income - base_income)
      income_total = income_total + income
    end
  end

  return {
    base_total = base_total,
    pop_bonus_total = pop_bonus_total,
    income_total = income_total
  }
end

local function draw_end_objectives_explain_overlay(opts)
  local rect = opts.rect
  local panel_x = rect.x + 8
  local panel_y = rect.y + 8
  local panel_w = rect.w - 16
  local panel_h = rect.h - 50

  love.graphics.setColor(0.04, 0.06, 0.1, 1)
  love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h, 10, 10)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Population + Profit Explainer (" .. opts.mode_text .. ")", panel_x + 12, panel_y + 12, panel_w - 24, "left")

  local text_x = panel_x + 12
  local text_w = panel_w - 24
  local line_y = panel_y + 34
  local limit_y = panel_y + panel_h - 18
  local section_color = { 0.75, 0.87, 0.95, 1 }
  local body_color = { 1, 1, 1, 1 }

  line_y = draw_wrapped_line(
    "Population thresholds: Good <= " .. tostring(opts.terraforming_state.population_good_threshold) ..
      " => +1, Ok <= " .. tostring(opts.terraforming_state.population_ok_threshold) .. " => 0, Bad => -1.",
    text_x,
    line_y,
    text_w,
    section_color,
    16
  )
  if line_y > limit_y then
    return
  end

  line_y = draw_wrapped_line("Population math terms:", text_x, line_y + 2, text_w, section_color, 16)
  if line_y > limit_y then
    return
  end

  if opts.active_breakdown and opts.active_snapshot then
    for _, key in ipairs(opts.stat_order) do
      if line_y > limit_y then
        break
      end
      local value = opts.active_snapshot[key] or 0
      local target = opts.terraforming_state.targets[key] or 0
      local quality = opts.active_breakdown.quality[key]
      local score = opts.active_breakdown.scores[key]
      local line = opts.stat_labels[key] .. " " .. opts.format_signed(value) .. " vs target " .. opts.format_signed(target) ..
        " => " .. get_quality_label(quality) .. " (" .. opts.format_signed(score) .. ")"
      line_y = draw_wrapped_line(line, text_x, line_y, text_w, body_color, 16)
    end

    if line_y > limit_y then
      return
    end

    line_y = draw_wrapped_line(
      "DeltaPop = +1(base) + " .. opts.format_signed(opts.active_breakdown.primitive) ..
        "(primitive) + " .. opts.format_signed(opts.active_breakdown.synergy) .. "(synergy) = " ..
        opts.format_signed(opts.population_delta) .. ".",
      text_x,
      line_y + 2,
      text_w,
      body_color,
      16
    )
    if line_y > limit_y then
      return
    end

    line_y = draw_wrapped_line(
      "NextPopulation = " .. tostring(opts.current_population) .. " + (" .. opts.format_signed(opts.population_delta) ..
        ") = " .. tostring(opts.active_population) .. ".",
      text_x,
      line_y,
      text_w,
      body_color,
      16
    )
  end

  if line_y > limit_y then
    return
  end

  line_y = draw_wrapped_line("Profit math terms:", text_x, line_y + 6, text_w, section_color, 16)
  if line_y > limit_y then
    return
  end

  if opts.industry_report then
    local terms = {}
    for i = 1, opts.slot_count do
      if line_y > limit_y then
        break
      end
      local report = opts.industry_report[i]
      local line
      local color = body_color
      if report and not report.empty then
        local income = report.income or 0
        if report.destroyed then
          line = "Slot " .. tostring(i) .. ": destroyed this turn => income 0."
          color = { 0.98, 0.62, 0.58, 1 }
          table.insert(terms, "S" .. tostring(i) .. " 0")
        else
          line = "Slot " .. tostring(i) .. ": " .. tostring(report.name) ..
            ", HP " .. tostring(report.before_health) .. "->" .. tostring(report.after_health) ..
            ", income " .. opts.format_signed(income) .. "."
          if report.damage and report.damage > 0 then
            line = line .. " Damage " .. tostring(report.damage)
          end
          if report.reasons and #report.reasons > 0 then
            line = line .. " (" .. table.concat(report.reasons, ", ") .. ")"
          end
          table.insert(terms, "S" .. tostring(i) .. " " .. opts.format_signed(income))
        end
      else
        line = "Slot " .. tostring(i) .. ": open => income 0."
        color = { 0.62, 0.72, 0.84, 1 }
        table.insert(terms, "S" .. tostring(i) .. " 0")
      end
      line_y = draw_wrapped_line(line, text_x, line_y, text_w, color, 16)
    end

    if line_y > limit_y then
      return
    end

    line_y = draw_wrapped_line(
      "DeltaProfit = " .. table.concat(terms, " + ") .. " = " .. opts.format_signed(opts.profit_delta) .. ".",
      text_x,
      line_y + 2,
      text_w,
      body_color,
      16
    )
    if line_y > limit_y then
      return
    end

    draw_wrapped_line(
      "NextProfit = " .. tostring(opts.current_profit) .. " + (" .. opts.format_signed(opts.profit_delta) ..
        ") = " .. tostring(opts.active_profit) .. ".",
      text_x,
      line_y,
      text_w,
      body_color,
      16
    )
  else
    line_y = draw_wrapped_line(
      "No end-turn profit projection in Current mode. Pick Do Nothing or Selected Card to compute DeltaProfit.",
      text_x,
      line_y,
      text_w,
      body_color,
      16
    )
    if line_y > limit_y then
      return
    end
    draw_wrapped_line(
      "Current slots: installed industries are listed in the objective panel; projected slot income terms appear once a forecast mode is chosen.",
      text_x,
      line_y,
      text_w,
      body_color,
      16
    )
  end
end

function ObjectivesPanel.draw(opts)
  local rect = opts.rect
  local forecast_ctx = opts.forecast_ctx
  local mode_text = opts.get_forecast_mode_label(forecast_ctx.active_mode)
  local active_snapshot = forecast_ctx.active_snapshot
  local active_summary = forecast_ctx.active_summary
  local current_population = forecast_ctx.current_economy.population
  local current_profit = forecast_ctx.current_economy.profit
  local active_population = forecast_ctx.active_economy.population
  local active_profit = forecast_ctx.active_economy.profit
  local magnetosphere_level = opts.terraforming_state:get_magnetosphere_level()
  local magnetosphere_tier = opts.terraforming_state:get_magnetosphere_tier(magnetosphere_level)
  local slot_count = opts.terraforming_state:get_industry_slot_count()
  local active_industries = forecast_ctx.active_economy.industries or {}
  local current_breakdown = build_population_snapshot_breakdown(opts.terraforming_state, opts.stat_order, opts.terraforming_state.stats or {})
  local active_breakdown = build_population_snapshot_breakdown(opts.terraforming_state, opts.stat_order, active_snapshot or {})
  local population_delta = active_summary and (active_summary.population_delta or active_breakdown.delta) or active_breakdown.delta
  local profit_delta = active_summary and (active_summary.profit_delta or 0) or 0
  local industry_report = active_summary and active_summary.industry_report or nil
  local profit_breakdown = build_profit_snapshot_breakdown(active_summary, slot_count)
  local profit_flow = calculate_profit_flow_totals(active_industries, profit_breakdown, active_population, slot_count)
  local projected_profit_gain = profit_breakdown and profit_delta or profit_flow.income_total
  local explain_button = opts.get_objectives_explain_button(opts.layout)

  love.graphics.setColor(0.06, 0.08, 0.12, 1)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 10, 10)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("End Objectives", rect.x + 14, rect.y + 12, rect.w - 28, "left")
  love.graphics.setColor(0.75, 0.87, 0.95, 1)
  love.graphics.printf(
    "Mode: " .. mode_text ..
      "  |  Hab " .. tostring(opts.terraforming_state.habitability) .. "/" .. tostring(opts.terraforming_state.goal) ..
      "  |  Mag L" .. tostring(magnetosphere_level) .. " " .. magnetosphere_tier,
    rect.x + 14,
    rect.y + 34,
    rect.w - 28,
    "left"
  )

  local primitive_header_y = rect.y + 56
  local tile_gap = 8
  local tile_w = math.floor((rect.w - 28 - (tile_gap * 3)) / 4)
  local tile_h = 52
  local tile_y = primitive_header_y + 16

  love.graphics.setColor(0.75, 0.87, 0.95, 1)
  love.graphics.printf("Primitive Status (-1 / 0 / +1)", rect.x + 14, primitive_header_y, rect.w - 28, "left")
  for i, key in ipairs(opts.stat_order) do
    local tile_x = rect.x + 14 + ((i - 1) * (tile_w + tile_gap))
    local current_score = current_breakdown.scores[key]
    local active_score = active_breakdown.scores[key]
    local active_quality = active_breakdown.quality[key]
    local border_color, fill_color = get_score_color(active_score)
    love.graphics.setColor(unpack(fill_color))
    love.graphics.rectangle("fill", tile_x, tile_y, tile_w, tile_h, 8, 8)
    love.graphics.setColor(unpack(border_color))
    love.graphics.rectangle("line", tile_x, tile_y, tile_w, tile_h, 8, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(opts.stat_labels[key], tile_x + 6, tile_y + 5, tile_w - 12, "center")
    love.graphics.printf("Now " .. opts.format_signed(active_score) .. " " .. get_quality_label(active_quality), tile_x + 6, tile_y + 20, tile_w - 12, "center")
    local score_text = "From " .. opts.format_signed(current_score)
    if active_score ~= current_score then
      score_text = score_text .. " -> " .. opts.format_signed(active_score)
    end
    love.graphics.printf(score_text, tile_x + 6, tile_y + 35, tile_w - 12, "center")
  end

  local bars_y = tile_y + tile_h + 10
  draw_end_objective_metric_graph(rect, bars_y, "Population", current_population, active_population, { 0.35, 0.66, 0.42 }, opts.format_signed, opts.clamp_value)
  draw_end_objective_metric_graph(rect, bars_y + 48, "Profit", current_profit, active_profit, { 0.66, 0.56, 0.24 }, opts.format_signed, opts.clamp_value)

  local flow_title_y = bars_y + 90
  love.graphics.setColor(0.75, 0.87, 0.95, 1)
  love.graphics.printf("Profit Flow", rect.x + 14, flow_title_y, rect.w - 28, "left")

  local flow_gap = 8
  local flow_box_w = math.floor((rect.w - 28 - (flow_gap * 2)) / 3)
  local flow_box_h = 40
  local flow_y = flow_title_y + 16
  local flow_x = rect.x + 14

  local flow_labels = {
    { title = "Population Bonus", value = opts.format_signed(profit_flow.pop_bonus_total) },
    { title = "Industry Base", value = opts.format_signed(profit_flow.base_total) },
    { title = "Projected Profit Gain", value = opts.format_signed(projected_profit_gain) }
  }

  for i, item in ipairs(flow_labels) do
    local box_x = flow_x + ((i - 1) * (flow_box_w + flow_gap))
    local fill = { 0.12, 0.16, 0.22, 1 }
    local border = { 0.58, 0.72, 0.9, 1 }
    if i == 3 then
      fill = item.value:sub(1, 1) == "-" and { 0.24, 0.13, 0.13, 1 } or { 0.12, 0.23, 0.15, 1 }
      border = item.value:sub(1, 1) == "-" and { 0.9, 0.5, 0.45, 1 } or { 0.62, 0.9, 0.6, 1 }
    end
    love.graphics.setColor(unpack(fill))
    love.graphics.rectangle("fill", box_x, flow_y, flow_box_w, flow_box_h, 7, 7)
    love.graphics.setColor(unpack(border))
    love.graphics.rectangle("line", box_x, flow_y, flow_box_w, flow_box_h, 7, 7)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(item.title, box_x + 6, flow_y + 7, flow_box_w - 12, "center")
    love.graphics.printf(item.value, box_x + 6, flow_y + 22, flow_box_w - 12, "center")
  end

  for i = 1, 2 do
    local left_x = flow_x + (i * flow_box_w) + ((i - 1) * flow_gap)
    local right_x = left_x + flow_gap
    local arrow_y = flow_y + math.floor(flow_box_h * 0.5)
    love.graphics.setColor(0.72, 0.82, 0.96, 1)
    love.graphics.setLineWidth(2)
    love.graphics.line(left_x + 2, arrow_y, right_x - 8, arrow_y)
    love.graphics.polygon("fill", right_x - 8, arrow_y - 4, right_x - 8, arrow_y + 4, right_x - 2, arrow_y)
    love.graphics.setLineWidth(1)
  end

  local slot_gap = 8
  local slot_w = math.floor((rect.w - 28 - ((slot_count - 1) * slot_gap)) / slot_count)
  local slot_h = 44
  local slot_target_y = flow_y + flow_box_h + 30
  local slot_max_y = explain_button.y - 8 - slot_h
  local slot_y = math.min(slot_target_y, slot_max_y)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Industry Slots (income per turn)", rect.x + 14, slot_y - 18, rect.w - 28, "left")
  for i = 1, opts.terraforming_state:get_industry_slot_count() do
    local slot_x = rect.x + 14 + ((i - 1) * (slot_w + slot_gap))
    local industry = active_industries[i]
    local term = profit_breakdown and profit_breakdown.terms and profit_breakdown.terms[i] or nil
    local fill = { 0.08, 0.1, 0.14, 1 }
    local border = { 0.48, 0.58, 0.7, 1 }
    if industry then
      local hp_ratio = industry.health / math.max(1, industry.max_health)
      if hp_ratio <= 0.34 then
        fill = { 0.24, 0.12, 0.12, 1 }
        border = { 0.86, 0.45, 0.4, 1 }
      elseif hp_ratio <= 0.67 then
        fill = { 0.24, 0.2, 0.1, 1 }
        border = { 0.93, 0.75, 0.42, 1 }
      else
        fill = { 0.12, 0.22, 0.15, 1 }
        border = { 0.62, 0.9, 0.6, 1 }
      end
    else
      fill = { 0.08, 0.1, 0.14, 1 }
      border = { 0.45, 0.55, 0.68, 1 }
    end

    love.graphics.setColor(unpack(fill))
    love.graphics.rectangle("fill", slot_x, slot_y, slot_w, slot_h, 8, 8)
    love.graphics.setColor(unpack(border))
    love.graphics.rectangle("line", slot_x, slot_y, slot_w, slot_h, 8, 8)

    love.graphics.setColor(1, 1, 1, 1)
    if industry then
      local base_income = industry.base_profit or 0
      local income_value
      if term and term.income ~= nil then
        income_value = term.income
      else
        local pop_bonus = math.floor((active_population or current_population) * (industry.population_factor or 0) + 0.5)
        income_value = base_income + pop_bonus
      end
      local pop_bonus_value = income_value - base_income
      local name_text = industry.name
      if #name_text > 18 then
        name_text = string.sub(name_text, 1, 17) .. "..."
      end
      local line_1 = fit_single_line(tostring(i) .. ". " .. name_text, slot_w - 12)
      local line_2 = fit_single_line(
        "Inc " .. opts.format_signed(income_value) .. "/turn (B " ..
          opts.format_signed(base_income) .. ", P " .. opts.format_signed(pop_bonus_value) .. ")",
        slot_w - 12
      )
      love.graphics.printf(line_1, slot_x + 6, slot_y + 8, slot_w - 12, "left")
      love.graphics.printf(line_2, slot_x + 6, slot_y + 28, slot_w - 12, "left")
    else
      local destroyed = industry_report and industry_report[i] and industry_report[i].destroyed
      love.graphics.setColor(destroyed and 0.98 or 0.75, destroyed and 0.55 or 0.87, destroyed and 0.52 or 0.95, 1)
      local line_1 = fit_single_line(tostring(i) .. ". " .. (destroyed and "Destroyed" or "Open"), slot_w - 12)
      love.graphics.printf(line_1, slot_x + 6, slot_y + 8, slot_w - 12, "left")
      love.graphics.printf("Income +0 / turn", slot_x + 6, slot_y + 28, slot_w - 12, "left")
    end
  end

  if opts.influence_ui.show_objectives_explain then
    draw_end_objectives_explain_overlay({
      rect = rect,
      mode_text = mode_text,
      current_breakdown = current_breakdown,
      active_breakdown = active_breakdown,
      current_population = current_population,
      active_population = active_population,
      current_profit = current_profit,
      active_profit = active_profit,
      profit_delta = profit_delta,
      active_snapshot = active_snapshot,
      industry_report = industry_report,
      slot_count = slot_count,
      stat_order = opts.stat_order,
      stat_labels = opts.stat_labels,
      format_signed = opts.format_signed,
      terraforming_state = opts.terraforming_state
    })
  end

  local explain_fill = opts.influence_ui.show_objectives_explain and { 0.24, 0.42, 0.26, 1 } or { 0.13, 0.18, 0.25, 1 }
  if opts.influence_ui.hovered_objectives_explain_button and not opts.influence_ui.show_objectives_explain then
    explain_fill = { 0.18, 0.24, 0.33, 1 }
  end
  local explain_border = opts.influence_ui.show_objectives_explain and { 0.65, 0.95, 0.64, 1 } or { 0.62, 0.78, 0.95, 1 }
  love.graphics.setColor(unpack(explain_fill))
  love.graphics.rectangle("fill", explain_button.x, explain_button.y, explain_button.w, explain_button.h, 7, 7)
  love.graphics.setColor(unpack(explain_border))
  love.graphics.rectangle("line", explain_button.x, explain_button.y, explain_button.w, explain_button.h, 7, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(opts.influence_ui.show_objectives_explain and "Hide Objectives" or "Explain Objectives", explain_button.x + 4, explain_button.y + 6, explain_button.w - 8, "center")
end

return ObjectivesPanel
