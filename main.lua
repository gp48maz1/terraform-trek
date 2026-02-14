local Deck = require("deck")
local TerraformingTarget = require("terraforming_target")
local DrawHelpers = require("draw_helpers")
local Background = require("background")
local TerraformingState = require("terraforming_state")

local STAT_ORDER = { "heat", "air", "water", "soil" }
local STAT_LABELS = {
  heat = "Heat",
  air = "Air",
  water = "Water",
  soil = "Soil"
}

local INFLUENCE_EDGES = {
  { source = "heat", target = "water", factor = -1, text = "Heat -> Water (-)", curve = 0 },
  { source = "heat", target = "soil", factor = -1, text = "Heat -> Soil (-)", curve = 0 },
  { source = "air", target = "heat", factor = 1, text = "Air -> Heat (+)", curve = 0 },
  { source = "air", target = "water", factor = 1, text = "Air -> Water (+)", curve = -34 },
  { source = "water", target = "soil", factor = 1, text = "Water -> Soil (+)", curve = 0 },
  { source = "water", target = "air", factor = 1, text = "Water -> Air (+)", curve = 34 },
  { source = "soil", target = "air", factor = 1, text = "Soil -> Air (+)", curve = 0 }
}

local INFLUENCE_HELP = {
  heat = {
    summary = "Heat is bipolar: too low freezes systems, too high scorches systems.",
    incoming = "Air drives Heat in the same direction when Air is extreme.",
    outgoing = {
      "Heat influences Water in the opposite direction.",
      "Heat influences Soil in the opposite direction."
    }
  },
  air = {
    summary = "Air is one-directional health: very negative is toxic/thin, zero is ideal.",
    incoming = "Water and Soil both influence Air in the same direction.",
    outgoing = {
      "Air influences Heat in the same direction.",
      "Air influences Water in the same direction."
    }
  },
  water = {
    summary = "Water is bipolar: very negative means ice lock, very positive means steam lock.",
    incoming = "Heat and Air both influence Water.",
    outgoing = {
      "Water influences Soil in the same direction.",
      "Water influences Air in the same direction."
    }
  },
  soil = {
    summary = "Soil is one-directional health: very negative is sterile regolith, zero is ideal.",
    incoming = "Heat and Water both influence Soil.",
    outgoing = {
      "Soil influences Air in the same direction."
    }
  }
}

local WORLD_CONFIGS = {
  {
    name = "Dustbound Expanse",
    tier = "Low Threat",
    goal = 20,
    turn_limit = 10,
    hazard_strength = 1,
    targets = { heat = 0, air = 0, water = 0, soil = 0 },
    starting_ranges = {
      heat = { min = -4, max = 4 },
      air = { min = -6, max = -1 },
      water = { min = -4, max = 4 },
      soil = { min = -6, max = -1 }
    }
  },
  {
    name = "Iron Tempest",
    tier = "Elite",
    goal = 24,
    turn_limit = 10,
    hazard_strength = 1,
    targets = { heat = 0, air = 0, water = 0, soil = 0 },
    starting_ranges = {
      heat = { min = -6, max = 6 },
      air = { min = -8, max = -2 },
      water = { min = -6, max = 6 },
      soil = { min = -8, max = -2 }
    }
  },
  {
    name = "Abyssal Crown",
    tier = "Boss",
    goal = 28,
    turn_limit = 11,
    hazard_strength = 2,
    targets = { heat = 0, air = 0, water = 0, soil = 0 },
    starting_ranges = {
      heat = { min = -8, max = 8 },
      air = { min = -10, max = -3 },
      water = { min = -8, max = 8 },
      soil = { min = -10, max = -3 }
    }
  }
}

local player_deck
local target
local terraforming_state
local world_index = 1
local campaign_state = "playing" -- playing | world_won | campaign_won | campaign_lost
local turn_summary = nil
local view_mode = "gameplay" -- gameplay | influence
local show_real_world_values = false
local focused_stat = "heat"
local selected_forecast_card_index = nil

local hovered_card_index = nil
local hovered_draw_pile = false
local hovered_discard_pile = false
local hovered_end_turn = false
local hovered_influence_stat = nil
local hovered_forecast_card_index = nil

local max_energy = 3
local current_energy = 0

local HAND_UI = {
  card_width = 150,
  card_height = 225,
  card_spacing = 175,
  max_angle_degrees = 10,
  pixel_offset_per_step = 20,
  base_y = 430
}

local PILE_UI = {
  x_padding = 30,
  y = 340,
  width = 110,
  height = 150
}

local END_TURN_UI = {
  width = 170,
  height = 50,
  x_padding = 30,
  y = 520
}

local function copy_stats(source)
  local out = {}
  for _, key in ipairs(STAT_ORDER) do
    out[key] = source[key]
  end
  return out
end

local function safe_atan2(y, x)
  if math.atan2 then
    return math.atan2(y, x)
  end

  if x > 0 then
    return math.atan(y / x)
  elseif x < 0 and y >= 0 then
    return math.atan(y / x) + math.pi
  elseif x < 0 and y < 0 then
    return math.atan(y / x) - math.pi
  elseif x == 0 and y > 0 then
    return math.pi / 2
  elseif x == 0 and y < 0 then
    return -math.pi / 2
  end

  return 0
end

local function format_signed(value)
  if value > 0 then
    return "+" .. tostring(value)
  end
  return tostring(value)
end

