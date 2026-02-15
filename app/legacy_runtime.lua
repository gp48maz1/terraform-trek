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

local card_library_state = {
  cards = {},
  topics = { "All" },
  selected_topic = "All",
  selected_card_id = nil,
  hovered_topic = nil,
  hovered_card_id = nil,
  scroll_offset = 0,
  max_scroll = 0
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

local function get_hazard_origin_color(origin)
  local colors = {
    space = { 0.95, 0.62, 0.28, 1 },
    atmospheric = { 0.55, 0.76, 0.97, 1 },
    climate = { 0.75, 0.84, 0.95, 1 },
    geologic = { 0.9, 0.57, 0.4, 1 },
    biological = { 0.56, 0.86, 0.53, 1 },
    chemical = { 0.94, 0.72, 0.36, 1 },
    planetary = { 0.82, 0.84, 0.9, 1 }
  }
  return colors[origin] or { 0.82, 0.84, 0.9, 1 }
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
  local hazard = projection.hazard or {}
  local rect = get_hazard_card_rect()
  local accent = get_hazard_origin_color(hazard.origin)
  local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 3.1)
  local body_color = { 0.07, 0.09, 0.13, 0.95 }
  local border_color = { accent[1], accent[2], accent[3], 1 }
  local header_h = 24
  local text_x = rect.x + 8
  local text_w = rect.w - 16

  love.graphics.setColor(unpack(body_color))
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 8, 8)
  love.graphics.setColor(border_color[1], border_color[2], border_color[3], 0.88 + pulse * 0.12)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 8, 8)
  love.graphics.setLineWidth(1)

  love.graphics.setColor(accent[1], accent[2], accent[3], 0.86)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, header_h, 8, 8)
  love.graphics.setColor(0.03, 0.05, 0.08, 1)
  love.graphics.printf("INCOMING", rect.x + 4, rect.y + 6, rect.w - 8, "center")

  local line_y = rect.y + header_h + 6
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(hazard.name or "Hazard", text_x, line_y, text_w, "center")
  line_y = line_y + 30

  love.graphics.setColor(0.76, 0.87, 0.95, 1)
  love.graphics.printf((hazard.category or "Event") .. " | " .. get_hazard_origin_label(hazard.origin), text_x, line_y, text_w, "center")
  line_y = line_y + 28

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Raw: " .. format_delta_list(projection.raw_deltas), text_x, line_y, text_w, "left")
  line_y = line_y + 30

  if hazard.magnetosphere_blockable then
    local level = terraforming_state:get_magnetosphere_level()
    local tier = terraforming_state:get_magnetosphere_tier(level)
    love.graphics.setColor(0.68, 0.87, 1, 1)
    love.graphics.printf("Mag L" .. tostring(level) .. " (" .. tier .. ")", text_x, line_y, text_w, "left")
    line_y = line_y + 18
    love.graphics.setColor(0.86, 0.93, 1, 1)
    love.graphics.printf("After block: " .. format_delta_list(projection.effective_deltas), text_x, line_y, text_w, "left")
  else
    love.graphics.setColor(0.9, 0.78, 0.42, 1)
    love.graphics.printf("Bypasses magnetosphere", text_x, line_y, text_w, "left")
  end

  local start_x = rect.x + rect.w + 8
  local start_y = rect.y + math.floor(rect.h * 0.5)
  local end_x = target.x - target.radius - 10
  local end_y = target.y
  local dx = end_x - start_x
  local dy = end_y - start_y
  local length = math.sqrt(dx * dx + dy * dy)
  if length > 0 then
    local ux = dx / length
    local uy = dy / length
    local arrow_len = 9
    local base_x = end_x - ux * 8
    local base_y = end_y - uy * 8
    local perp_x = -uy
    local perp_y = ux
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.45 + pulse * 0.45)
    love.graphics.setLineWidth(2)
    love.graphics.line(start_x, start_y, end_x, end_y)
    love.graphics.polygon(
      "fill",
      end_x,
      end_y,
      base_x + perp_x * (arrow_len * 0.45),
      base_y + perp_y * (arrow_len * 0.45),
      base_x - perp_x * (arrow_len * 0.45),
      base_y - perp_y * (arrow_len * 0.45)
    )
    love.graphics.setLineWidth(1)
  end
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

local function draw_stats(start_y, start_x)
  local base_x = start_x or 10
  local base_y = start_y or 110
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

