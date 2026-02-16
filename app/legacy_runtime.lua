local Runtime = {}

local Deck = require("deck")
local Card = require("card")
local CardTypes = require("card_types")
local TerraformingTarget = require("terraforming_target")
local DrawHelpers = require("draw_helpers")
local Background = require("background")
local TerraformingState = require("terraforming_state")
local Viewport = require("viewport")
local Worlds = require("content.worlds")
local CouplingRules = require("content.coupling_rules")
local PreviewContextSystem = require("systems.preview_context_system")
local ActionApplier = require("systems.action_applier")
local InfluenceUIState = require("app.influence_ui_state")
local InfluenceLayout = require("ui.layout.influence_layout")
local GameplayLayout = require("ui.layout.gameplay_layout")
local CardLibraryLayout = require("ui.layout.card_library_layout")
local CardLibraryState = require("app.card_library_state")
local DeckWidget = require("ui.components.deck_widget")
local EnergyOrb = require("ui.components.energy_orb")
local HazardCard = require("ui.components.hazard_card")
local GameplayHUD = require("ui.components.gameplay_hud")
local ObjectivesPanel = require("ui.components.objectives_panel")
local InfluenceExplain = require("ui.components.influence_explain")

local VIEWPORT_REF_W = 1728
local VIEWPORT_REF_H = 798
local VIEWPORT_SAFE_INSETS = {
  left = 96,
  right = 96,
  top = 20,
  bottom = 20
}

local STAT_ORDER = { "heat", "air", "water", "soil" }
local STAT_LABELS = {
  heat = "Heat",
  air = "Air",
  water = "Water",
  soil = "Soil"
}

local INFLUENCE_EDGES = {
  { source = "heat", target = "water", factor = 1, text = "Heat -> Water", curve = 0 },
  { source = "heat", target = "soil", factor = 1, text = "Heat -> Soil", curve = 68 },
  { source = "air", target = "heat", factor = 1, text = "Air -> Heat", curve = 0 },
  { source = "air", target = "water", factor = 1, text = "Air -> Water", curve = -72 },
  { source = "water", target = "soil", factor = 1, text = "Water -> Soil", curve = 0 },
  { source = "water", target = "air", factor = 1, text = "Water -> Air", curve = 72 },
  { source = "soil", target = "air", factor = 1, text = "Soil -> Air", curve = 0 }
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
    magnetosphere_level = 3,
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
    magnetosphere_level = 2,
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
    magnetosphere_level = 1,
    targets = { heat = 0, air = 0, water = 0, soil = 0 },
    starting_ranges = {
      heat = { min = -8, max = 8 },
      air = { min = -10, max = -3 },
      water = { min = -8, max = 8 },
      soil = { min = -10, max = -3 }
    }
  }
}

INFLUENCE_EDGES = CouplingRules.edges
INFLUENCE_HELP = CouplingRules.help
WORLD_CONFIGS = Worlds

local player_deck
local target
local terraforming_state
local viewport
local world_index = 1
local campaign_state = "playing" -- playing | world_won | campaign_won | campaign_lost
local turn_summary = nil
local view_mode = "gameplay" -- gameplay | influence
local show_real_world_values = false
local influence_ui = InfluenceUIState.new()

local hovered_card_index = nil
local hovered_draw_pile = false
local hovered_discard_pile = false
local hovered_end_turn = false

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
  width = 90,
  height = 120
}

local END_TURN_UI = {
  width = 170,
  height = 50,
  x_padding = 30,
  y = 520
}

local function detect_launch_mode()
  local env_mode = string.lower(os.getenv("TERRAFORM_TREK_MODE") or os.getenv("TT_MODE") or "")
  if env_mode == "cards" or env_mode == "card_library" or env_mode == "library" then
    return "cards"
  end

  local argv = rawget(_G, "arg")
  if type(argv) == "table" then
    for _, value in ipairs(argv) do
      local token = string.lower(tostring(value))
      if token == "cards" or token == "card_library" or token == "card-library" or token == "library" then
        return "cards"
      end
    end
  end

  return "game"
end

local launch_mode = detect_launch_mode() -- game | cards

local initialize_card_library_state
local card_library_state = CardLibraryState.new()

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

local function get_safe_rect()
  if viewport then
    return viewport:get_safe_rect()
  end
  return { x = 0, y = 0, w = VIEWPORT_REF_W, h = VIEWPORT_REF_H }
end

local function update_target_layout()
  if not target then
    return
  end
  local planet = GameplayLayout.get_planet(get_safe_rect())
  target.x = planet.x
  target.y = planet.y
  target.radius = planet.radius
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

local function get_hazard_origin_label(origin)
  local labels = {
    space = "Spaceborne",
    atmospheric = "Atmospheric",
    climate = "Climate",
    geologic = "Geologic",
    biological = "Biological",
    chemical = "Chemical",
    planetary = "Planetary"
  }
  return labels[origin] or "Hazard"
end

local function get_hazard_card_rect()
  return GameplayLayout.get_hazard_card_rect(get_safe_rect(), {
    x = target.x,
    y = target.y,
    radius = target.radius
  })
end

local function draw_next_hazard_card()
  local projection = terraforming_state:preview_next_hazard()
  local rect = get_hazard_card_rect()
  local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 3.1)
  HazardCard.draw({
    rect = rect,
    projection = projection,
    target = { x = target.x, y = target.y, radius = target.radius },
    pulse = pulse,
    format_delta_list = format_delta_list,
    magnetosphere_level = terraforming_state:get_magnetosphere_level(),
    magnetosphere_tier = terraforming_state:get_magnetosphere_tier(terraforming_state:get_magnetosphere_level())
  })