local function point_in_rect(px, py, rx, ry, rw, rh)
  return px >= rx and px <= rx + rw and py >= ry and py <= ry + rh
end

local function point_in_circle(px, py, cx, cy, radius)
  local dx = px - cx
  local dy = py - cy
  return (dx * dx + dy * dy) <= radius * radius
end

local function reset_energy()
  current_energy = max_energy
end

local function can_afford(cost)
  return current_energy >= (cost or 0)
end

local function spend_energy(cost)
  current_energy = current_energy - (cost or 0)
end

local function sanitize_selection()
  if selected_forecast_card_index and selected_forecast_card_index > #player_deck.hand then
    selected_forecast_card_index = nil
  end
end

local function get_stat_status(stat, value)
  if stat == "heat" then
    if value <= -7 then
      return "Deep Freeze", { 0.45, 0.72, 1.0, 1 }
    elseif value <= -3 then
      return "Cold", { 0.63, 0.8, 1.0, 1 }
    elseif value <= 2 then
      return "Temperate", { 0.45, 0.92, 0.48, 1 }
    elseif value <= 6 then
      return "Hot", { 0.98, 0.8, 0.36, 1 }
    end
    return "Scorching", { 0.97, 0.4, 0.4, 1 }
  end

  if stat == "water" then
    if value <= -7 then
      return "Ice Shell", { 0.45, 0.72, 1.0, 1 }
    elseif value <= -3 then
      return "Frozen", { 0.63, 0.8, 1.0, 1 }
    elseif value <= 2 then
      return "Liquid Cycle", { 0.45, 0.92, 0.48, 1 }
    elseif value <= 6 then
      return "Humid / Steam", { 0.98, 0.8, 0.36, 1 }
    end
    return "Steam Lock", { 0.97, 0.4, 0.4, 1 }
  end

  if stat == "air" then
    if value <= -8 then
      return "Toxic / Thin", { 0.97, 0.4, 0.4, 1 }
    elseif value <= -5 then
      return "Unstable", { 0.98, 0.8, 0.36, 1 }
    elseif value <= -2 then
      return "Recovering", { 0.72, 0.88, 0.48, 1 }
    end
    return "Breathable", { 0.45, 0.92, 0.48, 1 }
  end

  if value <= -8 then
    return "Sterile", { 0.97, 0.4, 0.4, 1 }
  elseif value <= -5 then
    return "Depleted", { 0.98, 0.8, 0.36, 1 }
  elseif value <= -2 then
    return "Recovering", { 0.72, 0.88, 0.48, 1 }
  end
  return "Fertile", { 0.45, 0.92, 0.48, 1 }
end

local function get_real_world_mapping(stat, value)
  if stat == "heat" then
    local c = value * 20
    local f = math.floor((c * 9 / 5) + 32 + 0.5)
    return string.format("~%d C / %d F mean surface temperature", c, f)
  end

  if stat == "water" then
    local eq_c = value * 15
    if value <= -3 then
      return string.format("Ice-dominant hydrosphere (~%d C equivalent)", eq_c)
    elseif value >= 4 then
      return string.format("Steam-heavy hydrosphere (~%d C equivalent)", eq_c)
    end
    return string.format("Liquid-cycle dominant (~%d C equivalent)", eq_c)
  end

  if stat == "air" then
    local pressure = math.floor((5 + ((value + 10) / 10) * 96) + 0.5)
    local oxygen = math.floor((4 + ((value + 10) / 10) * 17) * 10 + 0.5) / 10
    return string.format("~%d kPa pressure, ~%.1f%% oxygen potential", pressure, oxygen)
  end

  local fertility = math.floor(((value + 10) / 10) * 100 + 0.5)
  return string.format("Soil fertility index %d / 100", fertility)
end

local function format_delta_list(deltas)
  local parts = {}
  for _, key in ipairs(STAT_ORDER) do
    local delta = (deltas and deltas[key]) or 0
    if delta ~= 0 then
      table.insert(parts, STAT_LABELS[key] .. " " .. format_signed(delta))
    end
  end

  if #parts == 0 then
    return "None"
  end

  return table.concat(parts, "  ")
end

local function get_hand_layout(num_cards)
  local total_hand_width = 0
  if num_cards > 0 then
    total_hand_width = HAND_UI.card_width + (num_cards - 1) * HAND_UI.card_spacing
  end
  local start_x = (love.graphics.getWidth() - total_hand_width) / 2
  return { start_x = start_x, base_y = HAND_UI.base_y }
end

local function get_draw_pile_rect()
  return {
    x = PILE_UI.x_padding,
    y = PILE_UI.y,
    w = PILE_UI.width,
    h = PILE_UI.height
  }
end

local function get_discard_pile_rect()
  return {
    x = love.graphics.getWidth() - PILE_UI.x_padding - PILE_UI.width,
    y = PILE_UI.y,
    w = PILE_UI.width,
    h = PILE_UI.height
  }
end

local function get_end_turn_rect()
  return {
    x = love.graphics.getWidth() - END_TURN_UI.x_padding - END_TURN_UI.width,
    y = END_TURN_UI.y,
    w = END_TURN_UI.width,
    h = END_TURN_UI.height
  }
end

local function get_card_index_at_position(mx, my)
  local hand = player_deck.hand
  local num_cards = #hand
  local layout = get_hand_layout(num_cards)

  for i = num_cards, 1, -1 do
    local card_x = layout.start_x + (i - 1) * HAND_UI.card_spacing
    local dy = DrawHelpers.calculate_vertical_offset(i, num_cards, HAND_UI.pixel_offset_per_step)
    local current_y = layout.base_y + dy

    if point_in_rect(mx, my, card_x, current_y, HAND_UI.card_width, HAND_UI.card_height) then
      return i
    end
  end

  return nil