local function draw_energy_orb()
  local draw_rect = get_draw_pile_rect()
  local cx = draw_rect.x + math.floor(draw_rect.w * 0.5)
  local cy = draw_rect.y - 26
  local radius = 20
  local ratio = 0
  if max_energy > 0 then
    ratio = clamp_value(current_energy / max_energy, 0, 1)
  end
  local start_angle = -math.pi * 0.5
  local end_angle = start_angle + (math.pi * 2 * ratio)

  love.graphics.setColor(0.09, 0.1, 0.14, 0.96)
  love.graphics.circle("fill", cx, cy, radius + 5)
  love.graphics.setColor(0.88, 0.28, 0.28, 0.9)
  love.graphics.setLineWidth(6)
  love.graphics.arc("line", "open", cx, cy, radius + 1, 0, math.pi * 2)
  love.graphics.setColor(0.95, 0.82, 0.35, 1)
  if ratio > 0 then
    love.graphics.arc("line", "open", cx, cy, radius + 1, start_angle, end_angle)
  end
  love.graphics.setLineWidth(1)

  love.graphics.setColor(0.18, 0.14, 0.08, 1)
  love.graphics.circle("fill", cx, cy, radius - 5)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(tostring(current_energy) .. "/" .. tostring(max_energy), cx - radius, cy - 6, radius * 2, "center")
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
  local safe = get_safe_rect()
  local hud_x = safe.x + 4
  local header_y = safe.y
  local config = WORLD_CONFIGS[world_index]
  local hazard_projection = terraforming_state:preview_next_hazard()
  local hazard = hazard_projection.hazard or terraforming_state:get_next_hazard()
  local economy = terraforming_state:get_economy_snapshot()
  local magnetosphere_level = terraforming_state:get_magnetosphere_level()
  local magnetosphere_tier = terraforming_state:get_magnetosphere_tier(magnetosphere_level)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("World " .. world_index .. "/" .. #WORLD_CONFIGS .. ": " .. config.name .. " (" .. config.tier .. ")", hud_x, header_y)
  love.graphics.print(
    "Turn: " .. terraforming_state.turn .. "/" .. terraforming_state.turn_limit ..
      "    Habitability: " .. terraforming_state.habitability .. "/" .. terraforming_state.goal,
    hud_x,
    header_y + 20
  )
  if hazard.magnetosphere_blockable then
    love.graphics.setColor(0.7, 0.9, 1, 1)
    love.graphics.print(
      "Magnetosphere L" .. tostring(magnetosphere_level) .. " (" .. magnetosphere_tier .. ") blocks " ..
        tostring(magnetosphere_level) .. "/stat -> " .. format_delta_list(hazard_projection.effective_deltas),
      hud_x,
      header_y + 40
    )
  else
    love.graphics.setColor(0.9, 0.8, 0.42, 1)
    love.graphics.print(
      "Magnetosphere L" .. tostring(magnetosphere_level) .. " (" .. magnetosphere_tier ..
        ") has no effect on this " .. string.lower(get_hazard_origin_label(hazard.origin)) .. " hazard.",
      hud_x,
      header_y + 40
    )
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("Population: " .. tostring(economy.population) .. "    Profit: " .. tostring(economy.profit), hud_x, header_y + 60)

  local stats_start_y = header_y + 80
  draw_stats(stats_start_y, hud_x)
  local line_height = show_real_world_values and 36 or 22
  local stats_bottom_y = stats_start_y + (#STAT_ORDER * line_height)
  local industry_y = stats_bottom_y + 12

  local slot_parts = {}
  for i = 1, terraforming_state:get_industry_slot_count() do
    local industry = economy.industries[i]
    if industry then
      table.insert(slot_parts, tostring(i) .. ":" .. industry.name .. " " .. tostring(industry.health) .. "/" .. tostring(industry.max_health))
    else
      table.insert(slot_parts, tostring(i) .. ":Open")
    end
  end
  love.graphics.print("Industry Slots: " .. table.concat(slot_parts, " | "), hud_x, industry_y)

  if turn_summary then
    local summary_y = industry_y + 38
    love.graphics.print(
      "Last Turn Hazard: " .. turn_summary.hazard .. " [" .. tostring(turn_summary.hazard_category or "Hazard") .. "]",
      hud_x,
      summary_y
    )
    love.graphics.print(
      "Hazard Raw: " .. format_delta_list(turn_summary.hazard_raw_deltas or turn_summary.hazard_deltas),
      hud_x,
      summary_y + 20
    )
    if turn_summary.hazard_blockable then
      love.graphics.print(
        "Magnetosphere Block: " .. format_delta_list(turn_summary.hazard_blocked_deltas) ..
          " -> Applied " .. format_delta_list(turn_summary.hazard_deltas),
        hud_x,
        summary_y + 40
      )
      summary_y = summary_y + 20
    else
      love.graphics.print("Applied Hazard Delta: " .. format_delta_list(turn_summary.hazard_deltas), hud_x, summary_y + 40)
    end
    love.graphics.print("Coupling Delta: " .. format_delta_list(turn_summary.coupling_deltas), hud_x, summary_y + 60)
    love.graphics.print(
      "Growth " .. turn_summary.growth .. " - Penalty " .. turn_summary.penalty .. " = Net " .. format_signed(turn_summary.net),
      hud_x,
      summary_y + 80
    )
    love.graphics.print(
      "Population " .. format_signed(turn_summary.population_delta or 0) ..
        " -> " .. tostring(turn_summary.projected_population or terraforming_state.population) ..
        " | Profit " .. format_signed(turn_summary.profit_delta or 0) ..
        " -> " .. tostring(turn_summary.projected_profit or terraforming_state.profit),
      hud_x,
      summary_y + 100
    )
  end

end

local function draw_controls_hint()
  local safe = get_safe_rect()
  local hand_layout = get_hand_layout(#player_deck.hand)
  local y = hand_layout.base_y - 48
  y = clamp_value(y, safe.y + 12, safe.y + safe.h - 30)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print(
    "Controls: Click card | E end turn | V influence map | M real-world mapping | R restart",
    safe.x + 4,
    y
  )
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

local CARD_LIBRARY_TOPIC_ORDER = {
  "Terraform",
  "Industry",
  "Chance",
  "Power",
  "Heat",
  "Air",
  "Water",
  "Soil",
  "Economy",
  "Draw",
  "Stabilize",
  "Stat Change"
}

local CATEGORY_SORT_ORDER = {
  Terraform = 1,
  Industry = 2,
  Chance = 3,
  Power = 4
}

local function get_card_library_topics_for_card(card_data)
  local topics = {}
  local function add(topic)
    if topic and topic ~= "" then
      topics[topic] = true
    end
  end

  add(card_data.category)
  local properties = card_data.properties or {}
  local changes = properties.stat_changes
  if changes then
    add("Stat Change")
    for stat_key, _ in pairs(changes) do
      add(STAT_LABELS[stat_key] or stat_key)
    end
  end

  if card_data.effect_fn_name == "install_industry" then
    add("Economy")
    add("Industry")
  elseif card_data.effect_fn_name == "draw_cards" then
    add("Draw")
  elseif card_data.effect_fn_name == "stabilize_system" then
    add("Stabilize")
  end

  return topics
end

initialize_card_library_state = function()
  local card_ids = CardTypes.getAllCardIds()
  table.sort(card_ids)

  local entries = {}
  local topic_presence = {}
  for _, card_id in ipairs(card_ids) do
    local card_data = CardTypes.createCardData(card_id)
    local topics = get_card_library_topics_for_card(card_data)
    for topic, _ in pairs(topics) do
      topic_presence[topic] = true
    end
    table.insert(entries, {
      id = card_id,
      data = card_data,
      card = Card:new(card_data),
      topics = topics
    })
  end

  table.sort(entries, function(a, b)
    local ca = CATEGORY_SORT_ORDER[a.data.category] or 99
    local cb = CATEGORY_SORT_ORDER[b.data.category] or 99
    if ca == cb then
      return string.lower(a.data.name) < string.lower(b.data.name)
    end
    return ca < cb
  end)

  local topics = { "All" }
  for _, topic in ipairs(CARD_LIBRARY_TOPIC_ORDER) do
    if topic_presence[topic] then
      table.insert(topics, topic)
      topic_presence[topic] = nil
    end
  end

  local extra_topics = {}
  for topic, _ in pairs(topic_presence) do
    table.insert(extra_topics, topic)
  end
  table.sort(extra_topics)
  for _, topic in ipairs(extra_topics) do
    table.insert(topics, topic)
  end

  card_library_state.cards = entries
  card_library_state.topics = topics
  card_library_state.selected_topic = "All"
  card_library_state.selected_card_id = entries[1] and entries[1].id or nil
  card_library_state.hovered_topic = nil
  card_library_state.hovered_card_id = nil
  card_library_state.scroll_offset = 0
  card_library_state.max_scroll = 0
end

local function get_card_library_filtered_entries()
  local filtered = {}
  local selected_topic = card_library_state.selected_topic
  for _, entry in ipairs(card_library_state.cards) do
    if selected_topic == "All" or entry.topics[selected_topic] then
      table.insert(filtered, entry)
    end
  end
  return filtered
end

local function ensure_card_library_selection(filtered)
  if #filtered == 0 then
    card_library_state.selected_card_id = nil
    return
  end

  local selected_id = card_library_state.selected_card_id
  for _, entry in ipairs(filtered) do
    if entry.id == selected_id then
      return
    end
  end
  card_library_state.selected_card_id = filtered[1].id
end

local function get_card_library_layout()
  local sw, sh = love.graphics.getDimensions()
  local margin = 20
  local filter_y = 88
  local filter_h = 28
  local filter_gap = 8
  local x = margin
  local y = filter_y
  local font = love.graphics.getFont()
  local filter_rects = {}

  for _, topic in ipairs(card_library_state.topics) do
    local w = math.max(84, font:getWidth(topic) + 22)
    if x + w > sw - margin then
      x = margin
      y = y + filter_h + filter_gap
    end
    table.insert(filter_rects, {
      topic = topic,
      x = x,
      y = y,
      w = w,
      h = filter_h
    })
    x = x + w + filter_gap
  end

  local filters_bottom = y + filter_h
  local content_top = filters_bottom + 12
  local detail_w = math.max(300, math.floor(sw * 0.29))
  local content_h = math.max(220, sh - content_top - 20)
  local grid_w = sw - (margin * 2) - detail_w - 12
  if grid_w < 380 then
    detail_w = math.max(260, math.floor(sw * 0.34))
    grid_w = sw - (margin * 2) - detail_w - 12
  end
  local grid_rect = {
    x = margin,
    y = content_top,
    w = grid_w,
    h = content_h
  }
  local detail_rect = {
    x = grid_rect.x + grid_rect.w + 12,
    y = content_top,
    w = detail_w,
    h = content_h
  }

  return {
    filter_rects = filter_rects,
    grid_rect = grid_rect,
    detail_rect = detail_rect
  }
end

local function get_card_library_card_rects(layout, filtered_entries)
  local grid_rect = layout.grid_rect
  local inner_pad = 10
  local card_w = 150
  local card_h = 225
  local gap_x = 14
  local gap_y = 16
  local usable_w = math.max(1, grid_rect.w - (inner_pad * 2))
  local cols = math.max(1, math.floor((usable_w + gap_x) / (card_w + gap_x)))
  local used_w = cols * card_w + (cols - 1) * gap_x
  local start_x = grid_rect.x + inner_pad + math.max(0, math.floor((usable_w - used_w) / 2))
  local start_y = grid_rect.y + inner_pad - card_library_state.scroll_offset

  local rects = {}
  for i, entry in ipairs(filtered_entries) do
    local row = math.floor((i - 1) / cols)
    local col = (i - 1) % cols
    local x = start_x + col * (card_w + gap_x)
    local y = start_y + row * (card_h + gap_y)
    table.insert(rects, {
      x = x,
      y = y,
      w = card_w,
      h = card_h,
      entry = entry
    })
  end

  local rows = math.ceil(#filtered_entries / cols)
  local total_h = 0
  if rows > 0 then
    total_h = rows * card_h + (rows - 1) * gap_y
  end
  local max_scroll = math.max(0, total_h - (grid_rect.h - inner_pad * 2))
  return rects, max_scroll
end

local function get_card_library_selected_entry(filtered_entries)
  for _, entry in ipairs(filtered_entries) do
    if entry.id == card_library_state.selected_card_id then
      return entry
    end
  end
  return filtered_entries[1]
end

local function update_card_library_hover_state()
  local mx, my = love.mouse.getPosition()
  local layout = get_card_library_layout()
  local filtered_entries = get_card_library_filtered_entries()
  ensure_card_library_selection(filtered_entries)
  local card_rects, max_scroll = get_card_library_card_rects(layout, filtered_entries)
  card_library_state.max_scroll = max_scroll
  card_library_state.scroll_offset = clamp_value(card_library_state.scroll_offset, 0, max_scroll)

  card_library_state.hovered_topic = nil
  card_library_state.hovered_card_id = nil

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
  card_library_state.max_scroll = max_scroll
  card_library_state.scroll_offset = clamp_value(card_library_state.scroll_offset, 0, max_scroll)
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
  card_library_state.max_scroll = max_scroll
  card_library_state.scroll_offset = clamp_value(card_library_state.scroll_offset, 0, max_scroll)

  for _, filter_rect in ipairs(layout.filter_rects) do
    if point_in_rect(x, y, filter_rect.x, filter_rect.y, filter_rect.w, filter_rect.h) then
      card_library_state.selected_topic = filter_rect.topic
      card_library_state.scroll_offset = 0
      local refreshed = get_card_library_filtered_entries()
      ensure_card_library_selection(refreshed)
      return
    end
  end

  local grid_rect = layout.grid_rect
  for _, rect in ipairs(card_rects) do
    local visible = rect.y + rect.h >= grid_rect.y and rect.y <= grid_rect.y + grid_rect.h
    if visible and point_in_rect(x, y, rect.x, rect.y, rect.w, rect.h) then
      card_library_state.selected_card_id = rect.entry.id
      return
    end
  end
end

local function handle_card_library_wheel(y)
  local step = 44
  card_library_state.scroll_offset = clamp_value(
    card_library_state.scroll_offset - y * step,
    0,
    card_library_state.max_scroll
  )
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

  local topics = card_library_state.topics
  local current_index = 1
  for i, topic in ipairs(topics) do
    if topic == card_library_state.selected_topic then
      current_index = i
      break
    end
  end

  if key == "left" then
    current_index = current_index - 1
    if current_index < 1 then
      current_index = #topics
    end
    card_library_state.selected_topic = topics[current_index]
    card_library_state.scroll_offset = 0
    local filtered = get_card_library_filtered_entries()
    ensure_card_library_selection(filtered)
    return
  elseif key == "right" then
    current_index = current_index + 1
    if current_index > #topics then
      current_index = 1
    end
    card_library_state.selected_topic = topics[current_index]
    card_library_state.scroll_offset = 0
    local filtered = get_card_library_filtered_entries()
    ensure_card_library_selection(filtered)
    return
  end
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
  local magnetosphere_level = terraforming_state:get_magnetosphere_level()
  local magnetosphere_tier = terraforming_state:get_magnetosphere_tier(magnetosphere_level)
  local slot_count = terraforming_state:get_industry_slot_count()
  local active_industries = forecast_ctx.active_economy.industries or {}
  local current_breakdown = build_population_snapshot_breakdown(terraforming_state.stats or {})
  local active_breakdown = build_population_snapshot_breakdown(active_snapshot or {})
  local population_delta = active_summary and (active_summary.population_delta or active_breakdown.delta) or active_breakdown.delta
  local profit_delta = active_summary and (active_summary.profit_delta or 0) or 0
  local industry_report = active_summary and active_summary.industry_report or nil
  local profit_breakdown = build_profit_snapshot_breakdown(active_summary, slot_count)
  local profit_flow = calculate_profit_flow_totals(active_industries, profit_breakdown, active_population, slot_count)
  local projected_profit_gain = profit_breakdown and profit_delta or profit_flow.income_total

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
      "  |  Hab " .. tostring(terraforming_state.habitability) .. "/" .. tostring(terraforming_state.goal) ..
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
    love.graphics.printf("Now " .. format_signed(active_score) .. " " .. get_quality_label(active_quality), tile_x + 6, tile_y + 20, tile_w - 12, "center")
    local score_text = "From " .. format_signed(current_score)
    if active_score ~= current_score then
      score_text = score_text .. " -> " .. format_signed(active_score)
    end
    love.graphics.printf(score_text, tile_x + 6, tile_y + 35, tile_w - 12, "center")
  end

  local bars_y = tile_y + tile_h + 10
  draw_end_objective_metric_graph(rect, bars_y, "Population", current_population, active_population, { 0.35, 0.66, 0.42 })
  draw_end_objective_metric_graph(rect, bars_y + 48, "Profit", current_profit, active_profit, { 0.66, 0.56, 0.24 })

  local flow_title_y = bars_y + 90
  love.graphics.setColor(0.75, 0.87, 0.95, 1)
  love.graphics.printf("Profit Flow", rect.x + 14, flow_title_y, rect.w - 28, "left")

  local flow_gap = 8
  local flow_box_w = math.floor((rect.w - 28 - (flow_gap * 2)) / 3)
  local flow_box_h = 40
  local flow_y = flow_title_y + 16
  local flow_x = rect.x + 14

  local flow_labels = {
    {
      title = "Population Bonus",
      value = format_signed(profit_flow.pop_bonus_total)
    },
    {
      title = "Industry Base",
      value = format_signed(profit_flow.base_total)
    },
    {
      title = "Projected Profit Gain",
      value = format_signed(projected_profit_gain)
    }
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
        "Inc " .. format_signed(income_value) .. "/turn (B " ..
          format_signed(base_income) .. ", P " .. format_signed(pop_bonus_value) .. ")",
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

  if influence_ui.show_objectives_explain then
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

  local explain_fill = influence_ui.show_objectives_explain and { 0.24, 0.42, 0.26, 1 } or { 0.13, 0.18, 0.25, 1 }
  if influence_ui.hovered_objectives_explain_button and not influence_ui.show_objectives_explain then
    explain_fill = { 0.18, 0.24, 0.33, 1 }
  end
  local explain_border = influence_ui.show_objectives_explain and { 0.65, 0.95, 0.64, 1 } or { 0.62, 0.78, 0.95, 1 }
  love.graphics.setColor(unpack(explain_fill))
  love.graphics.rectangle("fill", explain_button.x, explain_button.y, explain_button.w, explain_button.h, 7, 7)
  love.graphics.setColor(unpack(explain_border))
  love.graphics.rectangle("line", explain_button.x, explain_button.y, explain_button.w, explain_button.h, 7, 7)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(influence_ui.show_objectives_explain and "Hide Objectives" or "Explain Objectives", explain_button.x + 4, explain_button.y + 6, explain_button.w - 8, "center")
end

local function draw_influence_details(rect, forecast_ctx)
  local snapshot = forecast_ctx.active_snapshot
  local value = snapshot[influence_ui.focused_stat]
  local help = INFLUENCE_HELP[influence_ui.focused_stat]
  local status, color = get_stat_status(influence_ui.focused_stat, value)
  local coupling_signal = terraforming_state:get_source_coupling_signal(influence_ui.focused_stat, snapshot)
  local coupling_rule_text = terraforming_state:get_coupling_rule_text(influence_ui.focused_stat)
  local incoming_edges = {}
  for _, edge in ipairs(INFLUENCE_EDGES) do
    if edge.target == influence_ui.focused_stat then
      table.insert(incoming_edges, edge)
    end
  end
  local outgoing_edges = get_edges_from_stat(influence_ui.focused_stat)
  local incoming_total = 0
  local incoming_active = 0
  for _, edge in ipairs(incoming_edges) do
    local delta = get_context_edge_delta(forecast_ctx, edge)
    incoming_total = incoming_total + delta
    if delta ~= 0 then
      incoming_active = incoming_active + 1
    end
  end
  local outgoing_total = 0
  local outgoing_active = 0
  for _, edge in ipairs(outgoing_edges) do
    local delta = get_context_edge_delta(forecast_ctx, edge)
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

  local text_x = rect.x + 14
  local text_w = rect.w - 28
  local line_y = rect.y + 14
  local bottom_y = rect.y + rect.h - 14

  line_y = draw_wrapped_line("Focused Primitive: " .. STAT_LABELS[influence_ui.focused_stat], text_x, line_y, text_w, { 1, 1, 1, 1 }, 16)
  line_y = draw_wrapped_line("Reference: " .. mode_label, text_x, line_y + 2, text_w, color, 16)
  line_y = draw_wrapped_line("Notch: " .. format_signed(value) .. " (" .. status .. ")", text_x, line_y + 2, text_w, color, 16)
  line_y = draw_wrapped_line(help.summary, text_x, line_y + 2, text_w, { 1, 1, 1, 1 }, 16)
  line_y = draw_wrapped_line("Incoming: " .. help.incoming, text_x, line_y + 2, text_w, { 1, 1, 1, 1 }, 16)

  local coupling_text = "Coupling signal: 0 (neutral) at this source state."
  local coupling_color = { 0.98, 0.82, 0.35, 1 }
  if coupling_signal > 0 then
    coupling_text = "Coupling signal: " .. format_signed(coupling_signal) .. " (supportive) from this source state."
    coupling_color = { 0.45, 0.95, 0.45, 1 }
  elseif coupling_signal < 0 then
    coupling_text = "Coupling signal: " .. format_signed(coupling_signal) .. " (stress) from this source state."
    coupling_color = { 0.98, 0.62, 0.42, 1 }
  end
  line_y = draw_wrapped_line(coupling_text, text_x, line_y + 2, text_w, coupling_color, 16)
  line_y = draw_wrapped_line(terraforming_state:get_coupling_rules_summary(), text_x, line_y + 2, text_w, { 1, 1, 1, 1 }, 16)
  line_y = draw_wrapped_line(coupling_rule_text, text_x, line_y + 2, text_w, { 1, 1, 1, 1 }, 16)
  line_y = draw_wrapped_line(
    "Incoming net " .. format_signed(incoming_total) .. " (" ..
      tostring(incoming_active) .. "/" .. tostring(#incoming_edges) .. " active) | Outgoing net " ..
      format_signed(outgoing_total) .. " (" .. tostring(outgoing_active) .. "/" ..
      tostring(#outgoing_edges) .. " active)",
    text_x,
    line_y + 2,
    text_w,
    { 1, 1, 1, 1 },
    16
  )

  if show_real_world_values and (line_y + 18) < bottom_y then
    draw_wrapped_line(get_real_world_mapping(influence_ui.focused_stat, value), text_x, line_y + 4, text_w, { 0.75, 0.87, 0.95, 1 }, 16)
  end
end

local function draw_forecast_panel(rect, forecast_ctx)
  local baseline = forecast_ctx.baseline
  local scenario = forecast_ctx.scenario
  local mode_buttons = get_forecast_mode_buttons(rect)
  local current_population = forecast_ctx.current_economy.population
  local current_profit = forecast_ctx.current_economy.profit

  love.graphics.setColor(0.06, 0.08, 0.12, 1)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 10, 10)

  local text_x = rect.x + 14
  local text_w = rect.w - 28
  local line_y = rect.y + 12

  line_y = draw_wrapped_line("End-Turn Forecast", text_x, line_y, text_w, { 1, 1, 1, 1 }, 16)
  line_y = draw_wrapped_line(
    "Hazard: " .. baseline.hazard .. " [" .. tostring(baseline.hazard_category or "Hazard") .. "]",
    text_x,
    line_y + 2,
    text_w,
    { 1, 1, 1, 1 },
    16
  )
  line_y = draw_wrapped_line(
    "Hazard raw: " .. format_delta_list(baseline.hazard_raw_deltas),
    text_x,
    line_y + 2,
    text_w,
    { 0.75, 0.87, 0.95, 1 },
    16
  )
  if baseline.hazard_blockable then
    line_y = draw_wrapped_line(
      "Magnetosphere block: " .. format_delta_list(baseline.hazard_blocked_deltas) ..
        " | Effective hazard: " .. format_delta_list(baseline.hazard_effective_deltas),
      text_x,
      line_y + 2,
      text_w,
      { 0.75, 0.87, 0.95, 1 },
      16
    )
  else
    line_y = draw_wrapped_line(
      "Hazard bypasses magnetosphere. Effective hazard: " .. format_delta_list(baseline.hazard_effective_deltas),
      text_x,
      line_y + 2,
      text_w,
      { 0.75, 0.87, 0.95, 1 },
      16
    )
  end
  line_y = draw_wrapped_line(
    "Map reference mode: " .. get_forecast_mode_label(forecast_ctx.active_mode),
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
    local current = terraforming_state.stats[key] or 0
    local start = start_stats[key] or current
    return start - current
  end

  local function format_edge_terms(summary)
    local terms = {}
    local edge_deltas = summary and summary.coupling_edge_deltas or {}
    for _, edge in ipairs(INFLUENCE_EDGES) do
      local key = edge.source .. "->" .. edge.target
      local delta = edge_deltas[key] or 0
      if delta ~= 0 then
        terms[#terms + 1] = edge.text .. " " .. format_signed(delta)
      end
    end
    if #terms == 0 then
      return "Coupling edges: none"
    end
    return "Coupling edges: " .. table.concat(terms, " | ")
  end

  local function draw_outcome_column(column_x, column_y, column_w, heading, summary, baseline_net, affordable_now)
    local y = draw_wrapped_line(heading, column_x, column_y, column_w, { 1, 1, 1, 1 }, 16)
    if not summary then
      draw_wrapped_line("Select a card below to preview a one-card outcome.", column_x, y + 2, column_w, { 1, 1, 1, 1 }, 16)
      return
    end

    if affordable_now == false then
      y = draw_wrapped_line("Card unaffordable now (preview only).", column_x, y + 2, column_w, { 0.98, 0.65, 0.35, 1 }, 16)
    end

    for _, key in ipairs(STAT_ORDER) do
      local current = terraforming_state.stats[key] or 0
      local card_delta = get_card_delta(summary, key)
      local hazard_delta = (summary.hazard_deltas and summary.hazard_deltas[key]) or 0
      local coupling_delta = (summary.coupling_target_deltas_applied and summary.coupling_target_deltas_applied[key]) or
        (summary.coupling_deltas and summary.coupling_deltas[key]) or 0
      local projected = (summary.projected_stats and summary.projected_stats[key]) or current
      local equation = STAT_LABELS[key] .. ": " .. format_signed(current) ..
        " + card " .. format_signed(card_delta) ..
        " + hazard " .. format_signed(hazard_delta) ..
        " + coupling " .. format_signed(coupling_delta) ..
        " = " .. format_signed(projected)
      y = draw_wrapped_line(equation, column_x, y + 1, column_w, { 1, 1, 1, 1 }, 15)
    end

    local net_line = "Net Habitability: " .. format_signed(summary.net)
    if baseline_net then
      net_line = net_line .. " (" .. format_signed(summary.net - baseline_net) .. " vs do-nothing)"
    end
    y = draw_wrapped_line(net_line, column_x, y + 2, column_w, { 1, 1, 1, 1 }, 15)
    y = draw_wrapped_line(
      "Population: " .. tostring(current_population) .. " + " .. format_signed(summary.population_delta or 0) ..
        " = " .. tostring(summary.projected_population or current_population),
      column_x,
      y + 1,
      column_w,
      { 1, 1, 1, 1 },
      15
    )
    y = draw_wrapped_line(
      "Profit: " .. tostring(current_profit) .. " + " .. format_signed(summary.profit_delta or 0) ..
        " = " .. tostring(summary.projected_profit or current_profit),
      column_x,
      y + 1,
      column_w,
      { 1, 1, 1, 1 },
      15
    )
    draw_wrapped_line(format_edge_terms(summary), column_x, y + 2, column_w, { 0.75, 0.87, 0.95, 1 }, 15)
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
  if viewport then
    viewport:update(love.graphics.getDimensions())
  end

  if launch_mode == "cards" then
    update_card_library_hover_state()
    return
  end

  target:update(dt)
  influence_ui:sanitize_selection(#player_deck.hand)

  hovered_card_index = nil
  hovered_draw_pile = false
  hovered_discard_pile = false
  hovered_end_turn = false
  influence_ui:reset_hover_state()

  local raw_mx, raw_my = love.mouse.getPosition()
  local has_pointer = true
  local mx, my = raw_mx, raw_my
  if viewport then
    if viewport:is_inside(raw_mx, raw_my) then
      mx, my = viewport:to_ui(raw_mx, raw_my)
    else
      has_pointer = false
    end
  end

  if has_pointer and view_mode == "gameplay" and campaign_state == "playing" then
    hovered_card_index = get_card_index_at_position(mx, my)

    local draw_rect = get_draw_pile_rect()
    hovered_draw_pile = point_in_rect(mx, my, draw_rect.x, draw_rect.y, draw_rect.w, draw_rect.h)

    local discard_rect = get_discard_pile_rect()
    hovered_discard_pile = point_in_rect(mx, my, discard_rect.x, discard_rect.y, discard_rect.w, discard_rect.h)

    local end_turn_rect = get_end_turn_rect()
    hovered_end_turn = point_in_rect(mx, my, end_turn_rect.x, end_turn_rect.y, end_turn_rect.w, end_turn_rect.h)
  end

  if has_pointer and view_mode == "influence" and campaign_state == "playing" then
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
end

function Runtime.draw()
  if launch_mode == "cards" then
    draw_card_library_screen()
    return
  end

  if viewport then
    viewport:begin_draw()
  end

  if view_mode == "gameplay" then
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
    return
  end

  draw_influence_screen()
  if viewport then
    viewport:end_draw()
  end
end

function Runtime.keypressed(key)
  if launch_mode == "cards" then
    handle_card_library_keypressed(key)
    return
  end

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
    return
  end

  local num = tonumber(key)
  if not num or num < 1 or num > #player_deck.hand then
    return
  end

  try_play_card(num)
end

function Runtime.mousepressed(x, y, button)
  if button ~= 1 then
    return
  end

  if launch_mode == "cards" then
    handle_card_library_mousepressed(x, y)
    return
  end

  if viewport then
    if not viewport:is_inside(x, y) then
      return
    end
    x, y = viewport:to_ui(x, y)
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
      influence_ui:cycle_edge_filter_mode()
      return
    end

    if point_in_rect(x, y, toggle_buttons.explain_graph.x, toggle_buttons.explain_graph.y, toggle_buttons.explain_graph.w, toggle_buttons.explain_graph.h) then
      influence_ui:toggle_graph_explain()
      return
    end

    local explain_button = get_preview_explain_button(layout)
    if point_in_rect(x, y, explain_button.x, explain_button.y, explain_button.w, explain_button.h) then
      influence_ui:toggle_turn_explain()
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
      influence_ui:toggle_objectives_explain()
      return
    end

    if influence_ui.show_turn_explain then
      local forecast_buttons = get_forecast_mode_buttons(layout.turn_explain_rect)
      for _, button in ipairs(forecast_buttons) do
        if point_in_rect(x, y, button.x, button.y, button.w, button.h) then
          influence_ui:set_current_mode()
          return
        end
      end
    end

    for _, key in ipairs(STAT_ORDER) do
      local node = layout.nodes[key]
      if point_in_circle(x, y, node.x, node.y, node.r) then
        influence_ui.focused_stat = key
        return
      end
    end

    local card_rects = get_influence_card_rects(layout)
    for i, rect in ipairs(card_rects) do
      if point_in_rect(x, y, rect.x, rect.y, rect.w, rect.h) then
        local option = rect.option
        if option.kind == "do_nothing" then
          influence_ui:set_do_nothing_mode(true)
        else
          influence_ui:set_selected_mode(option.card_index)
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

function Runtime.wheelmoved(_, y)
  if launch_mode ~= "cards" then
    return
  end
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
