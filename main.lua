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
  { source = "heat", target = "soil", factor = -1, text = "Heat -> Soil (-)", curve = 68 },
  { source = "air", target = "heat", factor = 1, text = "Air -> Heat (+)", curve = 0 },
  { source = "air", target = "water", factor = 1, text = "Air -> Water (+)", curve = -72 },
  { source = "water", target = "soil", factor = 1, text = "Water -> Soil (+)", curve = 0 },
  { source = "water", target = "air", factor = 1, text = "Water -> Air (+)", curve = 72 },
  { source = "soil", target = "air", factor = 1, text = "Soil -> Air (+)", curve = 0 }
}

local INFLUENCE_HELP = {
  heat = {
    summary = "Heat is bipolar: too low freezes systems, too high scorches systems.",
    incoming = "Air influences Heat whenever Air is extreme enough to trigger coupling.",
    outgoing = {
      "Heat can shift Water.",
      "Heat can shift Soil."
    }
  },
  air = {
    summary = "Air is one-directional health: very negative is toxic/thin, zero is ideal.",
    incoming = "Water and Soil influence Air when they hit coupling threshold.",
    outgoing = {
      "Air can shift Heat.",
      "Air can shift Water."
    }
  },
  water = {
    summary = "Water is bipolar: very negative means ice lock, very positive means steam lock.",
    incoming = "Heat and Air both influence Water once coupling is active.",
    outgoing = {
      "Water can shift Soil.",
      "Water can shift Air."
    }
  },
  soil = {
    summary = "Soil is one-directional health: very negative is sterile regolith, zero is ideal.",
    incoming = "Heat and Water influence Soil once coupling is active.",
    outgoing = {
      "Soil can shift Air."
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
local forecast_mode = "current" -- current | do_nothing | selected
local edge_filter_mode = "focused_both" -- focused_both | focused_incoming | focused_outgoing | all

local hovered_card_index = nil
local hovered_draw_pile = false
local hovered_discard_pile = false
local hovered_end_turn = false
local hovered_influence_stat = nil
local hovered_forecast_option_index = nil
local hovered_edge_filter_button = false
local hovered_forecast_mode = nil

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
    if forecast_mode == "selected" then
      forecast_mode = "current"
    end
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

local function get_edge_filter_label(mode)
  if mode == "focused_incoming" then
    return "Incoming"
  elseif mode == "focused_outgoing" then
    return "Outgoing"
  elseif mode == "all" then
    return "All Edges"
  end
  return "In + Out"
end

local function cycle_edge_filter_mode()
  local modes = { "focused_both", "focused_incoming", "focused_outgoing", "all" }
  for i, mode in ipairs(modes) do
    if edge_filter_mode == mode then
      edge_filter_mode = modes[(i % #modes) + 1]
      return
    end
  end
  edge_filter_mode = modes[1]
end

local function edge_is_visible(edge)
  if edge_filter_mode == "all" then
    return true
  elseif edge_filter_mode == "focused_incoming" then
    return edge.target == focused_stat
  elseif edge_filter_mode == "focused_outgoing" then
    return edge.source == focused_stat
  end
  return edge.source == focused_stat or edge.target == focused_stat
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

local function get_map_toggle_buttons(layout)
  local map_rect = layout.map_rect
  local button_h = 26
  local filter_w = 198
  local right = map_rect.x + map_rect.w - 12
  local filter_x = right - filter_w
  local y = map_rect.y + 8

  return {
    filter = { x = filter_x, y = y, w = filter_w, h = button_h }
  }
end

local function get_forecast_mode_buttons(layout)
  local rect = layout.forecast_rect
  return {
    {
      id = "current",
      text = "Current",
      x = rect.x + 14,
      y = rect.y + 52,
      w = 168,
      h = 24
    }
  }
end

local function get_influence_card_rects(layout)
  local rows = {}
  local options = {
    { kind = "do_nothing" }
  }
  for i, card in ipairs(player_deck.hand) do
    table.insert(options, { kind = "card", card = card, card_index = i })
  end
  local rect = layout.cards_rect
  local card_w = 185
  local card_h = 58
  local gap_x = 12
  local gap_y = 10
  local cards_per_row = math.max(1, math.floor((rect.w - 20 + gap_x) / (card_w + gap_x)))
  local used_width = cards_per_row * card_w + (cards_per_row - 1) * gap_x
  local start_x = rect.x + math.floor((rect.w - used_width) / 2)

  for i, option in ipairs(options) do
    local row = math.floor((i - 1) / cards_per_row)
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

local function setup_world(index)
  world_index = index
  local config = WORLD_CONFIGS[index]
  terraforming_state = TerraformingState.new(config)
  turn_summary = nil
  campaign_state = "playing"
  selected_forecast_card_index = nil
  focused_stat = "heat"
  forecast_mode = "current"
  edge_filter_mode = "focused_both"

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
  forecast_mode = "current"

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
      apply_card_to_snapshot(card, snapshot)
      scenario = {
        card = card,
        affordable = affordable,
        summary = terraforming_state:forecast_end_turn(snapshot)
      }
    end
  end

  return base_summary, scenario
end

local function get_forecast_context()
  local baseline, scenario = compute_forecasts(selected_forecast_card_index)
  local active_mode = forecast_mode

  if active_mode == "selected" and not scenario then
    active_mode = "do_nothing"
  end

  local active_snapshot = terraforming_state.stats
  local active_summary = nil
  if active_mode == "do_nothing" then
    active_snapshot = baseline.projected_stats
    active_summary = baseline
  elseif active_mode == "selected" and scenario then
    active_snapshot = scenario.summary.projected_stats
    active_summary = scenario.summary
  end

  return {
    baseline = baseline,
    scenario = scenario,
    active_mode = active_mode,
    active_snapshot = active_snapshot,
    active_summary = active_summary
  }
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
    forecast_mode = "current"
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

local function draw_influence_edge(source, target, edge, highlight, snapshot)
  local current_delta = get_edge_trigger_delta(edge, snapshot)
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
  local badge_text = format_signed(current_delta)
  love.graphics.printf(badge_text, badge_x - 10, badge_y - 7, 20, "center")
end

local function value_to_track_x(bounds, value, x, w)
  local span = bounds.max - bounds.min
  if span <= 0 then
    return x + (w * 0.5)
  end
  local t = (value - bounds.min) / span
  return x + t * w
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function draw_diamond(x, y, size, fill_color, border_color)
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

local function draw_stat_track(map_rect, node, stat_key, current_value, preview_value, target_value)
  local bounds = terraforming_state:get_stat_bounds(stat_key)
  local track_w = math.floor(node.r * 1.6)
  local track_h = 12
  local track_x = math.floor(node.x - (track_w * 0.5))
  local track_y = math.floor(node.y - node.r - 20)
  local min_track_y = map_rect.y + 86
  if track_y < min_track_y then
    track_y = min_track_y
  end
  local current_x = value_to_track_x(bounds, current_value, track_x, track_w)
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
    local r = lerp(0.12, 0.8, severity)
    local g = lerp(0.42, 0.16, severity)
    local b = lerp(0.14, 0.18, severity)
    love.graphics.setColor(r, g, b, 0.95)
    love.graphics.rectangle("fill", track_x + i, track_y + 2, 1, track_h - 4)
  end

  love.graphics.setColor(0.58, 0.67, 0.78, 0.95)
  love.graphics.rectangle("line", track_x, track_y, track_w, track_h, 4, 4)

  local marker_y = track_y + math.floor(track_h * 0.5)
  draw_diamond(current_x, marker_y, 5, { 1, 1, 1, 1 }, { 0.05, 0.08, 0.12, 1 })

  if preview_value then
    local preview_x = value_to_track_x(bounds, preview_value, track_x, track_w)
    local preview_y = marker_y
    if math.abs(preview_x - current_x) < 6 then
      preview_y = marker_y + 11
    end
    draw_diamond(preview_x, preview_y, 5, { 0.45, 0.78, 1.0, 1 }, { 0.05, 0.08, 0.12, 1 })
  end
end

local function draw_influence_nodes(layout, forecast_ctx)
  local map_rect = layout.map_rect
  local snapshot = forecast_ctx.active_snapshot
  local toggle_buttons = get_map_toggle_buttons(layout)

  love.graphics.setColor(0.06, 0.08, 0.12, 0.88)
  love.graphics.rectangle("fill", map_rect.x, map_rect.y, map_rect.w, map_rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", map_rect.x, map_rect.y, map_rect.w, map_rect.h, 10, 10)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Core Influence Graph", map_rect.x + 12, map_rect.y + 10, map_rect.w - 24, "left")
  love.graphics.printf("Edges activate when |source| >= " .. tostring(terraforming_state.coupling_threshold), map_rect.x + 12, map_rect.y + 30, map_rect.w - 24, "left")

  local filter_fill = hovered_edge_filter_button and { 0.2, 0.3, 0.4, 0.95 } or { 0.14, 0.19, 0.27, 0.95 }
  love.graphics.setColor(unpack(filter_fill))
  love.graphics.rectangle("fill", toggle_buttons.filter.x, toggle_buttons.filter.y, toggle_buttons.filter.w, toggle_buttons.filter.h, 7, 7)
  love.graphics.setColor(0.7, 0.82, 0.96, 1)
  love.graphics.rectangle("line", toggle_buttons.filter.x, toggle_buttons.filter.y, toggle_buttons.filter.w, toggle_buttons.filter.h, 7, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Flow: " .. get_edge_filter_label(edge_filter_mode), toggle_buttons.filter.x + 8, toggle_buttons.filter.y + 6, toggle_buttons.filter.w - 12, "left")

  love.graphics.setColor(0.45, 0.95, 0.45, 1)
  love.graphics.circle("fill", map_rect.x + 18, map_rect.y + 58, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("+ target impact", map_rect.x + 30, map_rect.y + 51)
  love.graphics.setColor(0.98, 0.45, 0.45, 1)
  love.graphics.circle("fill", map_rect.x + 156, map_rect.y + 58, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("- target impact", map_rect.x + 168, map_rect.y + 51)
  love.graphics.setColor(0.62, 0.66, 0.74, 1)
  love.graphics.circle("fill", map_rect.x + 292, map_rect.y + 58, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("0 inactive", map_rect.x + 304, map_rect.y + 51)

  local marker_legend_y = map_rect.y + 68
  draw_diamond(map_rect.x + 18, marker_legend_y + 1, 5, { 1, 1, 1, 1 }, { 0.05, 0.08, 0.12, 1 })
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("current", map_rect.x + 30, marker_legend_y - 6)
  draw_diamond(map_rect.x + 124, marker_legend_y + 1, 5, { 0.45, 0.78, 1.0, 1 }, { 0.05, 0.08, 0.12, 1 })
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("preview", map_rect.x + 136, marker_legend_y - 6)

  for _, edge in ipairs(INFLUENCE_EDGES) do
    if edge_is_visible(edge) then
      local source = layout.nodes[edge.source]
      local target = layout.nodes[edge.target]
      local highlight = edge.source == focused_stat or edge.target == focused_stat
      draw_influence_edge(source, target, edge, highlight, snapshot)
    end
  end

  for _, key in ipairs(STAT_ORDER) do
    local node = layout.nodes[key]
    local value = snapshot[key]
    local current_value = terraforming_state.stats[key]
    local preview_value = (forecast_ctx.active_mode == "selected") and snapshot[key] or nil
    local status, color = get_stat_status(key, value)
    local is_focused = key == focused_stat
    local is_hovered = key == hovered_influence_stat

    draw_stat_track(map_rect, node, key, current_value, preview_value, terraforming_state.targets[key])

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

local function draw_influence_details(layout, forecast_ctx)
  local rect = layout.details_rect
  local snapshot = forecast_ctx.active_snapshot
  local value = snapshot[focused_stat]
  local help = INFLUENCE_HELP[focused_stat]
  local status, color = get_stat_status(focused_stat, value)
  local threshold = terraforming_state.coupling_threshold
  local abs_value = math.abs(value)
  local distance_to_trigger = threshold - abs_value
  local incoming_edges = {}
  for _, edge in ipairs(INFLUENCE_EDGES) do
    if edge.target == focused_stat then
      table.insert(incoming_edges, edge)
    end
  end
  local outgoing_edges = get_edges_from_stat(focused_stat)
  local incoming_total = 0
  local incoming_active = 0
  for _, edge in ipairs(incoming_edges) do
    local delta = get_edge_trigger_delta(edge, snapshot)
    incoming_total = incoming_total + delta
    if delta ~= 0 then
      incoming_active = incoming_active + 1
    end
  end
  local outgoing_total = 0
  local outgoing_active = 0
  for _, edge in ipairs(outgoing_edges) do
    local delta = get_edge_trigger_delta(edge, snapshot)
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

  love.graphics.setColor(0.06, 0.08, 0.12, 0.92)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 10, 10)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Focused Primitive: " .. STAT_LABELS[focused_stat], rect.x + 14, rect.y + 14, rect.w - 28, "left")
  love.graphics.setColor(unpack(color))
  love.graphics.printf("Reference: " .. mode_label, rect.x + 14, rect.y + 36, rect.w - 28, "left")
  love.graphics.printf("Notch: " .. format_signed(value) .. " (" .. status .. ")", rect.x + 14, rect.y + 58, rect.w - 28, "left")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(help.summary, rect.x + 14, rect.y + 76, rect.w - 28, "left")
  love.graphics.printf("Incoming: " .. help.incoming, rect.x + 14, rect.y + 94, rect.w - 28, "left")

  if distance_to_trigger <= 0 then
    love.graphics.setColor(0.45, 0.95, 0.45, 1)
    love.graphics.printf(
      "Coupling active: |value| = " .. tostring(abs_value) .. " >= " .. tostring(threshold) .. ".",
      rect.x + 14,
      rect.y + 112,
      rect.w - 28,
      "left"
    )
  else
    love.graphics.setColor(0.98, 0.82, 0.35, 1)
    love.graphics.printf(
      "Coupling inactive: |value| = " .. tostring(abs_value) ..
        ", need " .. tostring(distance_to_trigger) .. " more to reach " .. tostring(threshold) .. ".",
      rect.x + 14,
      rect.y + 112,
      rect.w - 28,
      "left"
    )
  end
  love.graphics.setColor(1, 1, 1, 1)

  local summary_y = rect.y + 130
  love.graphics.printf(
    "Incoming net " .. format_signed(incoming_total) .. " (" ..
      tostring(incoming_active) .. "/" .. tostring(#incoming_edges) .. " active) | Outgoing net " ..
      format_signed(outgoing_total) .. " (" .. tostring(outgoing_active) .. "/" ..
      tostring(#outgoing_edges) .. " active)",
    rect.x + 14,
    summary_y,
    rect.w - 28,
    "left"
  )

  love.graphics.setColor(0.75, 0.87, 0.95, 1)
  love.graphics.printf(
    "Edge badges show per-link impact now. 0 means source magnitude is below threshold.",
    rect.x + 14,
    rect.y + 148,
    rect.w - 28,
    "left"
  )

  if show_real_world_values then
    love.graphics.setColor(0.75, 0.87, 0.95, 1)
    love.graphics.printf(get_real_world_mapping(focused_stat, value), rect.x + 14, rect.y + rect.h - 24, rect.w - 28, "left")
  end
end

local function draw_forecast_panel(layout, forecast_ctx)
  local rect = layout.forecast_rect
  local baseline = forecast_ctx.baseline
  local scenario = forecast_ctx.scenario
  local recommendations = compute_play_recommendations(3)
  local focused_target = terraforming_state.targets[focused_stat]
  local mode_buttons = get_forecast_mode_buttons(layout)

  love.graphics.setColor(0.06, 0.08, 0.12, 0.92)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 10, 10)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("End-Turn Forecast", rect.x + 14, rect.y + 12, rect.w - 28, "left")
  love.graphics.printf("Hazard: " .. baseline.hazard, rect.x + 14, rect.y + 34, rect.w - 28, "left")
  love.graphics.setColor(0.75, 0.87, 0.95, 1)
  love.graphics.printf("Map reference mode: " .. (forecast_ctx.active_mode == "current" and "Current" or (forecast_ctx.active_mode == "selected" and "Selected Card" or "Do Nothing")), rect.x + 210, rect.y + 34, rect.w - 224, "left")
  love.graphics.setColor(1, 1, 1, 1)

  for _, button in ipairs(mode_buttons) do
    local active = forecast_ctx.active_mode == button.id
    local hovered = hovered_forecast_mode == button.id
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

  local split_x = rect.x + math.floor(rect.w * 0.5)
  love.graphics.printf("Do Nothing Outcome", rect.x + 14, rect.y + 82, rect.w * 0.46, "left")
  love.graphics.printf("Selected Option Outcome", split_x + 8, rect.y + 82, rect.w * 0.46 - 12, "left")

  local left_y = rect.y + 102
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
    left_y = left_y + 15
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
    local right_y = rect.y + 102
    if not scenario.affordable then
      love.graphics.setColor(0.98, 0.65, 0.35, 1)
      love.graphics.printf("Card unaffordable now (preview only).", split_x + 8, right_y, rect.w * 0.46 - 12, "left")
      love.graphics.setColor(1, 1, 1, 1)
      right_y = right_y + 16
    end

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
      right_y = right_y + 15
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
    love.graphics.printf("Select a card below to preview a one-card outcome.", split_x + 8, rect.y + 102, rect.w * 0.46 - 12, "left")
  end

  local rec_start_y = rect.y + 182
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
  love.graphics.printf("Preview Selector (Do Nothing or card). Use Current above to clear preview.", rect.x + 10, rect.y + 10, rect.w - 20, "left")

  for i, card_rect in ipairs(card_rects) do
    local option = card_rect.option
    local is_do_nothing = option.kind == "do_nothing"
    local card = option.card
    local selected = false
    local affordable = true
    if is_do_nothing then
      selected = forecast_mode == "do_nothing"
    else
      selected = forecast_mode == "selected" and selected_forecast_card_index == option.card_index
      affordable = can_afford(card.cost or 0)
    end
    local hovered = (hovered_forecast_option_index == i)

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

local function draw_influence_screen()
  local layout = get_influence_layout()
  local forecast_ctx = get_forecast_context()

  Background.draw_fill()
  Background.draw_stars()

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("Core Influence Map (V)", 16, 12)
  love.graphics.print("Click primitive to focus. Arrows show current coupling impact only.", 16, 32)
  love.graphics.print("M mapping, C clear card, I flow, Z current, X do nothing, P selected card, V gameplay.", 16, 52)

  draw_influence_nodes(layout, forecast_ctx)
  draw_influence_details(layout, forecast_ctx)
  draw_forecast_panel(layout, forecast_ctx)
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
  hovered_forecast_option_index = nil
  hovered_edge_filter_button = false
  hovered_forecast_mode = nil

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
    local toggle_buttons = get_map_toggle_buttons(layout)
    hovered_edge_filter_button = point_in_rect(mx, my, toggle_buttons.filter.x, toggle_buttons.filter.y, toggle_buttons.filter.w, toggle_buttons.filter.h)

    local forecast_buttons = get_forecast_mode_buttons(layout)
    for _, button in ipairs(forecast_buttons) do
      if point_in_rect(mx, my, button.x, button.y, button.w, button.h) then
        hovered_forecast_mode = button.id
        break
      end
    end

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
        hovered_forecast_option_index = i
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
    if key == "i" then
      cycle_edge_filter_mode()
      return
    end

    if key == "z" then
      selected_forecast_card_index = nil
      forecast_mode = "current"
      return
    end

    if key == "x" then
      forecast_mode = "do_nothing"
      return
    end

    if key == "p" then
      if selected_forecast_card_index then
        forecast_mode = "selected"
      else
        forecast_mode = "do_nothing"
      end
      return
    end

    if key == "c" then
      selected_forecast_card_index = nil
      forecast_mode = "current"
      return
    end

    local num = tonumber(key)
    if num and num >= 1 and num <= #player_deck.hand then
      selected_forecast_card_index = num
      forecast_mode = "selected"
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
    local toggle_buttons = get_map_toggle_buttons(layout)
    if point_in_rect(x, y, toggle_buttons.filter.x, toggle_buttons.filter.y, toggle_buttons.filter.w, toggle_buttons.filter.h) then
      cycle_edge_filter_mode()
      return
    end

    local forecast_buttons = get_forecast_mode_buttons(layout)
    for _, button in ipairs(forecast_buttons) do
      if point_in_rect(x, y, button.x, button.y, button.w, button.h) then
        selected_forecast_card_index = nil
        forecast_mode = "current"
        return
      end
    end

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
        local option = rect.option
        if option.kind == "do_nothing" then
          selected_forecast_card_index = nil
          forecast_mode = "do_nothing"
        else
          selected_forecast_card_index = option.card_index
          forecast_mode = "selected"
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
