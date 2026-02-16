local GameplayHUD = {}

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

local function draw_industry_grid(opts)
  local start_x = opts.start_x
  local start_y = opts.start_y
  local economy = opts.economy
  local state = opts.terraforming_state
  local cell_w = 158
  local cell_h = 58
  local col_gap = 8
  local row_gap = 8
  local header_h = 20
  local slots = state:get_industry_slot_count()

  love.graphics.setColor(0.75, 0.87, 0.95, 1)
  love.graphics.print("Industry Slots", start_x, start_y)

  for i = 1, slots do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local x = start_x + (col * (cell_w + col_gap))
    local y = start_y + header_h + (row * (cell_h + row_gap))
    local industry = economy.industries[i]

    local fill = { 0.08, 0.1, 0.14, 0.95 }
    local border = { 0.48, 0.58, 0.7, 1 }
    if industry then
      local hp_ratio = (industry.health or 0) / math.max(1, industry.max_health or 1)
      if hp_ratio <= 0.34 then
        fill = { 0.24, 0.12, 0.12, 0.95 }
        border = { 0.86, 0.45, 0.4, 1 }
      elseif hp_ratio <= 0.67 then
        fill = { 0.22, 0.18, 0.1, 0.95 }
        border = { 0.93, 0.75, 0.42, 1 }
      else
        fill = { 0.12, 0.22, 0.15, 0.95 }
        border = { 0.62, 0.9, 0.6, 1 }
      end
    end

    love.graphics.setColor(unpack(fill))
    love.graphics.rectangle("fill", x, y, cell_w, cell_h, 8, 8)
    love.graphics.setColor(unpack(border))
    love.graphics.rectangle("line", x, y, cell_w, cell_h, 8, 8)

    if industry then
      local base = industry.base_profit or 0
      local pop_bonus = math.floor((economy.population or 0) * (industry.population_factor or 0) + 0.5)
      local income = base + pop_bonus
      local line_1 = fit_single_line(tostring(i) .. ". " .. tostring(industry.name or "Industry"), cell_w - 12)
      local line_2 = "HP " .. tostring(industry.health or 0) .. "/" .. tostring(industry.max_health or 0)
      local line_3 = "Income " .. opts.format_signed(income) .. "/t"
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.printf(line_1, x + 6, y + 7, cell_w - 12, "left")
      love.graphics.printf(line_2, x + 6, y + 24, cell_w - 12, "left")
      love.graphics.printf(line_3, x + 6, y + 40, cell_w - 12, "left")
    else
      love.graphics.setColor(0.75, 0.87, 0.95, 1)
      love.graphics.printf(tostring(i) .. ". Open", x + 6, y + 11, cell_w - 12, "left")
      love.graphics.printf("Income +0/t", x + 6, y + 33, cell_w - 12, "left")
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
  return start_y + header_h + (cell_h * 2) + row_gap
end