end

local function get_influence_layout()
  local sw, sh = love.graphics.getDimensions()
  local map_rect = {
    x = 20,
    y = 84,
    w = math.floor(sw * 0.53),
    h = math.floor(sh * 0.56)
  }

  local map_center_x = map_rect.x + math.floor(map_rect.w * 0.5)
  local map_center_y = map_rect.y + math.floor(map_rect.h * 0.56)
  local offset_x = math.floor(map_rect.w * 0.29)
  local offset_y = math.floor(map_rect.h * 0.26)
  local node_radius = math.max(48, math.floor(math.min(map_rect.w, map_rect.h) * 0.11))

  local nodes = {
    heat = { x = map_center_x, y = map_center_y - offset_y, r = node_radius },
    water = { x = map_center_x + offset_x, y = map_center_y, r = node_radius },
    soil = { x = map_center_x, y = map_center_y + offset_y, r = node_radius },
    air = { x = map_center_x - offset_x, y = map_center_y, r = node_radius }
  }

  local right_x = map_rect.x + map_rect.w + 16
  local right_w = sw - right_x - 20
  local details_rect = {
    x = right_x,
    y = map_rect.y,
    w = right_w,
    h = math.floor(map_rect.h * 0.46)
  }

  local forecast_rect = {
    x = right_x,
    y = details_rect.y + details_rect.h + 14,
    w = right_w,
    h = map_rect.y + map_rect.h - (details_rect.y + details_rect.h + 14)
  }

  local cards_y = map_rect.y + map_rect.h + 14
  local cards_rect = {
    x = 20,
    y = cards_y,
    w = sw - 40,
    h = sh - cards_y - 14
  }

  return {
    map_rect = map_rect,
    nodes = nodes,
    details_rect = details_rect,
    forecast_rect = forecast_rect,
    cards_rect = cards_rect
  }
end

local function get_influence_card_rects(layout)
  local rows = {}
  local cards = player_deck.hand
  local rect = layout.cards_rect
  local card_w = 185
  local card_h = 58
  local gap_x = 12
  local gap_y = 10
  local cards_per_row = math.max(1, math.floor((rect.w - 20 + gap_x) / (card_w + gap_x)))
  local used_width = cards_per_row * card_w + (cards_per_row - 1) * gap_x
  local start_x = rect.x + math.floor((rect.w - used_width) / 2)

  for i, card in ipairs(cards) do
    local row = math.floor((i - 1) / cards_per_row)
    local col = (i - 1) % cards_per_row
    local x = start_x + col * (card_w + gap_x)
    local y = rect.y + 34 + row * (card_h + gap_y)
    rows[i] = { x = x, y = y, w = card_w, h = card_h, card = card }
  end

  return rows
end

local function setup_world(index)
  world_index = index
  local config = WORLD_CONFIGS[index]
  terraforming_state = TerraformingState.new(config)
  turn_summary = nil
  campaign_state = "playing"
  selected_forecast_card_index = nil
  focused_stat = "heat"

  player_deck:create_starter_deck()
  player_deck:draw(5)
  reset_energy()
end

local function start_campaign()
  setup_world(1)
end

local function end_turn()
  if campaign_state ~= "playing" then
    return
  end

  turn_summary = terraforming_state:end_turn()
  selected_forecast_card_index = nil

  if terraforming_state.status == "won" then
    if world_index == #WORLD_CONFIGS then
      campaign_state = "campaign_won"
    else
      campaign_state = "world_won"
    end
    return
  end

  if terraforming_state.status == "lost" then
    campaign_state = "campaign_lost"
    return
  end

  player_deck:discard_hand()
  player_deck:draw(5)
  reset_energy()
end

local function apply_card_to_snapshot(card, snapshot)
  if not card then
    return
  end

  if card.effect_fn_name == "apply_stat_changes" then
    terraforming_state:apply_stat_changes_to(card.properties.stat_changes or {}, snapshot)
  elseif card.effect_fn_name == "stabilize_system" then
    terraforming_state:adjust_snapshot_toward_targets(snapshot, 1)
  end
end

local function compute_forecasts(card_index)
  local base_summary = terraforming_state:forecast_end_turn(terraforming_state.stats)
  local scenario = nil

  if card_index then
    local card = player_deck.hand[card_index]
    if card then
      local snapshot = copy_stats(terraforming_state.stats)
      local affordable = can_afford(card.cost or 0)
      if affordable then
        apply_card_to_snapshot(card, snapshot)
      end
      scenario = {
        card = card,
        affordable = affordable,
        summary = terraforming_state:forecast_end_turn(snapshot)
      }
    end
  end

  return base_summary, scenario
end

local function get_edges_from_stat(stat_key)
  local edges = {}
  for _, edge in ipairs(INFLUENCE_EDGES) do
    if edge.source == stat_key then
      table.insert(edges, edge)
    end
  end
  return edges
end

local function get_edge_trigger_delta(edge, snapshot)
  local source_value = snapshot[edge.source]
  if math.abs(source_value) < terraforming_state.coupling_threshold then
    return 0
  end
  local source_sign = 0
  if source_value > 0 then
    source_sign = 1
  elseif source_value < 0 then
    source_sign = -1
  end
  return source_sign * edge.factor