end

local function edge_is_visible(edge)
  return influence_ui:edge_is_visible(edge)
end

local function get_hand_layout(num_cards)
  return GameplayLayout.get_hand_layout(get_safe_rect(), num_cards, HAND_UI)
end

local function get_draw_pile_rect()
  return GameplayLayout.get_deck_rect(get_safe_rect(), PILE_UI)
end

local function get_discard_pile_rect()
  return GameplayLayout.get_discard_rect(get_safe_rect(), PILE_UI)
end

local function get_end_turn_rect()
  local hand_layout = get_hand_layout(#player_deck.hand)
  return GameplayLayout.get_end_turn_rect(get_safe_rect(), hand_layout, HAND_UI, END_TURN_UI)
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
  return InfluenceLayout.compute(get_safe_rect())
end

local function get_map_toggle_buttons(layout)
  return InfluenceLayout.get_map_toggle_buttons(layout)
end

local function get_forecast_mode_buttons(rect)
  return InfluenceLayout.get_forecast_mode_buttons(rect)
end

local function get_preview_explain_button(layout)
  return InfluenceLayout.get_preview_explain_button(layout)
end

local function get_objectives_explain_button(layout)
  return InfluenceLayout.get_objectives_explain_button(layout)
end

local function get_influence_card_rects(layout)
  return InfluenceLayout.get_card_rects(layout, player_deck.hand)
end

local function setup_world(index)
  world_index = index
  local config = WORLD_CONFIGS[index]
  terraforming_state = TerraformingState.new(config)
  turn_summary = nil
  campaign_state = "playing"
  influence_ui:reset_for_new_campaign()

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
  influence_ui:set_current_mode()

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

local function get_forecast_context()
  return PreviewContextSystem.build(
    terraforming_state,
    player_deck.hand,
    influence_ui.selected_forecast_card_index,
    influence_ui.forecast_mode,
    can_afford
  )
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

local function get_context_edge_delta(forecast_ctx, edge)
  local key = edge.source .. "->" .. edge.target
  local edge_deltas = forecast_ctx and forecast_ctx.active_edge_deltas or {}
  return edge_deltas[key] or 0
end

local function compute_play_recommendations(limit)
  local recommendations = {}
  local baseline = terraforming_state:forecast_end_turn(terraforming_state.stats, {
    economy_state = terraforming_state:get_economy_snapshot()
  })
  local current_distance = math.abs(terraforming_state.stats[influence_ui.focused_stat] - terraforming_state.targets[influence_ui.focused_stat])

  for i, card in ipairs(player_deck.hand) do
    if can_afford(card.cost or 0) then
      local snapshot = copy_stats(terraforming_state.stats)
      local economy = terraforming_state:get_economy_snapshot()
      ActionApplier.apply_card_preview(terraforming_state, card, snapshot, economy)
      local summary = terraforming_state:forecast_end_turn(snapshot, { economy_state = economy })
      local next_distance = math.abs(summary.projected_stats[influence_ui.focused_stat] - terraforming_state.targets[influence_ui.focused_stat])
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
    influence_ui:set_current_mode()
    return true
  end

  return false
end

local function enforce_window_mode()
  if not (love.window and love.window.getMode and love.window.setMode) then
    return
  end

  local width, height, flags = love.window.getMode()
  if width == VIEWPORT_REF_W and height == VIEWPORT_REF_H then
    return
  end

  local desired_flags = flags or {}
  desired_flags.resizable = false
  desired_flags.fullscreen = false
  desired_flags.vsync = true
  desired_flags.highdpi = true
  desired_flags.fullscreentype = desired_flags.fullscreentype or "desktop"
  love.window.setMode(VIEWPORT_REF_W, VIEWPORT_REF_H, desired_flags)
end

function Runtime.load()
  love.math.setRandomSeed(os.time())
  enforce_window_mode()
  viewport = Viewport.new(VIEWPORT_REF_W, VIEWPORT_REF_H, VIEWPORT_SAFE_INSETS)
  viewport:update(love.graphics.getDimensions())
  Background.load()

  if launch_mode == "cards" then
    initialize_card_library_state()
    if love.window and love.window.setTitle then
      love.window.setTitle("Terraform Trek - Card Library")
    end
    return
  end

  player_deck = Deck:new()
  target = TerraformingTarget:new()
  start_campaign()
end

function Runtime.resize(w, h)
  if viewport then
    viewport:update(w, h)
  end
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

local function draw_card_pile_widget(rect, label, count, is_hovered)
  DeckWidget.draw(rect, label, count, is_hovered)
end

local function draw_energy_orb()
  local draw_rect = get_draw_pile_rect()
  local cx = draw_rect.x + math.floor(draw_rect.w * 0.5)
  local cy = draw_rect.y - 26
  EnergyOrb.draw(cx, cy, current_energy, max_energy)
end

local function draw_pile_widgets()
  draw_card_pile_widget(get_draw_pile_rect(), "DECK", #player_deck.draw_pile, hovered_draw_pile)
  draw_card_pile_widget(get_discard_pile_rect(), "DISCARD", #player_deck.discard_pile, hovered_discard_pile)
  draw_energy_orb()
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
  GameplayHUD.draw_hud({
    safe_rect = get_safe_rect(),
    world_index = world_index,
    world_count = #WORLD_CONFIGS,
    world_config = WORLD_CONFIGS[world_index],
    terraforming_state = terraforming_state,
    hazard_projection = terraforming_state:preview_next_hazard(),
    economy_snapshot = terraforming_state:get_economy_snapshot(),
    turn_summary = turn_summary,
    show_real_world_values = show_real_world_values,
    stat_order = STAT_ORDER,
    stat_labels = STAT_LABELS,
    get_stat_status = get_stat_status,
    format_signed = format_signed,
    get_real_world_mapping = get_real_world_mapping,
    format_delta_list = format_delta_list,
    get_hazard_origin_label = get_hazard_origin_label
  })
end

local function draw_controls_hint()
  local safe = get_safe_rect()
  local hand_layout = get_hand_layout(#player_deck.hand)
  GameplayHUD.draw_controls_hint({
    safe_rect = safe,
    hand_base_y = hand_layout.base_y,
    clamp_value = clamp_value
  })
end

local function draw_status_overlay()
  GameplayHUD.draw_status_overlay({
    screen_w = love.graphics.getWidth(),
    campaign_state = campaign_state
  })
end

local function draw_influence_edge(source, target, edge, highlight, current_delta)
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
  local projection_label = "Viewing Current State"
  if forecast_ctx.active_mode ~= "current" then
    projection_label = "Viewing End-Turn Projection"
  end

  love.graphics.setColor(0.06, 0.08, 0.12, 0.88)
  love.graphics.rectangle("fill", map_rect.x, map_rect.y, map_rect.w, map_rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", map_rect.x, map_rect.y, map_rect.w, map_rect.h, 10, 10)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Core Influence Graph", map_rect.x + 12, map_rect.y + 10, map_rect.w - 24, "left")
  love.graphics.printf("Use Explain Graph for detailed coupling rules and focused primitive breakdown.", map_rect.x + 12, map_rect.y + 30, map_rect.w - 24, "left")
  love.graphics.setColor(0.75, 0.87, 0.95, 1)
  love.graphics.printf(projection_label, map_rect.x + 12, map_rect.y + 48, map_rect.w - 24, "left")

  local filter_fill = influence_ui.hovered_edge_filter_button and { 0.2, 0.3, 0.4, 0.95 } or { 0.14, 0.19, 0.27, 0.95 }
  love.graphics.setColor(unpack(filter_fill))
  love.graphics.rectangle("fill", toggle_buttons.filter.x, toggle_buttons.filter.y, toggle_buttons.filter.w, toggle_buttons.filter.h, 7, 7)
  love.graphics.setColor(0.7, 0.82, 0.96, 1)
  love.graphics.rectangle("line", toggle_buttons.filter.x, toggle_buttons.filter.y, toggle_buttons.filter.w, toggle_buttons.filter.h, 7, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Flow: " .. influence_ui:get_edge_filter_label(), toggle_buttons.filter.x + 8, toggle_buttons.filter.y + 6, toggle_buttons.filter.w - 12, "left")

  local graph_fill = influence_ui.show_graph_explain and { 0.24, 0.42, 0.26, 1 } or { 0.13, 0.18, 0.25, 1 }
  if influence_ui.hovered_graph_explain_button and not influence_ui.show_graph_explain then
    graph_fill = { 0.18, 0.24, 0.33, 1 }
  end
  local graph_border = influence_ui.show_graph_explain and { 0.65, 0.95, 0.64, 1 } or { 0.62, 0.78, 0.95, 1 }
  love.graphics.setColor(unpack(graph_fill))
  love.graphics.rectangle("fill", toggle_buttons.explain_graph.x, toggle_buttons.explain_graph.y, toggle_buttons.explain_graph.w, toggle_buttons.explain_graph.h, 7, 7)
  love.graphics.setColor(unpack(graph_border))
  love.graphics.rectangle("line", toggle_buttons.explain_graph.x, toggle_buttons.explain_graph.y, toggle_buttons.explain_graph.w, toggle_buttons.explain_graph.h, 7, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(influence_ui.show_graph_explain and "Hide Graph" or "Explain Graph", toggle_buttons.explain_graph.x + 4, toggle_buttons.explain_graph.y + 6, toggle_buttons.explain_graph.w - 8, "center")

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
  love.graphics.print("0 neutral", map_rect.x + 304, map_rect.y + 51)

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
      local highlight = edge.source == influence_ui.focused_stat or edge.target == influence_ui.focused_stat
      local edge_delta = get_context_edge_delta(forecast_ctx, edge)
      draw_influence_edge(source, target, edge, highlight, edge_delta)
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
    local is_focused = key == influence_ui.focused_stat
    local is_hovered = key == influence_ui.hovered_influence_stat

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

initialize_card_library_state = function()
  CardLibraryState.initialize(card_library_state, {
    card_types = CardTypes,
    card_class = Card,
    stat_labels = STAT_LABELS
  })
end

local function get_card_library_filtered_entries()
  return CardLibraryState.get_filtered_entries(card_library_state)
end

local function ensure_card_library_selection(filtered)
  CardLibraryState.ensure_selection(card_library_state, filtered)
end

local function get_card_library_layout()
  local sw, sh = love.graphics.getDimensions()
  local font = love.graphics.getFont()
  return CardLibraryLayout.compute_for_window(sw, sh, card_library_state.topics, function(text)
    return font:getWidth(text)
  end)
end

local function get_card_library_card_rects(layout, filtered_entries)
  return CardLibraryLayout.get_card_rects(layout.grid_rect, filtered_entries, card_library_state.scroll_offset)
end

local function get_card_library_selected_entry(filtered_entries)
  return CardLibraryState.get_selected_entry(card_library_state, filtered_entries)
end

local function update_card_library_hover_state()
  local mx, my = love.mouse.getPosition()
  local layout = get_card_library_layout()
  local filtered_entries = get_card_library_filtered_entries()
  ensure_card_library_selection(filtered_entries)
  local card_rects, max_scroll = get_card_library_card_rects(layout, filtered_entries)
  CardLibraryState.set_max_scroll(card_library_state, max_scroll)
  CardLibraryState.reset_hover(card_library_state)

  for _, filter_rect in ipairs(layout.filter_rects) do
    if point_in_rect(mx, my, filter_rect.x, filter_rect.y, filter_rect.w, filter_rect.h) then
      card_library_state.hovered_topic = filter_rect.topic
      break
    end
  end

  local grid_rect = layout.grid_rect
  for _, rect in ipairs(card_rects) do
    local visible = rect.y + rect.h >= grid_rect.y and rect.y <= grid_rect.y + grid_rect.h
    if visible and point_in_rect(mx, my, rect.x, rect.y, rect.w, rect.h) then
      card_library_state.hovered_card_id = rect.entry.id
      break
    end
  end
end

local function draw_card_library_screen()
  local layout = get_card_library_layout()
  local filtered_entries = get_card_library_filtered_entries()
  ensure_card_library_selection(filtered_entries)
  local card_rects, max_scroll = get_card_library_card_rects(layout, filtered_entries)
  CardLibraryState.set_max_scroll(card_library_state, max_scroll)
  local selected_entry = get_card_library_selected_entry(filtered_entries)

  Background.draw_fill()
  Background.draw_stars()

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("Card Library", 16, 12)
  love.graphics.print("Browse all cards or filter by topic. Click a card to inspect details.", 16, 32)
  love.graphics.print("Filters + mouse wheel. Press ESC to quit this mode.", 16, 52)

  for _, filter_rect in ipairs(layout.filter_rects) do
    local active = card_library_state.selected_topic == filter_rect.topic
    local hovered = card_library_state.hovered_topic == filter_rect.topic
    local fill = active and { 0.24, 0.42, 0.26, 0.98 } or { 0.13, 0.18, 0.25, 0.98 }
    local border = active and { 0.65, 0.95, 0.64, 1 } or { 0.62, 0.78, 0.95, 1 }
    if hovered and not active then
      fill = { 0.18, 0.24, 0.33, 0.98 }
    end
    love.graphics.setColor(unpack(fill))
    love.graphics.rectangle("fill", filter_rect.x, filter_rect.y, filter_rect.w, filter_rect.h, 7, 7)
    love.graphics.setColor(unpack(border))
    love.graphics.rectangle("line", filter_rect.x, filter_rect.y, filter_rect.w, filter_rect.h, 7, 7)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(filter_rect.topic, filter_rect.x + 4, filter_rect.y + 6, filter_rect.w - 8, "center")
  end

  local grid_rect = layout.grid_rect
  love.graphics.setColor(0.06, 0.08, 0.12, 0.95)
  love.graphics.rectangle("fill", grid_rect.x, grid_rect.y, grid_rect.w, grid_rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", grid_rect.x, grid_rect.y, grid_rect.w, grid_rect.h, 10, 10)
  love.graphics.setColor(0.75, 0.87, 0.95, 1)
  love.graphics.printf(
    "Cards: " .. tostring(#filtered_entries) .. "/" .. tostring(#card_library_state.cards) .. "  |  Topic: " .. card_library_state.selected_topic,
    grid_rect.x + 10,
    grid_rect.y + 8,
    grid_rect.w - 20,
    "left"
  )

  local scissor_y = grid_rect.y + 28
  local scissor_h = grid_rect.h - 36
  love.graphics.setScissor(grid_rect.x + 2, scissor_y, grid_rect.w - 4, scissor_h)
  for _, rect in ipairs(card_rects) do
    local visible = rect.y + rect.h >= scissor_y and rect.y <= scissor_y + scissor_h
    if visible then
      rect.entry.card:draw(rect.x, rect.y)
      local selected = card_library_state.selected_card_id == rect.entry.id
      local hovered = card_library_state.hovered_card_id == rect.entry.id
      if selected or hovered then
        local color = selected and { 0.64, 0.94, 0.63, 1 } or { 0.7, 0.82, 0.98, 1 }
        love.graphics.setColor(unpack(color))
        love.graphics.setLineWidth(selected and 3 or 2)
        love.graphics.rectangle("line", rect.x - 3, rect.y - 3, rect.w + 6, rect.h + 6, 6, 6)
        love.graphics.setLineWidth(1)
      end
    end
  end
  love.graphics.setScissor()

  if card_library_state.max_scroll > 0 then
    local track_x = grid_rect.x + grid_rect.w - 8
    local track_y = scissor_y + 4
    local track_h = scissor_h - 8
    local thumb_h = math.max(30, math.floor(track_h * (scissor_h / (scissor_h + card_library_state.max_scroll))))
    local thumb_t = card_library_state.scroll_offset / card_library_state.max_scroll
    local thumb_y = track_y + math.floor((track_h - thumb_h) * thumb_t)
    love.graphics.setColor(0.16, 0.22, 0.3, 0.95)
    love.graphics.rectangle("fill", track_x, track_y, 4, track_h, 3, 3)
    love.graphics.setColor(0.65, 0.78, 0.95, 0.95)
    love.graphics.rectangle("fill", track_x, thumb_y, 4, thumb_h, 3, 3)
  end

  local detail_rect = layout.detail_rect
  love.graphics.setColor(0.06, 0.08, 0.12, 0.95)
  love.graphics.rectangle("fill", detail_rect.x, detail_rect.y, detail_rect.w, detail_rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", detail_rect.x, detail_rect.y, detail_rect.w, detail_rect.h, 10, 10)

  local text_x = detail_rect.x + 12
  local text_w = detail_rect.w - 24
  local y = detail_rect.y + 12

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Card Detail", text_x, y, text_w, "left")
  y = y + 22

  if not selected_entry then
    love.graphics.setColor(0.75, 0.87, 0.95, 1)
    love.graphics.printf("No cards match this filter.", text_x, y, text_w, "left")
    return
  end

  local data = selected_entry.data
  local topic_list = {}
  for topic, _ in pairs(selected_entry.topics) do
    table.insert(topic_list, topic)
  end
  table.sort(topic_list)

  y = draw_wrapped_line(data.name .. "  (Cost " .. tostring(data.cost or 0) .. ")", text_x, y, text_w, { 1, 1, 1, 1 }, 16)
  y = draw_wrapped_line("Category: " .. tostring(data.category), text_x, y + 2, text_w, { 0.75, 0.87, 0.95, 1 }, 16)
  y = draw_wrapped_line("ID: " .. tostring(data.id), text_x, y, text_w, { 0.75, 0.87, 0.95, 1 }, 16)
  y = draw_wrapped_line("Topics: " .. table.concat(topic_list, ", "), text_x, y, text_w, { 0.75, 0.87, 0.95, 1 }, 16)
  y = draw_wrapped_line("Description: " .. tostring(data.description), text_x, y + 6, text_w, { 1, 1, 1, 1 }, 16)
  y = draw_wrapped_line("Effect: " .. tostring(data.effect_fn_name), text_x, y + 6, text_w, { 0.75, 0.87, 0.95, 1 }, 16)

  local properties = data.properties or {}
  if properties.stat_changes then
    local change_parts = {}
    for _, key in ipairs(STAT_ORDER) do
      local delta = properties.stat_changes[key]
      if delta and delta ~= 0 then
        table.insert(change_parts, (STAT_LABELS[key] or key) .. " " .. format_signed(delta))
      end
    end
    if #change_parts > 0 then
      y = draw_wrapped_line("Stat changes: " .. table.concat(change_parts, ", "), text_x, y, text_w, { 1, 1, 1, 1 }, 16)
    end
  end

  if properties.draw_amount then
    y = draw_wrapped_line("Draw amount: " .. tostring(properties.draw_amount), text_x, y, text_w, { 1, 1, 1, 1 }, 16)
  end

  if properties.industry_def then
    local industry = properties.industry_def
    y = draw_wrapped_line(
      "Industry: base " .. tostring(industry.base_profit or 0) ..
        ", pop factor " .. tostring(industry.population_factor or 0) ..
        ", HP " .. tostring(industry.max_health or industry.health or 0),
      text_x,
      y + 4,
      text_w,
      { 1, 1, 1, 1 },
      16
    )
    if industry.damage_rules and #industry.damage_rules > 0 then
      y = draw_wrapped_line("Damage rules:", text_x, y + 2, text_w, { 0.75, 0.87, 0.95, 1 }, 16)
      for _, rule in ipairs(industry.damage_rules) do
        local stat_label = STAT_LABELS[rule.stat] or tostring(rule.stat)
        local conditions = {}
        if rule.min ~= nil then
          table.insert(conditions, stat_label .. " >= " .. tostring(rule.min))
        end
        if rule.max ~= nil then
          table.insert(conditions, stat_label .. " <= " .. tostring(rule.max))
        end
        local cond_text = table.concat(conditions, " and ")
        local rule_text = "- " .. cond_text .. ": -" .. tostring(rule.damage or 1) .. " HP"
        if rule.reason and rule.reason ~= "" then
          rule_text = rule_text .. " (" .. rule.reason .. ")"
        end
        y = draw_wrapped_line(rule_text, text_x, y, text_w, { 1, 1, 1, 1 }, 16)
        if y > detail_rect.y + detail_rect.h - 20 then
          break
        end
      end
    end
  end
end

local function handle_card_library_mousepressed(x, y)
  local layout = get_card_library_layout()
  local filtered_entries = get_card_library_filtered_entries()
  ensure_card_library_selection(filtered_entries)
  local card_rects, max_scroll = get_card_library_card_rects(layout, filtered_entries)
  CardLibraryState.set_max_scroll(card_library_state, max_scroll)

  for _, filter_rect in ipairs(layout.filter_rects) do
    if point_in_rect(x, y, filter_rect.x, filter_rect.y, filter_rect.w, filter_rect.h) then
      CardLibraryState.select_topic(card_library_state, filter_rect.topic)
      local refreshed = get_card_library_filtered_entries()
      ensure_card_library_selection(refreshed)
      return
    end
  end

  local grid_rect = layout.grid_rect
  for _, rect in ipairs(card_rects) do
    local visible = rect.y + rect.h >= grid_rect.y and rect.y <= grid_rect.y + grid_rect.h
    if visible and point_in_rect(x, y, rect.x, rect.y, rect.w, rect.h) then
      CardLibraryState.select_card(card_library_state, rect.entry.id)
      return
    end
  end
end

local function handle_card_library_wheel(y)
  CardLibraryState.scroll_by(card_library_state, y, 44)
end

local function handle_card_library_keypressed(key)
  if key == "escape" then
    love.event.quit()
    return
  end

  if key == "up" then
    handle_card_library_wheel(1)
    return
  elseif key == "down" then
    handle_card_library_wheel(-1)
    return
  end

  if key == "left" then
    CardLibraryState.cycle_topic(card_library_state, -1)
    local filtered = get_card_library_filtered_entries()
    ensure_card_library_selection(filtered)
    return
  elseif key == "right" then
    CardLibraryState.cycle_topic(card_library_state, 1)
    local filtered = get_card_library_filtered_entries()
    ensure_card_library_selection(filtered)
    return
  end
end


local function draw_end_objectives_panel(layout, forecast_ctx)
  ObjectivesPanel.draw({
    rect = layout.objectives_rect,
    layout = layout,
    forecast_ctx = forecast_ctx,
    influence_ui = influence_ui,
    terraforming_state = terraforming_state,
    stat_order = STAT_ORDER,
    stat_labels = STAT_LABELS,
    format_signed = format_signed,
    clamp_value = clamp_value,
    get_forecast_mode_label = get_forecast_mode_label,
    get_objectives_explain_button = get_objectives_explain_button
  })
end

local function draw_influence_details(rect, forecast_ctx)
  InfluenceExplain.draw_details({
    rect = rect,
    forecast_ctx = forecast_ctx,
    influence_ui = influence_ui,
    terraforming_state = terraforming_state,
    influence_edges = INFLUENCE_EDGES,
    influence_help = INFLUENCE_HELP,
    stat_order = STAT_ORDER,
    stat_labels = STAT_LABELS,
    format_signed = format_signed,
    show_real_world_values = show_real_world_values,
    get_real_world_mapping = get_real_world_mapping,
    get_edges_from_stat = get_edges_from_stat,
    get_context_edge_delta = get_context_edge_delta,
    draw_wrapped_line = draw_wrapped_line,
    get_stat_status = get_stat_status
  })
end

local function draw_forecast_panel(rect, forecast_ctx)
  InfluenceExplain.draw_forecast_panel({
    rect = rect,
    forecast_ctx = forecast_ctx,
    mode_buttons = get_forecast_mode_buttons(rect),
    influence_ui = influence_ui,
    terraforming_state = terraforming_state,
    influence_edges = INFLUENCE_EDGES,
    stat_order = STAT_ORDER,
    stat_labels = STAT_LABELS,
    format_signed = format_signed,
    format_delta_list = format_delta_list,
    draw_wrapped_line = draw_wrapped_line,
    get_forecast_mode_label = get_forecast_mode_label
  })
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

  local turn_fill = influence_ui.show_turn_explain and { 0.24, 0.42, 0.26, 1 } or { 0.13, 0.18, 0.25, 1 }
  if influence_ui.hovered_turn_explain_button and not influence_ui.show_turn_explain then
    turn_fill = { 0.18, 0.24, 0.33, 1 }
  end
  local turn_border = influence_ui.show_turn_explain and { 0.65, 0.95, 0.64, 1 } or { 0.62, 0.78, 0.95, 1 }
  love.graphics.setColor(unpack(turn_fill))
  love.graphics.rectangle("fill", explain_button.x, explain_button.y, explain_button.w, explain_button.h, 7, 7)
  love.graphics.setColor(unpack(turn_border))
  love.graphics.rectangle("line", explain_button.x, explain_button.y, explain_button.w, explain_button.h, 7, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(influence_ui.show_turn_explain and "Hide Turn" or "Explain Next Turn", explain_button.x + 4, explain_button.y + 6, explain_button.w - 8, "center")

  for i, card_rect in ipairs(card_rects) do
    local option = card_rect.option
    local is_do_nothing = option.kind == "do_nothing"
    local card = option.card
    local selected = false
    local affordable = true
    if is_do_nothing then
      selected = influence_ui.forecast_mode == "do_nothing"
    else
      selected = influence_ui.forecast_mode == "selected" and influence_ui.selected_forecast_card_index == option.card_index
      affordable = can_afford(card.cost or 0)
    end
    local hovered = (influence_ui.hovered_forecast_option_index == i)

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
  local safe = get_safe_rect()
  local heading_x = safe.x
  local heading_y = safe.y - 8
  local layout = get_influence_layout()
  local forecast_ctx = get_forecast_context()

  Background.draw_fill()
  Background.draw_stars()

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("Core Influence Map (V)", heading_x, heading_y)
  love.graphics.print("Click primitive to focus. Arrows show coupling for the selected reference mode; blue marker shows card push.", heading_x, heading_y + 20)
  love.graphics.print("Use Explain Graph, Explain Next Turn, and Explain Objectives for detailed breakdowns.", heading_x, heading_y + 40)
  love.graphics.print("M mapping, C clear card, I flow, Z current, X do nothing, P selected card, V gameplay.", heading_x, heading_y + 60)

  draw_influence_nodes(layout, forecast_ctx)
  draw_end_objectives_panel(layout, forecast_ctx)
  if influence_ui.show_graph_explain then
    draw_influence_details(layout.graph_explain_rect, forecast_ctx)
  end
  if influence_ui.show_turn_explain then
    draw_forecast_panel(layout.turn_explain_rect, forecast_ctx)
  end
  draw_influence_cards(layout)

  if campaign_state ~= "playing" then
    draw_status_overlay()
  end
end

function Runtime.update(dt)
  local active_scene = Runtime.get_active_scene()
  if active_scene == "card_library" then
    Runtime.update_card_library(dt)
  elseif active_scene == "influence" then
    Runtime.update_influence(dt)
  else
    Runtime.update_gameplay(dt)
  end
end

function Runtime.draw()
  local active_scene = Runtime.get_active_scene()
  if active_scene == "card_library" then
    Runtime.draw_card_library()
  elseif active_scene == "influence" then
    Runtime.draw_influence()
  else
    Runtime.draw_gameplay()
  end
end

function Runtime.keypressed(key)
  local active_scene = Runtime.get_active_scene()
  if active_scene == "card_library" then
    Runtime.keypressed_card_library(key)
  elseif active_scene == "influence" then
    Runtime.keypressed_influence(key)
  else
    Runtime.keypressed_gameplay(key)
  end
end

function Runtime.mousepressed(x, y, button)
  local active_scene = Runtime.get_active_scene()
  if active_scene == "card_library" then
    Runtime.mousepressed_card_library(x, y, button)
  elseif active_scene == "influence" then
    Runtime.mousepressed_influence(x, y, button)
  else
    Runtime.mousepressed_gameplay(x, y, button)
  end
end

function Runtime.wheelmoved(_, y)
  local active_scene = Runtime.get_active_scene()
  if active_scene == "card_library" then
    Runtime.wheelmoved_card_library(0, y)
  elseif active_scene == "influence" then
    Runtime.wheelmoved_influence(0, y)
  else
    Runtime.wheelmoved_gameplay(0, y)
  end
end

local function map_pointer_to_ui(x, y)
  local has_pointer = true
  local mapped_x = x
  local mapped_y = y
  if viewport then
    if viewport:is_inside(x, y) then
      mapped_x, mapped_y = viewport:to_ui(x, y)
    else
      has_pointer = false
    end
  end
  return has_pointer, mapped_x, mapped_y
end

function Runtime.update_gameplay(dt)
  if viewport then
    viewport:update(love.graphics.getDimensions())
  end

  target:update(dt)
  influence_ui:sanitize_selection(#player_deck.hand)

  hovered_card_index = nil
  hovered_draw_pile = false
  hovered_discard_pile = false
  hovered_end_turn = false
  influence_ui:reset_hover_state()

  if campaign_state ~= "playing" then
    return
  end

  local raw_mx, raw_my = love.mouse.getPosition()
  local has_pointer, mx, my = map_pointer_to_ui(raw_mx, raw_my)
  if not has_pointer then
    return
  end

  hovered_card_index = get_card_index_at_position(mx, my)
  local draw_rect = get_draw_pile_rect()
  hovered_draw_pile = point_in_rect(mx, my, draw_rect.x, draw_rect.y, draw_rect.w, draw_rect.h)
  local discard_rect = get_discard_pile_rect()
  hovered_discard_pile = point_in_rect(mx, my, discard_rect.x, discard_rect.y, discard_rect.w, discard_rect.h)
  local end_turn_rect = get_end_turn_rect()
  hovered_end_turn = point_in_rect(mx, my, end_turn_rect.x, end_turn_rect.y, end_turn_rect.w, end_turn_rect.h)
end

function Runtime.update_influence(_dt)
  if viewport then
    viewport:update(love.graphics.getDimensions())
  end

  target:update(0)
  influence_ui:sanitize_selection(#player_deck.hand)
  hovered_card_index = nil
  hovered_draw_pile = false
  hovered_discard_pile = false
  hovered_end_turn = false
  influence_ui:reset_hover_state()

  if campaign_state ~= "playing" then
    return
  end

  local raw_mx, raw_my = love.mouse.getPosition()
  local has_pointer, mx, my = map_pointer_to_ui(raw_mx, raw_my)
  if not has_pointer then
    return
  end

  local layout = get_influence_layout()
  local toggle_buttons = get_map_toggle_buttons(layout)
  influence_ui.hovered_edge_filter_button = point_in_rect(mx, my, toggle_buttons.filter.x, toggle_buttons.filter.y, toggle_buttons.filter.w, toggle_buttons.filter.h)
  influence_ui.hovered_graph_explain_button = point_in_rect(mx, my, toggle_buttons.explain_graph.x, toggle_buttons.explain_graph.y, toggle_buttons.explain_graph.w, toggle_buttons.explain_graph.h)

  local explain_button = get_preview_explain_button(layout)
  influence_ui.hovered_turn_explain_button = point_in_rect(mx, my, explain_button.x, explain_button.y, explain_button.w, explain_button.h)

  local objectives_explain_button = get_objectives_explain_button(layout)
  influence_ui.hovered_objectives_explain_button = point_in_rect(
    mx,
    my,
    objectives_explain_button.x,
    objectives_explain_button.y,
    objectives_explain_button.w,
    objectives_explain_button.h
  )

  if influence_ui.show_turn_explain then
    local forecast_buttons = get_forecast_mode_buttons(layout.turn_explain_rect)
    for _, button in ipairs(forecast_buttons) do
      if point_in_rect(mx, my, button.x, button.y, button.w, button.h) then
        influence_ui.hovered_forecast_mode = button.id
        break
      end
    end
  end

  for _, key in ipairs(STAT_ORDER) do
    local node = layout.nodes[key]
    if point_in_circle(mx, my, node.x, node.y, node.r) then
      influence_ui.hovered_influence_stat = key
      break
    end
  end

  local card_rects = get_influence_card_rects(layout)
  for i, rect in ipairs(card_rects) do
    if point_in_rect(mx, my, rect.x, rect.y, rect.w, rect.h) then
      influence_ui.hovered_forecast_option_index = i
      break
    end
  end
end

function Runtime.update_card_library(_dt)
  if viewport then
    viewport:update(love.graphics.getDimensions())
  end
  update_card_library_hover_state()
end

function Runtime.draw_gameplay()
  if viewport then
    viewport:begin_draw()
  end

  update_target_layout()
  Background.draw_fill()
  Background.draw_stars()
  target:draw()
  draw_next_hazard_card()
  draw_hud()
  draw_pile_widgets()
  draw_end_turn_button()
  draw_hand()
  draw_controls_hint()

  if campaign_state ~= "playing" then
    draw_status_overlay()
  end

  if viewport then
    viewport:end_draw()
  end
end

function Runtime.draw_influence()
  if viewport then
    viewport:begin_draw()
  end
  draw_influence_screen()
  if viewport then
    viewport:end_draw()
  end
end

function Runtime.draw_card_library()
  draw_card_library_screen()
end

function Runtime.keypressed_gameplay(key)
  if key == "r" then
    start_campaign()
    return
  end

  if key == "v" then
    view_mode = "influence"
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

  local num = tonumber(key)
  if not num or num < 1 or num > #player_deck.hand then
    return
  end
  try_play_card(num)
end

function Runtime.keypressed_influence(key)
  if key == "r" then
    start_campaign()
    return
  end

  if key == "v" then
    view_mode = "gameplay"
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

  if key == "i" then
    influence_ui:cycle_edge_filter_mode()
    return
  end

  if key == "z" then
    influence_ui:set_current_mode()
    return
  end

  if key == "x" then
    influence_ui:set_do_nothing_mode(false)
    return
  end

  if key == "p" then
    influence_ui:set_selected_or_do_nothing_mode()
    return
  end

  if key == "c" then
    influence_ui:set_current_mode()
    return
  end

  local num = tonumber(key)
  if num and num >= 1 and num <= #player_deck.hand then
    influence_ui:set_selected_mode(num)
  end
end

function Runtime.keypressed_card_library(key)
  handle_card_library_keypressed(key)
end

function Runtime.mousepressed_gameplay(x, y, button)
  if button ~= 1 then
    return
  end

  local has_pointer, mapped_x, mapped_y = map_pointer_to_ui(x, y)
  if not has_pointer then
    return
  end

  if campaign_state ~= "playing" then
    return
  end

  local end_turn_rect = get_end_turn_rect()
  if point_in_rect(mapped_x, mapped_y, end_turn_rect.x, end_turn_rect.y, end_turn_rect.w, end_turn_rect.h) then
    end_turn()
    return
  end

  local card_index = get_card_index_at_position(mapped_x, mapped_y)
  if card_index then
    try_play_card(card_index)
  end
end

function Runtime.mousepressed_influence(x, y, button)
  if button ~= 1 then
    return
  end

  local has_pointer, mapped_x, mapped_y = map_pointer_to_ui(x, y)
  if not has_pointer then
    return
  end

  if campaign_state ~= "playing" then
    return
  end

  local layout = get_influence_layout()
  local toggle_buttons = get_map_toggle_buttons(layout)
  if point_in_rect(mapped_x, mapped_y, toggle_buttons.filter.x, toggle_buttons.filter.y, toggle_buttons.filter.w, toggle_buttons.filter.h) then
    influence_ui:cycle_edge_filter_mode()
    return
  end

  if point_in_rect(mapped_x, mapped_y, toggle_buttons.explain_graph.x, toggle_buttons.explain_graph.y, toggle_buttons.explain_graph.w, toggle_buttons.explain_graph.h) then
    influence_ui:toggle_graph_explain()
    return
  end

  local explain_button = get_preview_explain_button(layout)
  if point_in_rect(mapped_x, mapped_y, explain_button.x, explain_button.y, explain_button.w, explain_button.h) then
    influence_ui:toggle_turn_explain()
    return
  end

  local objectives_explain_button = get_objectives_explain_button(layout)
  if point_in_rect(
    mapped_x,
    mapped_y,
    objectives_explain_button.x,
    objectives_explain_button.y,
    objectives_explain_button.w,
    objectives_explain_button.h
  ) then
    influence_ui:toggle_objectives_explain()
    return
  end

  if influence_ui.show_turn_explain then
    local forecast_buttons = get_forecast_mode_buttons(layout.turn_explain_rect)
    for _, forecast_button in ipairs(forecast_buttons) do
      if point_in_rect(mapped_x, mapped_y, forecast_button.x, forecast_button.y, forecast_button.w, forecast_button.h) then
        influence_ui:set_current_mode()
        return
      end
    end
  end

  for _, key in ipairs(STAT_ORDER) do
    local node = layout.nodes[key]
    if point_in_circle(mapped_x, mapped_y, node.x, node.y, node.r) then
      influence_ui.focused_stat = key
      return
    end
  end

  local card_rects = get_influence_card_rects(layout)
  for _, card_rect in ipairs(card_rects) do
    if point_in_rect(mapped_x, mapped_y, card_rect.x, card_rect.y, card_rect.w, card_rect.h) then
      local option = card_rect.option
      if option.kind == "do_nothing" then
        influence_ui:set_do_nothing_mode(true)
      else
        influence_ui:set_selected_mode(option.card_index)
      end
      return
    end
  end
end

function Runtime.mousepressed_card_library(x, y, button)
  if button ~= 1 then
    return
  end
  handle_card_library_mousepressed(x, y)
end

function Runtime.wheelmoved_gameplay(_, _)
end

function Runtime.wheelmoved_influence(_, _)
end

function Runtime.wheelmoved_card_library(_, y)
  handle_card_library_wheel(y)
end

function Runtime.get_active_scene()
  if launch_mode == "cards" then
    return "card_library"
  end

  if view_mode == "influence" then
    return "influence"
  end

  return "gameplay"
end

function Runtime.set_active_scene(scene_name)
  if scene_name == "card_library" then
    launch_mode = "cards"
    return
  end

  launch_mode = "game"
  if scene_name == "influence" then
    view_mode = "influence"
  else
    view_mode = "gameplay"
  end
end

function Runtime.get_viewport()
  return viewport
end

return Runtime
