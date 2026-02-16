local GameplayHUD = {}

local function draw_stats(opts)
  local base_x = opts.start_x or 10
  local base_y = opts.start_y or 110
  local line_height = opts.show_real_world_values and 36 or 22

  for i, key in ipairs(opts.stat_order) do
    local value = opts.terraforming_state.stats[key]
    local target_value = opts.terraforming_state.targets[key]
    local status, color = opts.get_stat_status(key, value)
    local y = base_y + (i - 1) * line_height

    love.graphics.setColor(unpack(color))
    love.graphics.print(
      opts.stat_labels[key] .. ": " .. opts.format_signed(value) .. " / target " .. opts.format_signed(target_value) .. "  [" .. status .. "]",
      base_x,
      y
    )

    if opts.show_real_world_values then
      love.graphics.setColor(0.75, 0.84, 0.95, 1)
      love.graphics.print("    " .. opts.get_real_world_mapping(key, value), base_x, y + 16)
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
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

  local stats_start_y = header_y + 80
  draw_stats({
    start_y = stats_start_y,
    start_x = hud_x,
    show_real_world_values = opts.show_real_world_values,
    stat_order = opts.stat_order,
    stat_labels = opts.stat_labels,
    terraforming_state = opts.terraforming_state,
    get_stat_status = opts.get_stat_status,
    format_signed = opts.format_signed,
    get_real_world_mapping = opts.get_real_world_mapping
  })
  local line_height = opts.show_real_world_values and 36 or 22
  local stats_bottom_y = stats_start_y + (#opts.stat_order * line_height)
  local industry_y = stats_bottom_y + 12

  local slot_parts = {}
  for i = 1, opts.terraforming_state:get_industry_slot_count() do
    local industry = economy.industries[i]
    if industry then
      table.insert(slot_parts, tostring(i) .. ":" .. industry.name .. " " .. tostring(industry.health) .. "/" .. tostring(industry.max_health))
    else
      table.insert(slot_parts, tostring(i) .. ":Open")
    end
  end
  love.graphics.print("Industry Slots: " .. table.concat(slot_parts, " | "), hud_x, industry_y)

  if opts.turn_summary then
    local turn_summary = opts.turn_summary
    local summary_y = industry_y + 38
    love.graphics.print(
      "Last Turn Hazard: " .. turn_summary.hazard .. " [" .. tostring(turn_summary.hazard_category or "Hazard") .. "]",
      hud_x,
      summary_y
    )
    love.graphics.print(
      "Hazard Raw: " .. opts.format_delta_list(turn_summary.hazard_raw_deltas or turn_summary.hazard_deltas),
      hud_x,
      summary_y + 20
    )
    if turn_summary.hazard_blockable then
      love.graphics.print(
        "Magnetosphere Block: " .. opts.format_delta_list(turn_summary.hazard_blocked_deltas) ..
          " -> Applied " .. opts.format_delta_list(turn_summary.hazard_deltas),
        hud_x,
        summary_y + 40
      )
      summary_y = summary_y + 20
    else
      love.graphics.print("Applied Hazard Delta: " .. opts.format_delta_list(turn_summary.hazard_deltas), hud_x, summary_y + 40)
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
    "Controls: Click card | E end turn | V influence map | M real-world mapping | R restart",
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