end

local function compute_play_recommendations(limit)
  local recommendations = {}
  local baseline = terraforming_state:forecast_end_turn(terraforming_state.stats)
  local current_distance = math.abs(terraforming_state.stats[focused_stat] - terraforming_state.targets[focused_stat])

  for i, card in ipairs(player_deck.hand) do
    if can_afford(card.cost or 0) then
      local snapshot = copy_stats(terraforming_state.stats)
      apply_card_to_snapshot(card, snapshot)
      local summary = terraforming_state:forecast_end_turn(snapshot)
      local next_distance = math.abs(summary.projected_stats[focused_stat] - terraforming_state.targets[focused_stat])
      local focus_gain = current_distance - next_distance
      local net_gain = summary.net - baseline.net
      local score = net_gain * 10 + focus_gain

      table.insert(recommendations, {
        index = i,
        card = card,
        summary = summary,
        net_gain = net_gain,
        focus_gain = focus_gain,
        score = score
      })
    end
  end

  table.sort(recommendations, function(a, b)
    if a.score == b.score then
      if a.net_gain == b.net_gain then
        return a.focus_gain > b.focus_gain
      end
      return a.net_gain > b.net_gain
    end
    return a.score > b.score
  end)

  local cap = math.min(limit or 3, #recommendations)
  local output = {}
  for i = 1, cap do
    output[i] = recommendations[i]
  end
  return output
end

local function try_play_card(card_index)
  if campaign_state ~= "playing" then
    return false
  end

  local card_to_play = player_deck.hand[card_index]
  if not card_to_play then
    return false
  end

  local cost = card_to_play.cost or 0
  if not can_afford(cost) then
    return false
  end

  local context = {
    terraforming_state = terraforming_state,
    target = target
  }

  local played_card = player_deck:play_card(card_index, current_energy, context)
  if played_card then
    spend_energy(played_card.cost)
    selected_forecast_card_index = nil
    return true
  end

  return false
end

function love.load()
  love.math.setRandomSeed(os.time())
  Background.load()

  player_deck = Deck:new()
  target = TerraformingTarget:new()
  start_campaign()
end

local function draw_card_energy_overlay(card_x, card_y, angle_rad, scale)
  local overlay_scale = scale or 1
  love.graphics.setColor(0.42, 0.08, 0.08, 0.34)
  love.graphics.push()
  love.graphics.translate(card_x + HAND_UI.card_width / 2, card_y + HAND_UI.card_height / 2)
  love.graphics.scale(overlay_scale, overlay_scale)
  love.graphics.rotate(angle_rad)
  love.graphics.translate(-HAND_UI.card_width / 2, -HAND_UI.card_height / 2)
  love.graphics.rectangle("fill", 0, 0, HAND_UI.card_width, HAND_UI.card_height)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1, 1)
end

local function draw_hand()
  local hand = player_deck.hand
  local num_cards = #hand
  local layout = get_hand_layout(num_cards)
  local start_x = layout.start_x
  local base_y = layout.base_y

  for i, card in ipairs(hand) do
    if i ~= hovered_card_index then
      local card_x = start_x + (i - 1) * HAND_UI.card_spacing
      local angle_rad = DrawHelpers.calculate_card_angle(i, num_cards, HAND_UI.max_angle_degrees)
      local dy = DrawHelpers.calculate_vertical_offset(i, num_cards, HAND_UI.pixel_offset_per_step)

      DrawHelpers.draw_transformed_card(card, card_x, base_y, dy, angle_rad, HAND_UI.card_width, HAND_UI.card_height)
      local number_x = card_x + HAND_UI.card_width / 2 - 5
      local number_y = base_y + dy - 15
      love.graphics.print(i, number_x, number_y)

      local cost = card.cost or 0
      if cost > current_energy then
        draw_card_energy_overlay(card_x, base_y + dy, angle_rad, 1)
      end
    end
  end

  if hovered_card_index then
    local i = hovered_card_index
    local card = hand[i]
    local card_x = start_x + (i - 1) * HAND_UI.card_spacing
    local angle_rad = DrawHelpers.calculate_card_angle(i, num_cards, HAND_UI.max_angle_degrees)
    local dy = DrawHelpers.calculate_vertical_offset(i, num_cards, HAND_UI.pixel_offset_per_step)

    local hover_scale = 1.15
    local hover_y_offset = -40
    love.graphics.push()
    love.graphics.translate(card_x + HAND_UI.card_width / 2, base_y + dy + hover_y_offset + HAND_UI.card_height / 2)
    love.graphics.scale(hover_scale, hover_scale)
    love.graphics.rotate(angle_rad)
    love.graphics.translate(-HAND_UI.card_width / 2, -HAND_UI.card_height / 2)
    card:draw(0, 0)
    love.graphics.pop()

    if (card.cost or 0) > current_energy then
      draw_card_energy_overlay(card_x, base_y + dy + hover_y_offset, angle_rad, hover_scale)
    end
  end
end

local function draw_stats()
  local base_x = 10
  local base_y = 110
  local line_height = show_real_world_values and 36 or 22

  for i, key in ipairs(STAT_ORDER) do
    local value = terraforming_state.stats[key]
    local target_value = terraforming_state.targets[key]
    local status, color = get_stat_status(key, value)
    local y = base_y + (i - 1) * line_height

    love.graphics.setColor(unpack(color))
    love.graphics.print(
      STAT_LABELS[key] .. ": " .. format_signed(value) .. " / target " .. format_signed(target_value) .. "  [" .. status .. "]",
      base_x,
      y
    )

    if show_real_world_values then
      love.graphics.setColor(0.75, 0.84, 0.95, 1)
      love.graphics.print("    " .. get_real_world_mapping(key, value), base_x, y + 16)
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
end

