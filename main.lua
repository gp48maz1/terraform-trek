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
  { source = "water", target = "air", factor = -1, text = "Water -> Air (-)", curve = 72 },
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
local show_graph_explain = false
local show_turn_explain = false
local show_objectives_explain = false

local hovered_card_index = nil
local hovered_draw_pile = false
local hovered_discard_pile = false
local hovered_end_turn = false
local hovered_influence_stat = nil
local hovered_forecast_option_index = nil
local hovered_edge_filter_button = false
local hovered_forecast_mode = nil
local hovered_graph_explain_button = false
local hovered_turn_explain_button = false
local hovered_objectives_explain_button = false

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

local function clamp_value(value, min_value, max_value)
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
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
    y = 96,
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
  local objectives_rect = {
    x = right_x,
    y = map_rect.y,
    w = right_w,
    h = map_rect.h
  }

  local graph_explain_rect = {
    x = map_rect.x + 22,
    y = map_rect.y + 92,
    w = map_rect.w - 44,
    h = map_rect.h - 132
  }

  local turn_explain_rect = {
    x = map_rect.x + 24,
    y = map_rect.y + 92,
    w = sw - 48,
    h = map_rect.h - 88
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
    objectives_rect = objectives_rect,
    graph_explain_rect = graph_explain_rect,
    turn_explain_rect = turn_explain_rect,
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
  local explain_w = 154
  local explain_y = map_rect.y + map_rect.h - button_h - 8

  return {
    filter = { x = filter_x, y = y, w = filter_w, h = button_h },
    explain_graph = { x = map_rect.x + 12, y = explain_y, w = explain_w, h = button_h }
  }
end

local function get_forecast_mode_buttons(rect)
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

local function get_preview_explain_button(layout)
  local rect = layout.cards_rect
  return {
    x = rect.x + 12,
    y = rect.y + rect.h - 30,
    w = 176,
    h = 24
  }
end

local function get_objectives_explain_button(layout)
  local rect = layout.objectives_rect
  return {
    x = rect.x + 14,
    y = rect.y + rect.h - 34,
    w = 188,
    h = 24
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
  show_graph_explain = false
  show_turn_explain = false
  show_objectives_explain = false

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

local function apply_card_to_snapshot(card, snapshot, economy_state)
  if not card then
    return
  end

  if card.effect_fn_name == "apply_stat_changes" then
    terraforming_state:apply_stat_changes_to(card.properties.stat_changes or {}, snapshot)
  elseif card.effect_fn_name == "stabilize_system" then
    terraforming_state:adjust_snapshot_toward_targets(snapshot, 1)
  elseif card.effect_fn_name == "install_industry" then
    local industry_def = card.properties and card.properties.industry_def
    if industry_def and economy_state and economy_state.industries then
      terraforming_state:install_industry_in_slots(industry_def, economy_state.industries)
    end
  end
end

local function compute_forecasts(card_index)
  local base_summary = terraforming_state:forecast_end_turn(terraforming_state.stats, {
    economy_state = terraforming_state:get_economy_snapshot()
  })
  local scenario = nil

  if card_index then
    local card = player_deck.hand[card_index]
    if card then
      local snapshot = copy_stats(terraforming_state.stats)
      local economy = terraforming_state:get_economy_snapshot()
      local affordable = can_afford(card.cost or 0)
      apply_card_to_snapshot(card, snapshot, economy)
      scenario = {
        card = card,
        affordable = affordable,
        summary = terraforming_state:forecast_end_turn(snapshot, { economy_state = economy })
      }
    end
  end

  return base_summary, scenario
end

local function get_forecast_context()
  local baseline, scenario = compute_forecasts(selected_forecast_card_index)
  local card_push_snapshot = nil
  if selected_forecast_card_index then
    local card = player_deck.hand[selected_forecast_card_index]
    if card then
      card_push_snapshot = copy_stats(terraforming_state.stats)
      local card_push_economy = terraforming_state:get_economy_snapshot()
      apply_card_to_snapshot(card, card_push_snapshot, card_push_economy)
    end
  end
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

  local current_economy = terraforming_state:get_economy_snapshot()
  local active_economy = current_economy
  if active_mode == "do_nothing" then
    active_economy = {
      population = baseline.projected_population or current_economy.population,
      profit = baseline.projected_profit or current_economy.profit,
      industries = baseline.projected_industries or current_economy.industries or {}
    }
  elseif active_mode == "selected" and scenario then
    active_economy = {
      population = scenario.summary.projected_population or current_economy.population,
      profit = scenario.summary.projected_profit or current_economy.profit,
      industries = scenario.summary.projected_industries or current_economy.industries or {}
    }
  end

  return {
    baseline = baseline,
    scenario = scenario,
    card_push_snapshot = card_push_snapshot,
    active_mode = active_mode,
    active_snapshot = active_snapshot,
    active_summary = active_summary,
    current_economy = current_economy,
    active_economy = active_economy
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
  return terraforming_state:get_coupling_delta_for_edge(edge.source, edge.factor, snapshot)
end

local function compute_play_recommendations(limit)
  local recommendations = {}
  local baseline = terraforming_state:forecast_end_turn(terraforming_state.stats, {
    economy_state = terraforming_state:get_economy_snapshot()
  })
  local current_distance = math.abs(terraforming_state.stats[focused_stat] - terraforming_state.targets[focused_stat])

  for i, card in ipairs(player_deck.hand) do
    if can_afford(card.cost or 0) then
      local snapshot = copy_stats(terraforming_state.stats)
      local economy = terraforming_state:get_economy_snapshot()
      apply_card_to_snapshot(card, snapshot, economy)
      local summary = terraforming_state:forecast_end_turn(snapshot, { economy_state = economy })
      local next_distance = math.abs(summary.projected_stats[focused_stat] - terraforming_state.targets[focused_stat])
      local focus_gain = current_distance - next_distance
      local net_gain = summary.net - baseline.net
      local score = net_gain * 10 + focus_gain + summary.population_delta + math.floor(summary.profit_delta * 0.5)

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
  local economy = terraforming_state:get_economy_snapshot()

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
  love.graphics.print("Population: " .. tostring(economy.population) .. "    Profit: " .. tostring(economy.profit), 10, 90)
  draw_stats()

  local slot_parts = {}
  for i = 1, terraforming_state:get_industry_slot_count() do
    local industry = economy.industries[i]
    if industry then
      table.insert(slot_parts, tostring(i) .. ":" .. industry.name .. " " .. tostring(industry.health) .. "/" .. tostring(industry.max_health))
    else
      table.insert(slot_parts, tostring(i) .. ":Open")
    end
  end
  love.graphics.print("Industry Slots: " .. table.concat(slot_parts, " | "), 10, show_real_world_values and 270 or 210)

  if turn_summary then
    local summary_y = show_real_world_values and 320 or 250
    love.graphics.print("Last Turn Hazard: " .. turn_summary.hazard, 10, summary_y)
    love.graphics.print("Hazard Delta: " .. format_delta_list(turn_summary.hazard_deltas), 10, summary_y + 20)
    love.graphics.print("Coupling Delta: " .. format_delta_list(turn_summary.coupling_deltas), 10, summary_y + 40)
    love.graphics.print(
      "Growth " .. turn_summary.growth .. " - Penalty " .. turn_summary.penalty .. " = Net " .. format_signed(turn_summary.net),
      10,
      summary_y + 60
    )
    love.graphics.print(
      "Population " .. format_signed(turn_summary.population_delta or 0) ..
        " -> " .. tostring(turn_summary.projected_population or terraforming_state.population) ..
        " | Profit " .. format_signed(turn_summary.profit_delta or 0) ..
        " -> " .. tostring(turn_summary.projected_profit or terraforming_state.profit),
      10,
      summary_y + 80
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
  local marker_min_x = track_x + 5
  local marker_max_x = track_x + track_w - 5
  current_x = clamp_value(current_x, marker_min_x, marker_max_x)
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
    preview_x = clamp_value(preview_x, marker_min_x, marker_max_x)
    if math.abs(preview_x - current_x) < 3 then
      draw_diamond(preview_x, marker_y, 7, { 0.25, 0.48, 0.66, 0.15 }, { 0.45, 0.78, 1.0, 1 })
    else
      draw_diamond(preview_x, marker_y, 5, { 0.45, 0.78, 1.0, 1 }, { 0.05, 0.08, 0.12, 1 })
    end
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
  love.graphics.printf("Use Explain Graph for detailed coupling rules and focused primitive breakdown.", map_rect.x + 12, map_rect.y + 30, map_rect.w - 24, "left")

  local filter_fill = hovered_edge_filter_button and { 0.2, 0.3, 0.4, 0.95 } or { 0.14, 0.19, 0.27, 0.95 }
  love.graphics.setColor(unpack(filter_fill))
  love.graphics.rectangle("fill", toggle_buttons.filter.x, toggle_buttons.filter.y, toggle_buttons.filter.w, toggle_buttons.filter.h, 7, 7)
  love.graphics.setColor(0.7, 0.82, 0.96, 1)
  love.graphics.rectangle("line", toggle_buttons.filter.x, toggle_buttons.filter.y, toggle_buttons.filter.w, toggle_buttons.filter.h, 7, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Flow: " .. get_edge_filter_label(edge_filter_mode), toggle_buttons.filter.x + 8, toggle_buttons.filter.y + 6, toggle_buttons.filter.w - 12, "left")

  local graph_fill = show_graph_explain and { 0.24, 0.42, 0.26, 1 } or { 0.13, 0.18, 0.25, 1 }
  if hovered_graph_explain_button and not show_graph_explain then
    graph_fill = { 0.18, 0.24, 0.33, 1 }
  end
  local graph_border = show_graph_explain and { 0.65, 0.95, 0.64, 1 } or { 0.62, 0.78, 0.95, 1 }
  love.graphics.setColor(unpack(graph_fill))
  love.graphics.rectangle("fill", toggle_buttons.explain_graph.x, toggle_buttons.explain_graph.y, toggle_buttons.explain_graph.w, toggle_buttons.explain_graph.h, 7, 7)
  love.graphics.setColor(unpack(graph_border))
  love.graphics.rectangle("line", toggle_buttons.explain_graph.x, toggle_buttons.explain_graph.y, toggle_buttons.explain_graph.w, toggle_buttons.explain_graph.h, 7, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(show_graph_explain and "Hide Graph" or "Explain Graph", toggle_buttons.explain_graph.x + 4, toggle_buttons.explain_graph.y + 6, toggle_buttons.explain_graph.w - 8, "center")

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
  love.graphics.print("preview (card push)", map_rect.x + 136, marker_legend_y - 6)

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
    local preview_value = nil
    if forecast_ctx.active_mode == "selected" and forecast_ctx.card_push_snapshot then
      preview_value = forecast_ctx.card_push_snapshot[key]
    end
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

local function get_forecast_mode_label(active_mode)
  if active_mode == "do_nothing" then
    return "Do Nothing"
  elseif active_mode == "selected" then
    return "Selected Card"
  end
  return "Current"
end

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

local function build_population_snapshot_breakdown(snapshot)
  local quality = {}
  local scores = {}
  local primitive_sum = 0
  local good_count = 0

  for _, key in ipairs(STAT_ORDER) do
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
    table.insert(term_text, "S" .. tostring(i) .. " " .. format_signed(income))
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

local function draw_end_objective_metric_graph(rect, y, label, current_value, active_value, bar_color)
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

local function draw_end_objectives_explain_overlay(
  rect,
  mode_text,
  current_breakdown,
  active_breakdown,
  current_population,
  active_population,
  current_profit,
  active_profit,
  profit_delta,
  active_snapshot,
  active_industries,
  industry_report
)
  local panel_x = rect.x + 8
  local panel_y = rect.y + 8
  local panel_w = rect.w - 16
  local panel_h = rect.h - 50

  love.graphics.setColor(0.04, 0.06, 0.1, 1)
  love.graphics.rectangle("fill", panel_x, panel_y, panel_w, panel_h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", panel_x, panel_y, panel_w, panel_h, 10, 10)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Population + Profit Explainer (" .. mode_text .. ")", panel_x + 12, panel_y + 12, panel_w - 24, "left")

  local text_x = panel_x + 12
  local text_w = panel_w - 24
  local line_y = panel_y + 34
  local limit_y = panel_y + panel_h - 18
  local section_color = { 0.75, 0.87, 0.95, 1 }
  local body_color = { 1, 1, 1, 1 }

  line_y = draw_wrapped_line(
    "Population thresholds: Good <= " .. tostring(terraforming_state.population_good_threshold) ..
      " => +1, Ok <= " .. tostring(terraforming_state.population_ok_threshold) .. " => 0, Bad => -1.",
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

  if active_breakdown and active_snapshot then
    for _, key in ipairs(STAT_ORDER) do
      if line_y > limit_y then
        break
      end
      local value = active_snapshot[key] or 0
      local target = terraforming_state.targets[key] or 0
      local distance = math.abs(value - target)
      local quality = active_breakdown.quality[key]
      local score = active_breakdown.scores[key] or 0
      local detail_line =
        STAT_LABELS[key] .. ": value " .. format_signed(value) ..
        ", target " .. format_signed(target) ..
        ", |delta| " .. tostring(distance) ..
        " => " .. get_quality_label(quality) .. " (" .. format_signed(score) .. ")"
      line_y = draw_wrapped_line(detail_line, text_x, line_y, text_w, body_color, 16)
    end
  end

  if line_y > limit_y then
    return
  end

  if active_breakdown then
    local s = active_breakdown.scores or {}
    local c = (current_breakdown and current_breakdown.scores) or s
    line_y = draw_wrapped_line(
      "Current -> " .. mode_text .. " score shift: Heat " .. format_signed(c.heat or 0) .. " -> " .. format_signed(s.heat or 0) ..
        ", Air " .. format_signed(c.air or 0) .. " -> " .. format_signed(s.air or 0) ..
        ", Water " .. format_signed(c.water or 0) .. " -> " .. format_signed(s.water or 0) ..
        ", Soil " .. format_signed(c.soil or 0) .. " -> " .. format_signed(s.soil or 0) .. ".",
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
      "Synergy: if good_count >= 2 then synergy = min(4, good_count), else 0. good_count = " ..
        tostring(active_breakdown.good_count or 0) .. ", synergy = " .. format_signed(active_breakdown.synergy or 0) .. ".",
      text_x,
      line_y,
      text_w,
      body_color,
      16
    )
    if line_y > limit_y then
      return
    end

    line_y = draw_wrapped_line(
      "DeltaPopulation = +1 + primitive_sum + synergy = +1 + " ..
        format_signed(active_breakdown.primitive or 0) .. " + " ..
        format_signed(active_breakdown.synergy or 0) .. " = " .. format_signed(active_breakdown.delta or 0) .. ".",
      text_x,
      line_y,
      text_w,
      body_color,
      16
    )
    if line_y > limit_y then
      return
    end

    line_y = draw_wrapped_line(
      "NextPopulation = " .. tostring(current_population or 0) .. " + (" ..
        format_signed(active_breakdown.delta or 0) .. ") = " .. tostring(active_population or 0) .. ".",
      text_x,
      line_y,
      text_w,
      body_color,
      16
    )
    if line_y > limit_y then
      return
    end
  end

  line_y = draw_wrapped_line("Profit math terms:", text_x, line_y + 2, text_w, section_color, 16)
  if line_y > limit_y then
    return
  end
  line_y = draw_wrapped_line(
    "Per surviving slot: income = base_profit + round(pop_after_turn * population_factor). Destroyed/open slots contribute 0.",
    text_x,
    line_y,
    text_w,
    section_color,
    16
  )
  if line_y > limit_y then
    return
  end

  local slot_count = terraforming_state:get_industry_slot_count()
  if industry_report then
    local terms = {}
    for i = 1, slot_count do
      if line_y > limit_y then
        break
      end
      local report = industry_report[i]
      local industry = active_industries and active_industries[i] or nil
      local line
      local color = { 0.85, 0.9, 0.96, 1 }
      if report and not report.empty then
        if report.destroyed then
          line = "Slot " .. tostring(i) .. " " .. tostring(report.name or "Industry") .. ": destroyed => income 0."
          color = { 0.98, 0.55, 0.52, 1 }
          table.insert(terms, "S" .. tostring(i) .. " 0")
        else
          local base_income = industry and (industry.base_profit or 0) or 0
          local income = report.income or 0
          local pop_bonus = income - base_income
          line = "Slot " .. tostring(i) .. " " .. tostring(report.name or "Industry") ..
            ": income = " .. tostring(base_income) .. " + " .. tostring(pop_bonus) .. " = +" .. tostring(income)
          if (report.damage or 0) > 0 then
            line = line .. ", damage " .. tostring(report.damage)
            color = { 0.95, 0.84, 0.48, 1 }
          end
          if report.reasons and #report.reasons > 0 then
            line = line .. " (" .. table.concat(report.reasons, ", ") .. ")"
          end
          table.insert(terms, "S" .. tostring(i) .. " " .. format_signed(income))
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
      "DeltaProfit = " .. table.concat(terms, " + ") .. " = " .. format_signed(profit_delta or 0) .. ".",
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
      "NextProfit = " .. tostring(current_profit or 0) .. " + (" .. format_signed(profit_delta or 0) ..
        ") = " .. tostring(active_profit or 0) .. ".",
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

local function draw_end_objectives_panel(layout, forecast_ctx)
  local rect = layout.objectives_rect
  local mode_text = get_forecast_mode_label(forecast_ctx.active_mode)
  local active_snapshot = forecast_ctx.active_snapshot
  local active_summary = forecast_ctx.active_summary
  local current_population = forecast_ctx.current_economy.population
  local current_profit = forecast_ctx.current_economy.profit
  local active_population = forecast_ctx.active_economy.population
  local active_profit = forecast_ctx.active_economy.profit
  local slot_count = terraforming_state:get_industry_slot_count()
  local active_industries = forecast_ctx.active_economy.industries or {}
  local current_breakdown = build_population_snapshot_breakdown(terraforming_state.stats or {})
  local active_breakdown = build_population_snapshot_breakdown(active_snapshot or {})
  local population_delta = active_summary and (active_summary.population_delta or active_breakdown.delta) or active_breakdown.delta
  local profit_delta = active_summary and (active_summary.profit_delta or 0) or 0
  local industry_report = active_summary and active_summary.industry_report or nil
  local profit_breakdown = build_profit_snapshot_breakdown(active_summary, slot_count)

  local explain_button = get_objectives_explain_button(layout)

  love.graphics.setColor(0.06, 0.08, 0.12, 1)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 10, 10)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("End Objectives", rect.x + 14, rect.y + 12, rect.w - 28, "left")
  love.graphics.setColor(0.75, 0.87, 0.95, 1)
  love.graphics.printf(
    "Mode: " .. mode_text ..
      "  |  Habitability " .. tostring(terraforming_state.habitability) .. "/" .. tostring(terraforming_state.goal),
    rect.x + 14,
    rect.y + 34,
    rect.w - 28,
    "left"
  )

  draw_end_objective_metric_graph(rect, rect.y + 56, "Population", current_population, active_population, { 0.35, 0.66, 0.42 })
  draw_end_objective_metric_graph(rect, rect.y + 104, "Profit", current_profit, active_profit, { 0.66, 0.56, 0.24 })

  love.graphics.setColor(0.75, 0.87, 0.95, 1)
  love.graphics.printf(
    "Snapshot Equations (" .. mode_text .. ")",
    rect.x + 14,
    rect.y + 146,
    rect.w - 28,
    "left"
  )
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(
    "Population: Δ = +1 + " .. format_signed(active_breakdown.primitive) ..
      " + " .. format_signed(active_breakdown.synergy) .. " = " .. format_signed(population_delta) ..
      " | " .. tostring(current_population) .. " -> " .. tostring(active_population),
    rect.x + 14,
    rect.y + 162,
    rect.w - 28,
    "left"
  )
  if profit_breakdown then
    love.graphics.printf(
      "Profit: Δ = " .. table.concat(profit_breakdown.term_text, " + ") ..
        " = " .. format_signed(profit_breakdown.total) ..
        " | " .. tostring(current_profit) .. " -> " .. tostring(active_profit),
      rect.x + 14,
      rect.y + 178,
      rect.w - 28,
      "left"
    )
  else
    love.graphics.printf(
      "Profit: choose Do Nothing or a card to project slot income terms.",
      rect.x + 14,
      rect.y + 178,
      rect.w - 28,
      "left"
    )
  end

  love.graphics.setColor(0.75, 0.87, 0.95, 1)
  love.graphics.printf("Primitive Status Scores (-1 / 0 / +1)", rect.x + 14, rect.y + 198, rect.w - 28, "left")
  local tile_gap = 8
  local tile_w = math.floor((rect.w - 28 - (tile_gap * 3)) / 4)
  local tile_h = 56
  local tile_y = rect.y + 216
  for i, key in ipairs(STAT_ORDER) do
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
    love.graphics.printf(STAT_LABELS[key], tile_x + 6, tile_y + 5, tile_w - 12, "center")
    love.graphics.printf("Score " .. format_signed(active_score) .. " " .. get_quality_label(active_quality), tile_x + 6, tile_y + 22, tile_w - 12, "center")
    local score_text = "Cur " .. format_signed(current_score)
    if active_score ~= current_score then
      score_text = score_text .. " -> " .. format_signed(active_score)
    end
    love.graphics.printf(score_text, tile_x + 6, tile_y + 39, tile_w - 12, "center")
  end

  local slot_gap = 8
  local slot_w = math.floor((rect.w - 28 - ((slot_count - 1) * slot_gap)) / slot_count)
  local slot_h = 56
  local slot_y = rect.y + 286

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Industry Slots (per-slot profit term)", rect.x + 14, slot_y - 20, rect.w - 28, "left")
  for i = 1, terraforming_state:get_industry_slot_count() do
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
    love.graphics.printf(tostring(i), slot_x + 6, slot_y + 4, slot_w - 12, "left")
    if industry then
      local name_text = industry.name
      if #name_text > 18 then
        name_text = string.sub(name_text, 1, 17) .. "..."
      end
      love.graphics.printf(name_text, slot_x + 6, slot_y + 16, slot_w - 12, "center")
      love.graphics.printf("HP " .. tostring(industry.health) .. "/" .. tostring(industry.max_health), slot_x + 6, slot_y + 30, slot_w - 12, "center")
      love.graphics.printf("Δ$ " .. (term and format_signed(term.income or 0) or "?"), slot_x + 6, slot_y + 43, slot_w - 12, "center")
    else
      local destroyed = industry_report and industry_report[i] and industry_report[i].destroyed
      love.graphics.setColor(destroyed and 0.98 or 0.75, destroyed and 0.55 or 0.87, destroyed and 0.52 or 0.95, 1)
      love.graphics.printf(destroyed and "Destroyed" or "Open", slot_x + 6, slot_y + 22, slot_w - 12, "center")
      love.graphics.printf("Δ$ 0", slot_x + 6, slot_y + 43, slot_w - 12, "center")
    end
  end

  if show_objectives_explain then
    draw_end_objectives_explain_overlay(
      rect,
      mode_text,
      current_breakdown,
      active_breakdown,
      current_population,
      active_population,
      current_profit,
      active_profit,
      profit_delta,
      active_snapshot,
      active_industries,
      industry_report
    )
  end

  local explain_fill = show_objectives_explain and { 0.24, 0.42, 0.26, 1 } or { 0.13, 0.18, 0.25, 1 }
  if hovered_objectives_explain_button and not show_objectives_explain then
    explain_fill = { 0.18, 0.24, 0.33, 1 }
  end
  local explain_border = show_objectives_explain and { 0.65, 0.95, 0.64, 1 } or { 0.62, 0.78, 0.95, 1 }
  love.graphics.setColor(unpack(explain_fill))
  love.graphics.rectangle("fill", explain_button.x, explain_button.y, explain_button.w, explain_button.h, 7, 7)
  love.graphics.setColor(unpack(explain_border))
  love.graphics.rectangle("line", explain_button.x, explain_button.y, explain_button.w, explain_button.h, 7, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(show_objectives_explain and "Hide Objectives" or "Explain Objectives", explain_button.x + 4, explain_button.y + 6, explain_button.w - 8, "center")
end

local function draw_influence_details(rect, forecast_ctx)
  local snapshot = forecast_ctx.active_snapshot
  local value = snapshot[focused_stat]
  local help = INFLUENCE_HELP[focused_stat]
  local status, color = get_stat_status(focused_stat, value)
  local coupling_signal = terraforming_state:get_source_coupling_signal(focused_stat, snapshot)
  local coupling_rule_text = terraforming_state:get_coupling_rule_text(focused_stat)
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

  love.graphics.setColor(0.06, 0.08, 0.12, 1)
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

  if coupling_signal > 0 then
    love.graphics.setColor(0.45, 0.95, 0.45, 1)
    love.graphics.printf(
      "Coupling signal: +1 (supportive) from this source state.",
      rect.x + 14,
      rect.y + 112,
      rect.w - 28,
      "left"
    )
  elseif coupling_signal < 0 then
    love.graphics.setColor(0.98, 0.62, 0.42, 1)
    love.graphics.printf(
      "Coupling signal: -1 (stress) from this source state.",
      rect.x + 14,
      rect.y + 112,
      rect.w - 28,
      "left"
    )
  else
    love.graphics.setColor(0.98, 0.82, 0.35, 1)
    love.graphics.printf(
      "Coupling signal: 0 (inactive) at this source state.",
      rect.x + 14,
      rect.y + 112,
      rect.w - 28,
      "left"
    )
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(terraforming_state:get_coupling_rules_summary(), rect.x + 14, rect.y + 130, rect.w - 28, "left")
  love.graphics.printf(coupling_rule_text, rect.x + 14, rect.y + 146, rect.w - 28, "left")

  local summary_y = rect.y + 164
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

  if show_real_world_values then
    love.graphics.setColor(0.75, 0.87, 0.95, 1)
    love.graphics.printf(get_real_world_mapping(focused_stat, value), rect.x + 14, rect.y + rect.h - 24, rect.w - 28, "left")
  end
end

local function draw_forecast_panel(rect, forecast_ctx)
  local baseline = forecast_ctx.baseline
  local scenario = forecast_ctx.scenario
  local recommendations = compute_play_recommendations(3)
  local focused_target = terraforming_state.targets[focused_stat]
  local mode_buttons = get_forecast_mode_buttons(rect)
  local current_population = forecast_ctx.current_economy.population
  local current_profit = forecast_ctx.current_economy.profit

  love.graphics.setColor(0.06, 0.08, 0.12, 1)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 10, 10)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("End-Turn Forecast", rect.x + 14, rect.y + 12, rect.w - 28, "left")
  love.graphics.printf("Hazard: " .. baseline.hazard, rect.x + 14, rect.y + 34, rect.w - 28, "left")
  love.graphics.setColor(0.75, 0.87, 0.95, 1)
  love.graphics.printf("Map reference mode: " .. get_forecast_mode_label(forecast_ctx.active_mode), rect.x + 210, rect.y + 34, rect.w - 224, "left")
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
  love.graphics.printf(
    "Population: " .. tostring(current_population) .. " -> " .. tostring(baseline.projected_population) ..
      " (" .. format_signed(baseline.population_delta or 0) .. ")",
    rect.x + 14,
    left_y + 34,
    rect.w * 0.46,
    "left"
  )
  love.graphics.printf(
    "Profit: " .. tostring(current_profit) .. " -> " .. tostring(baseline.projected_profit) ..
      " (" .. format_signed(baseline.profit_delta or 0) .. ")",
    rect.x + 14,
    left_y + 50,
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
    love.graphics.printf(
      "Population: " .. tostring(current_population) .. " -> " .. tostring(scenario.summary.projected_population) ..
        " (" .. format_signed(scenario.summary.population_delta or 0) .. ")",
      split_x + 8,
      right_y + 34,
      rect.w * 0.46 - 12,
      "left"
    )
    love.graphics.printf(
      "Profit: " .. tostring(current_profit) .. " -> " .. tostring(scenario.summary.projected_profit) ..
        " (" .. format_signed(scenario.summary.profit_delta or 0) .. ")",
      split_x + 8,
      right_y + 50,
      rect.w * 0.46 - 12,
      "left"
    )
  else
    love.graphics.printf("Select a card below to preview a one-card outcome.", split_x + 8, rect.y + 102, rect.w * 0.46 - 12, "left")
  end

  local rec_start_y = rect.y + 214
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
  local explain_button = get_preview_explain_button(layout)

  love.graphics.setColor(0.06, 0.08, 0.12, 0.92)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 10, 10)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Preview Selector (Do Nothing or card). Use Current above to clear preview.", rect.x + 10, rect.y + 10, rect.w - 20, "left")

  local turn_fill = show_turn_explain and { 0.24, 0.42, 0.26, 1 } or { 0.13, 0.18, 0.25, 1 }
  if hovered_turn_explain_button and not show_turn_explain then
    turn_fill = { 0.18, 0.24, 0.33, 1 }
  end
  local turn_border = show_turn_explain and { 0.65, 0.95, 0.64, 1 } or { 0.62, 0.78, 0.95, 1 }
  love.graphics.setColor(unpack(turn_fill))
  love.graphics.rectangle("fill", explain_button.x, explain_button.y, explain_button.w, explain_button.h, 7, 7)
  love.graphics.setColor(unpack(turn_border))
  love.graphics.rectangle("line", explain_button.x, explain_button.y, explain_button.w, explain_button.h, 7, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(show_turn_explain and "Hide Turn" or "Explain Next Turn", explain_button.x + 4, explain_button.y + 6, explain_button.w - 8, "center")

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
  love.graphics.print("Click primitive to focus. Arrows show current coupling; blue marker shows card push.", 16, 32)
  love.graphics.print("Use Explain Graph, Explain Next Turn, and Explain Objectives for detailed breakdowns.", 16, 52)
  love.graphics.print("M mapping, C clear card, I flow, Z current, X do nothing, P selected card, V gameplay.", 16, 72)

  draw_influence_nodes(layout, forecast_ctx)
  draw_end_objectives_panel(layout, forecast_ctx)
  if show_graph_explain then
    draw_influence_details(layout.graph_explain_rect, forecast_ctx)
  end
  if show_turn_explain then
    draw_forecast_panel(layout.turn_explain_rect, forecast_ctx)
  end
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
  hovered_graph_explain_button = false
  hovered_turn_explain_button = false
  hovered_objectives_explain_button = false

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
    hovered_graph_explain_button = point_in_rect(mx, my, toggle_buttons.explain_graph.x, toggle_buttons.explain_graph.y, toggle_buttons.explain_graph.w, toggle_buttons.explain_graph.h)

    local explain_button = get_preview_explain_button(layout)
    hovered_turn_explain_button = point_in_rect(mx, my, explain_button.x, explain_button.y, explain_button.w, explain_button.h)

    local objectives_explain_button = get_objectives_explain_button(layout)
    hovered_objectives_explain_button = point_in_rect(
      mx,
      my,
      objectives_explain_button.x,
      objectives_explain_button.y,
      objectives_explain_button.w,
      objectives_explain_button.h
    )

    if show_turn_explain then
      local forecast_buttons = get_forecast_mode_buttons(layout.turn_explain_rect)
      for _, button in ipairs(forecast_buttons) do
        if point_in_rect(mx, my, button.x, button.y, button.w, button.h) then
          hovered_forecast_mode = button.id
          break
        end
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

    if point_in_rect(x, y, toggle_buttons.explain_graph.x, toggle_buttons.explain_graph.y, toggle_buttons.explain_graph.w, toggle_buttons.explain_graph.h) then
      show_graph_explain = not show_graph_explain
      if show_graph_explain then
        show_turn_explain = false
      end
      return
    end

    local explain_button = get_preview_explain_button(layout)
    if point_in_rect(x, y, explain_button.x, explain_button.y, explain_button.w, explain_button.h) then
      show_turn_explain = not show_turn_explain
      if show_turn_explain then
        show_graph_explain = false
      end
      return
    end

    local objectives_explain_button = get_objectives_explain_button(layout)
    if point_in_rect(
      x,
      y,
      objectives_explain_button.x,
      objectives_explain_button.y,
      objectives_explain_button.w,
      objectives_explain_button.h
    ) then
      show_objectives_explain = not show_objectives_explain
      return
    end

    if show_turn_explain then
      local forecast_buttons = get_forecast_mode_buttons(layout.turn_explain_rect)
      for _, button in ipairs(forecast_buttons) do
        if point_in_rect(x, y, button.x, button.y, button.w, button.h) then
          selected_forecast_card_index = nil
          forecast_mode = "current"
          return
        end
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