function GameplayHUD.draw_hud(opts)
  local safe = opts.safe_rect
  local hud_x = safe.x + 4
  local header_y = safe.y
  local config = opts.world_config
  local hazard_projection = opts.hazard_projection
  local hazard = hazard_projection.hazard or opts.terraforming_state:get_next_hazard()
  local economy = opts.economy_snapshot
  local magnetosphere_level = opts.terraforming_state:get_magnetosphere_level()
  local magnetosphere_tier = opts.terraforming_state:get_magnetosphere_tier(magnetosphere_level)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("World " .. opts.world_index .. "/" .. opts.world_count .. ": " .. config.name .. " (" .. config.tier .. ")", hud_x, header_y)
  love.graphics.print(
    "Turn: " .. opts.terraforming_state.turn .. "/" .. opts.terraforming_state.turn_limit ..
      "    Habitability: " .. opts.terraforming_state.habitability .. "/" .. opts.terraforming_state.goal,
    hud_x,
    header_y + 20
  )
  if hazard.magnetosphere_blockable then
    love.graphics.setColor(0.7, 0.9, 1, 1)
    love.graphics.print(
      "Magnetosphere L" .. tostring(magnetosphere_level) .. " (" .. magnetosphere_tier .. ") blocks " ..
        tostring(magnetosphere_level) .. "/stat -> " .. opts.format_delta_list(hazard_projection.effective_deltas),
      hud_x,
      header_y + 40
    )
  else
    love.graphics.setColor(0.9, 0.8, 0.42, 1)
    love.graphics.print(
      "Magnetosphere L" .. tostring(magnetosphere_level) .. " (" .. magnetosphere_tier ..
        ") has no effect on this " .. string.lower(opts.get_hazard_origin_label(hazard.origin)) .. " hazard.",
      hud_x,
      header_y + 40
    )
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("Population: " .. tostring(economy.population) .. "    Profit: " .. tostring(economy.profit), hud_x, header_y + 60)

  local industry_y = header_y + 86
  local industry_bottom_y = draw_industry_grid({
    start_x = hud_x,
    start_y = industry_y,
    economy = economy,
    terraforming_state = opts.terraforming_state,
    format_signed = opts.format_signed
  })

  if opts.turn_summary then
    local turn_summary = opts.turn_summary
    local summary_y = industry_bottom_y + 16
    love.graphics.print(
      "Last Turn Hazard: " .. turn_summary.hazard .. " [" .. tostring(turn_summary.hazard_category or "Hazard") .. "]",
      hud_x,
      summary_y
    )
    love.graphics.print(
      "Last Turn Raw (pre-magnetosphere): " .. opts.format_delta_list(turn_summary.hazard_raw_deltas or turn_summary.hazard_deltas),
      hud_x,
      summary_y + 20
    )
    if turn_summary.hazard_blockable then
      love.graphics.print(
        "Last Turn Applied (post-magnetosphere): " .. opts.format_delta_list(turn_summary.hazard_deltas) ..
          "  [Blocked " .. opts.format_delta_list(turn_summary.hazard_blocked_deltas) .. "]",
        hud_x,
        summary_y + 40
      )
      summary_y = summary_y + 20
    else
      love.graphics.print("Last Turn Applied (post-magnetosphere): " .. opts.format_delta_list(turn_summary.hazard_deltas), hud_x, summary_y + 40)
    end
    love.graphics.print("Coupling Delta: " .. opts.format_delta_list(turn_summary.coupling_deltas), hud_x, summary_y + 60)
    love.graphics.print(
      "Growth " .. turn_summary.growth .. " - Penalty " .. turn_summary.penalty .. " = Net " .. opts.format_signed(turn_summary.net),
      hud_x,
      summary_y + 80
    )
    love.graphics.print(
      "Population " .. opts.format_signed(turn_summary.population_delta or 0) ..
        " -> " .. tostring(turn_summary.projected_population or opts.terraforming_state.population) ..
        " | Profit " .. opts.format_signed(turn_summary.profit_delta or 0) ..
        " -> " .. tostring(turn_summary.projected_profit or opts.terraforming_state.profit),
      hud_x,
      summary_y + 100
    )
  end
end

function GameplayHUD.draw_controls_hint(opts)
  local y = opts.hand_base_y - 48
  local safe = opts.safe_rect
  y = opts.clamp_value(y, safe.y + 12, safe.y + safe.h - 30)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print(
    "Controls: Click card | E end turn | V influence map | R restart",
    safe.x + 4,
    y
  )
end

function GameplayHUD.draw_status_overlay(opts)
  local width = opts.screen_w
  local box_w = 620
  local box_h = 130
  local box_x = (width - box_w) / 2
  local box_y = 140

  love.graphics.setColor(0.05, 0.05, 0.08, 0.85)
  love.graphics.rectangle("fill", box_x, box_y, box_w, box_h, 8, 8)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("line", box_x, box_y, box_w, box_h, 8, 8)

  if opts.campaign_state == "world_won" then
    love.graphics.printf("World Terraformed!", box_x, box_y + 24, box_w, "center")
    love.graphics.printf("Press N for the next world.", box_x, box_y + 56, box_w, "center")
  elseif opts.campaign_state == "campaign_won" then
    love.graphics.printf("Campaign Complete", box_x, box_y + 24, box_w, "center")
    love.graphics.printf("You terraformed all worlds. Press R to restart.", box_x, box_y + 56, box_w, "center")
  elseif opts.campaign_state == "campaign_lost" then
    love.graphics.printf("Terraforming Failed", box_x, box_y + 24, box_w, "center")
    love.graphics.printf("Turn limit reached before habitability target. Press R to restart.", box_x, box_y + 56, box_w, "center")
  end
end

return GameplayHUD