local function draw_card_pile_widget(rect, label, count, is_hovered)
  local base_fill = { 0.08, 0.11, 0.16, 0.95 }
  local hover_fill = { 0.12, 0.17, 0.24, 0.95 }
  local border = is_hovered and { 0.85, 0.92, 1.0, 1 } or { 0.55, 0.67, 0.82, 1 }
  local fill = is_hovered and hover_fill or base_fill

  love.graphics.setColor(unpack(fill))
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 8, 8)
  love.graphics.setColor(unpack(border))
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 8, 8)
  love.graphics.setLineWidth(1)

  local stack_w = rect.w - 46
  local stack_h = rect.h - 72
  local stack_x = rect.x + 23
  local stack_y = rect.y + 34
  for offset = 2, 0, -1 do
    love.graphics.setColor(0.16 + offset * 0.03, 0.2 + offset * 0.03, 0.28 + offset * 0.03, 0.95)
    love.graphics.rectangle("fill", stack_x + offset * 3, stack_y + offset * 2, stack_w, stack_h, 6, 6)
    love.graphics.setColor(0.85, 0.88, 0.95, 0.9)
    love.graphics.rectangle("line", stack_x + offset * 3, stack_y + offset * 2, stack_w, stack_h, 6, 6)
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(label, rect.x, rect.y + 10, rect.w, "center")
  love.graphics.printf("x" .. tostring(count), rect.x, rect.y + rect.h - 24, rect.w, "center")
end

local function draw_pile_widgets()
  draw_card_pile_widget(get_draw_pile_rect(), "DECK", #player_deck.draw_pile, hovered_draw_pile)
  draw_card_pile_widget(get_discard_pile_rect(), "DISCARD", #player_deck.discard_pile, hovered_discard_pile)
end

local function draw_end_turn_button()
  local rect = get_end_turn_rect()
  local base = { 0.2, 0.32, 0.15, 0.95 }
  local hover = { 0.28, 0.45, 0.2, 0.98 }
  local border = { 0.72, 0.9, 0.62, 1 }
  local fill = hovered_end_turn and hover or base

  love.graphics.setColor(unpack(fill))
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 8, 8)
  love.graphics.setColor(unpack(border))
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 8, 8)
  love.graphics.setLineWidth(1)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("END TURN", rect.x, rect.y + 12, rect.w, "center")
  love.graphics.printf("(E)", rect.x, rect.y + 28, rect.w, "center")
end

local function draw_hud()
  local config = WORLD_CONFIGS[world_index]
  local hazard = terraforming_state:get_next_hazard()

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("World " .. world_index .. "/" .. #WORLD_CONFIGS .. ": " .. config.name .. " (" .. config.tier .. ")", 10, 10)
  love.graphics.print(
    "Turn: " .. terraforming_state.turn .. "/" .. terraforming_state.turn_limit ..
      "    Habitability: " .. terraforming_state.habitability .. "/" .. terraforming_state.goal,
    10,
    30
  )
  love.graphics.print("Energy: " .. current_energy .. " / " .. max_energy, 10, 50)
  love.graphics.print("Next Hazard: " .. hazard.name .. " (" .. format_delta_list(hazard.deltas) .. ")", 10, 70)
  draw_stats()

  if turn_summary then
    local summary_y = show_real_world_values and 270 or 210
    love.graphics.print("Last Turn Hazard: " .. turn_summary.hazard, 10, summary_y)
    love.graphics.print("Hazard Delta: " .. format_delta_list(turn_summary.hazard_deltas), 10, summary_y + 20)
    love.graphics.print("Coupling Delta: " .. format_delta_list(turn_summary.coupling_deltas), 10, summary_y + 40)
    love.graphics.print(
      "Growth " .. turn_summary.growth .. " - Penalty " .. turn_summary.penalty .. " = Net " .. format_signed(turn_summary.net),
      10,
      summary_y + 60
    )
  end

  love.graphics.print("Controls: Click card | E end turn | V influence map | M real-world mapping | R restart", 10, love.graphics.getHeight() - 22)
end

local function draw_status_overlay()
  local width = love.graphics.getWidth()
  local box_w = 620
  local box_h = 130
  local box_x = (width - box_w) / 2
  local box_y = 140

  love.graphics.setColor(0.05, 0.05, 0.08, 0.85)
  love.graphics.rectangle("fill", box_x, box_y, box_w, box_h, 8, 8)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("line", box_x, box_y, box_w, box_h, 8, 8)

  if campaign_state == "world_won" then
    love.graphics.printf("World Terraformed!", box_x, box_y + 24, box_w, "center")
    love.graphics.printf("Press N for the next world.", box_x, box_y + 56, box_w, "center")
  elseif campaign_state == "campaign_won" then
    love.graphics.printf("Campaign Complete", box_x, box_y + 24, box_w, "center")
    love.graphics.printf("You terraformed all worlds. Press R to restart.", box_x, box_y + 56, box_w, "center")
  elseif campaign_state == "campaign_lost" then
    love.graphics.printf("Terraforming Failed", box_x, box_y + 24, box_w, "center")
    love.graphics.printf("Turn limit reached before habitability target. Press R to restart.", box_x, box_y + 56, box_w, "center")
  end
end

local function draw_influence_edge(source, target, edge, highlight)
  local factor = edge.factor
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

  local positive_color = highlight and { 0.45, 0.95, 0.45, 1 } or { 0.4, 0.7, 0.4, 0.65 }
  local negative_color = highlight and { 0.98, 0.72, 0.3, 1 } or { 0.75, 0.58, 0.35, 0.65 }
  local color = factor > 0 and positive_color or negative_color

  love.graphics.setColor(unpack(color))
  love.graphics.setLineWidth(highlight and 3 or 2)
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
  local angle = safe_atan2(tangent_y, tangent_x)
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
  love.graphics.printf(factor > 0 and "+" or "-", badge_x - 8, badge_y - 7, 16, "center")
end

local function draw_influence_nodes(layout)
  local map_rect = layout.map_rect
  love.graphics.setColor(0.06, 0.08, 0.12, 0.88)
  love.graphics.rectangle("fill", map_rect.x, map_rect.y, map_rect.w, map_rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", map_rect.x, map_rect.y, map_rect.w, map_rect.h, 10, 10)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Core Influence Graph", map_rect.x + 12, map_rect.y + 10, map_rect.w - 24, "left")
  love.graphics.printf("Edges activate when |source| >= " .. tostring(terraforming_state.coupling_threshold), map_rect.x + 12, map_rect.y + 30, map_rect.w - 24, "left")

  love.graphics.setColor(0.45, 0.95, 0.45, 1)
  love.graphics.circle("fill", map_rect.x + 18, map_rect.y + 54, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("+ : same direction", map_rect.x + 30, map_rect.y + 47)
  love.graphics.setColor(0.98, 0.72, 0.3, 1)
  love.graphics.circle("fill", map_rect.x + 170, map_rect.y + 54, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("- : opposite direction", map_rect.x + 182, map_rect.y + 47)

  for _, edge in ipairs(INFLUENCE_EDGES) do
    local source = layout.nodes[edge.source]
    local target = layout.nodes[edge.target]
    local highlight = edge.source == focused_stat or edge.target == focused_stat
    draw_influence_edge(source, target, edge, highlight)
  end

  for _, key in ipairs(STAT_ORDER) do
    local node = layout.nodes[key]
    local value = terraforming_state.stats[key]
    local status, color = get_stat_status(key, value)
    local is_focused = key == focused_stat
    local is_hovered = key == hovered_influence_stat

    love.graphics.setColor(0.08, 0.1, 0.14, 0.95)
    love.graphics.circle("fill", node.x, node.y, node.r)
    love.graphics.setColor(is_focused and 0.98 or color[1], is_focused and 0.98 or color[2], is_focused and 0.98 or color[3], 1)
    love.graphics.setLineWidth(is_focused and 4 or (is_hovered and 3 or 2))
    love.graphics.circle("line", node.x, node.y, node.r)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(STAT_LABELS[key], node.x - node.r + 8, node.y - 26, node.r * 2 - 16, "center")
    love.graphics.printf(format_signed(value) .. " (" .. status .. ")", node.x - node.r + 8, node.y - 6, node.r * 2 - 16, "center")
  end
end

local function draw_influence_details(layout)
  local rect = layout.details_rect
  local value = terraforming_state.stats[focused_stat]
  local help = INFLUENCE_HELP[focused_stat]
  local status, color = get_stat_status(focused_stat, value)
  local threshold = terraforming_state.coupling_threshold
  local abs_value = math.abs(value)
  local distance_to_trigger = threshold - abs_value
  local outgoing_edges = get_edges_from_stat(focused_stat)

  love.graphics.setColor(0.06, 0.08, 0.12, 0.92)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 10, 10)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Focused Primitive: " .. STAT_LABELS[focused_stat], rect.x + 14, rect.y + 14, rect.w - 28, "left")
  love.graphics.setColor(unpack(color))
  love.graphics.printf("Current notch: " .. format_signed(value) .. " (" .. status .. ")", rect.x + 14, rect.y + 38, rect.w - 28, "left")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(help.summary, rect.x + 14, rect.y + 62, rect.w - 28, "left")
  love.graphics.printf("Incoming: " .. help.incoming, rect.x + 14, rect.y + 84, rect.w - 28, "left")

  if distance_to_trigger <= 0 then
    love.graphics.setColor(0.45, 0.95, 0.45, 1)
    love.graphics.printf("Coupling trigger is ACTIVE this turn.", rect.x + 14, rect.y + 106, rect.w - 28, "left")
  else
    love.graphics.setColor(0.98, 0.82, 0.35, 1)
    love.graphics.printf("Needs " .. tostring(distance_to_trigger) .. " more notch(es) to trigger coupling.", rect.x + 14, rect.y + 106, rect.w - 28, "left")
  end
  love.graphics.setColor(1, 1, 1, 1)

  local line_y = rect.y + 128
  love.graphics.printf("Outgoing effects now:", rect.x + 14, line_y, rect.w - 28, "left")
  line_y = line_y + 20
  for _, edge in ipairs(outgoing_edges) do
    local delta = get_edge_trigger_delta(edge, terraforming_state.stats)
    local delta_text = "inactive"
    local delta_color = { 0.75, 0.82, 0.9, 1 }
    if delta ~= 0 then
      delta_text = STAT_LABELS[edge.target] .. " " .. format_signed(delta)
      delta_color = { 0.45, 0.95, 0.45, 1 }
    end
    love.graphics.setColor(unpack(delta_color))
    love.graphics.printf("- " .. edge.text .. " => " .. delta_text, rect.x + 14, line_y, rect.w - 28, "left")
    line_y = line_y + 18
  end

  if show_real_world_values then
    love.graphics.setColor(0.75, 0.87, 0.95, 1)
    love.graphics.printf(get_real_world_mapping(focused_stat, value), rect.x + 14, rect.y + rect.h - 24, rect.w - 28, "left")
  end
end

local function draw_forecast_panel(layout)
  local rect = layout.forecast_rect
  local baseline, scenario = compute_forecasts(selected_forecast_card_index)
  local recommendations = compute_play_recommendations(3)
  local focused_target = terraforming_state.targets[focused_stat]

  love.graphics.setColor(0.06, 0.08, 0.12, 0.92)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 10, 10)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("End-Turn Forecast", rect.x + 14, rect.y + 12, rect.w - 28, "left")
  love.graphics.printf("Hazard: " .. baseline.hazard, rect.x + 14, rect.y + 34, rect.w - 28, "left")

  local split_x = rect.x + math.floor(rect.w * 0.5)
  love.graphics.printf("End now", rect.x + 14, rect.y + 56, rect.w * 0.46, "left")
  love.graphics.printf("Play selected then end", split_x + 8, rect.y + 56, rect.w * 0.46 - 12, "left")

  local left_y = rect.y + 76
  for _, key in ipairs(STAT_ORDER) do
    local now_val = terraforming_state.stats[key]
    local end_val = baseline.projected_stats[key]
    love.graphics.printf(
      STAT_LABELS[key] .. " " .. format_signed(now_val) .. " -> " .. format_signed(end_val),
      rect.x + 14,
      left_y,
      rect.w * 0.46,
      "left"
    )
    left_y = left_y + 16
  end
  local base_focus_end = baseline.projected_stats[focused_stat]
  love.graphics.printf("Net Habitability: " .. format_signed(baseline.net), rect.x + 14, left_y + 2, rect.w * 0.46, "left")
  love.graphics.printf(
    STAT_LABELS[focused_stat] .. " to target: " .. tostring(math.abs(base_focus_end - focused_target)),
    rect.x + 14,
    left_y + 18,
    rect.w * 0.46,
    "left"
  )

  if scenario then
    if scenario.affordable then
      local right_y = rect.y + 76
      for _, key in ipairs(STAT_ORDER) do
        local now_val = terraforming_state.stats[key]
        local end_val = scenario.summary.projected_stats[key]
        love.graphics.printf(
          STAT_LABELS[key] .. " " .. format_signed(now_val) .. " -> " .. format_signed(end_val),
          split_x + 8,
          right_y,
          rect.w * 0.46 - 12,
          "left"
        )
        right_y = right_y + 16
      end
      local scen_focus_end = scenario.summary.projected_stats[focused_stat]
      love.graphics.printf(
        "Net Habitability: " .. format_signed(scenario.summary.net) ..
          " (" .. format_signed(scenario.summary.net - baseline.net) .. " vs now)",
        split_x + 8,
        right_y + 2,
        rect.w * 0.46 - 12,
        "left"
      )
      love.graphics.printf(
        STAT_LABELS[focused_stat] .. " to target: " .. tostring(math.abs(scen_focus_end - focused_target)),
        split_x + 8,
        right_y + 18,
        rect.w * 0.46 - 12,
        "left"
      )
    else
      love.graphics.setColor(0.98, 0.65, 0.35, 1)
      love.graphics.printf("Not enough energy for selected card.", split_x + 8, rect.y + 78, rect.w * 0.46 - 12, "left")
      love.graphics.setColor(1, 1, 1, 1)
    end
  else
    love.graphics.printf("Select a card below to preview a one-card outcome.", split_x + 8, rect.y + 78, rect.w * 0.46 - 12, "left")
  end

  local rec_start_y = rect.y + 156
  local usable_height = rect.y + rect.h - rec_start_y - 10
  if usable_height > 18 then
    love.graphics.setColor(0.75, 0.87, 0.95, 1)
    love.graphics.printf("Best immediate plays:", rect.x + 14, rec_start_y, rect.w - 28, "left")
    local line_y = rec_start_y + 18
    local lines_available = math.max(1, math.floor((rect.y + rect.h - line_y - 6) / 16))
    local lines_to_draw = math.min(lines_available, #recommendations)

    if lines_to_draw == 0 then
      love.graphics.setColor(0.95, 0.75, 0.62, 1)
      love.graphics.printf("No affordable cards this turn.", rect.x + 14, line_y, rect.w - 28, "left")
    else
      love.graphics.setColor(1, 1, 1, 1)
      for i = 1, lines_to_draw do
        local rec = recommendations[i]
        local text = string.format(
          "%d) %s  net %s  focused %s",
          rec.index,
          rec.card.name,
          format_signed(rec.net_gain),
          format_signed(rec.focus_gain)
        )
        love.graphics.printf(text, rect.x + 14, line_y, rect.w - 28, "left")
        line_y = line_y + 16
      end
    end
  end
end

local function draw_influence_cards(layout)
  local rect = layout.cards_rect
  local card_rects = get_influence_card_rects(layout)

  love.graphics.setColor(0.06, 0.08, 0.12, 0.92)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 10, 10)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Card Preview Selector (click one card to forecast, click again to clear)", rect.x + 10, rect.y + 10, rect.w - 20, "left")

  for i, card_rect in ipairs(card_rects) do
    local card = card_rect.card
    local selected = (selected_forecast_card_index == i)
    local hovered = (hovered_forecast_card_index == i)
    local affordable = can_afford(card.cost or 0)

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
    love.graphics.printf(i .. ". " .. card.name, card_rect.x + 8, card_rect.y + 8, card_rect.w - 16, "left")
    love.graphics.printf(
      "Cost " .. tostring(card.cost or 0) .. " | " .. card.description,
      card_rect.x + 8,
      card_rect.y + 28,
      card_rect.w - 16,
      "left"
    )
  end
end

local function draw_influence_screen()
  local layout = get_influence_layout()

  Background.draw_fill()
  Background.draw_stars()

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("Core Influence Map (V)", 16, 12)
  love.graphics.print("Click a primitive to focus its effects. Click a card to forecast end-turn outcomes.", 16, 32)
  love.graphics.print("M toggles real-world mapping. C clears preview. V returns to gameplay.", 16, 52)

  draw_influence_nodes(layout)
  draw_influence_details(layout)
  draw_forecast_panel(layout)
  draw_influence_cards(layout)

  if campaign_state ~= "playing" then
    draw_status_overlay()
  end
end

function love.update(dt)
  target:update(dt)
  sanitize_selection()

  hovered_card_index = nil
  hovered_draw_pile = false
  hovered_discard_pile = false
  hovered_end_turn = false
  hovered_influence_stat = nil
  hovered_forecast_card_index = nil

  local mx, my = love.mouse.getPosition()

  if view_mode == "gameplay" and campaign_state == "playing" then
    hovered_card_index = get_card_index_at_position(mx, my)

    local draw_rect = get_draw_pile_rect()
    hovered_draw_pile = point_in_rect(mx, my, draw_rect.x, draw_rect.y, draw_rect.w, draw_rect.h)

    local discard_rect = get_discard_pile_rect()
    hovered_discard_pile = point_in_rect(mx, my, discard_rect.x, discard_rect.y, discard_rect.w, discard_rect.h)

    local end_turn_rect = get_end_turn_rect()
    hovered_end_turn = point_in_rect(mx, my, end_turn_rect.x, end_turn_rect.y, end_turn_rect.w, end_turn_rect.h)
  end

  if view_mode == "influence" and campaign_state == "playing" then
    local layout = get_influence_layout()
    for _, key in ipairs(STAT_ORDER) do
      local node = layout.nodes[key]
      if point_in_circle(mx, my, node.x, node.y, node.r) then
        hovered_influence_stat = key
        break
      end
    end

    local card_rects = get_influence_card_rects(layout)
    for i, rect in ipairs(card_rects) do
      if point_in_rect(mx, my, rect.x, rect.y, rect.w, rect.h) then
        hovered_forecast_card_index = i
        break
      end
    end
  end
end

function love.draw()
  if view_mode == "gameplay" then
    Background.draw_fill()
    Background.draw_stars()
    target:draw()

    draw_hud()
    draw_pile_widgets()
    draw_end_turn_button()
    draw_hand()

    if campaign_state ~= "playing" then
      draw_status_overlay()
    end
    return
  end

  draw_influence_screen()
end

function love.keypressed(key)
  if key == "r" then
    start_campaign()
    return
  end

  if key == "v" then
    if view_mode == "gameplay" then
      view_mode = "influence"
    else
      view_mode = "gameplay"
    end
    return
  end

  if key == "m" then
    show_real_world_values = not show_real_world_values
    return
  end

  if campaign_state == "world_won" then
    if key == "n" then
      setup_world(world_index + 1)
    end
    return
  end

  if campaign_state ~= "playing" then
    return
  end

  if key == "e" then
    end_turn()
    return
  end

  if view_mode == "influence" then
    if key == "c" then
      selected_forecast_card_index = nil
      return
    end

    local num = tonumber(key)
    if num and num >= 1 and num <= #player_deck.hand then
      if selected_forecast_card_index == num then
        selected_forecast_card_index = nil
      else
        selected_forecast_card_index = num
      end
    end
    return
  end

  local num = tonumber(key)
  if not num or num < 1 or num > #player_deck.hand then
    return
  end

  try_play_card(num)
end

function love.mousepressed(x, y, button)
  if button ~= 1 then
    return
  end

  if campaign_state == "world_won" then
    return
  end

  if campaign_state ~= "playing" then
    return
  end

  if view_mode == "influence" then
    local layout = get_influence_layout()
    for _, key in ipairs(STAT_ORDER) do
      local node = layout.nodes[key]
      if point_in_circle(x, y, node.x, node.y, node.r) then
        focused_stat = key
        return
      end
    end

    local card_rects = get_influence_card_rects(layout)
    for i, rect in ipairs(card_rects) do
      if point_in_rect(x, y, rect.x, rect.y, rect.w, rect.h) then
        if selected_forecast_card_index == i then
          selected_forecast_card_index = nil
        else
          selected_forecast_card_index = i
        end
        return
      end
    end
    return
  end

  local end_turn_rect = get_end_turn_rect()
  if point_in_rect(x, y, end_turn_rect.x, end_turn_rect.y, end_turn_rect.w, end_turn_rect.h) then
    end_turn()
    return
  end

  local card_index = get_card_index_at_position(x, y)
  if card_index then
    try_play_card(card_index)
  end
end
