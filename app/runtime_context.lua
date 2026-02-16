local Deck = require("deck")
local Card = require("card")
local CardTypes = require("card_types")
local TerraformingTarget = require("terraforming_target")
local TerraformingState = require("terraforming_state")
local Viewport = require("viewport")
local Background = require("background")

local Worlds = require("content.worlds")
local CouplingRules = require("content.coupling_rules")

local PreviewContextSystem = require("systems.preview_context_system")
local ActionApplier = require("systems.action_applier")

local InfluenceUIState = require("app.influence_ui_state")
local CardLibraryState = require("app.card_library_state")

local RuntimeContext = {}
RuntimeContext.__index = RuntimeContext

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

function RuntimeContext.new()
  local self = setmetatable({}, RuntimeContext)

  self.VIEWPORT_REF_W = 1728
  self.VIEWPORT_REF_H = 798
  self.VIEWPORT_SAFE_INSETS = {
    left = 96,
    right = 96,
    top = 20,
    bottom = 20
  }

  self.STAT_ORDER = { "heat", "air", "water", "soil" }
  self.STAT_LABELS = {
    heat = "Heat",
    air = "Air",
    water = "Water",
    soil = "Soil"
  }

  self.INFLUENCE_EDGES = CouplingRules.edges
  self.INFLUENCE_HELP = CouplingRules.help
  self.WORLD_CONFIGS = Worlds

  self.HAND_UI = {
    card_width = 150,
    card_height = 225,
    card_spacing = 175,
    max_angle_degrees = 10,
    pixel_offset_per_step = 20,
    base_y = 430
  }

  self.PILE_UI = {
    x_padding = 30,
    y = 340,
    width = 90,
    height = 120
  }

  self.END_TURN_UI = {
    width = 170,
    height = 50,
    x_padding = 30,
    y = 520
  }

  self.player_deck = nil
  self.target = nil
  self.terraforming_state = nil
  self.viewport = nil
  self.world_index = 1
  self.campaign_state = "playing" -- playing | world_won | campaign_won | campaign_lost
  self.turn_summary = nil
  self.view_mode = "gameplay" -- gameplay | influence
  self.show_real_world_values = false
  self.launch_mode = detect_launch_mode() -- game | cards

  self.influence_ui = InfluenceUIState.new()
  self.card_library_state = CardLibraryState.new()

  self.hovered_card_index = nil
  self.hovered_draw_pile = false
  self.hovered_discard_pile = false
  self.hovered_end_turn = false

  self.max_energy = 3
  self.current_energy = 0

  return self
end

function RuntimeContext:copy_stats(source)
  local out = {}
  for _, key in ipairs(self.STAT_ORDER) do
    out[key] = source[key]
  end
  return out
end

function RuntimeContext:safe_atan2(y, x)
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

function RuntimeContext:format_signed(value)
  if value > 0 then
    return "+" .. tostring(value)
  end
  return tostring(value)
end

function RuntimeContext:clamp_value(value, min_value, max_value)
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
end

function RuntimeContext:point_in_rect(px, py, rx, ry, rw, rh)
  return px >= rx and px <= rx + rw and py >= ry and py <= ry + rh
end

function RuntimeContext:point_in_circle(px, py, cx, cy, radius)
  local dx = px - cx
  local dy = py - cy
  return (dx * dx + dy * dy) <= radius * radius
end

function RuntimeContext:get_safe_rect()
  if self.viewport then
    return self.viewport:get_safe_rect()
  end
  return { x = 0, y = 0, w = self.VIEWPORT_REF_W, h = self.VIEWPORT_REF_H }
end

function RuntimeContext:update_viewport_from_graphics()
  if self.viewport then
    self.viewport:update(love.graphics.getDimensions())
  end
end

function RuntimeContext:get_stat_status(stat, value)
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

function RuntimeContext:get_real_world_mapping(stat, value)
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

function RuntimeContext:format_delta_list(deltas)
  local parts = {}
  for _, key in ipairs(self.STAT_ORDER) do
    local delta = (deltas and deltas[key]) or 0
    if delta ~= 0 then
      table.insert(parts, self.STAT_LABELS[key] .. " " .. self:format_signed(delta))
    end
  end

  if #parts == 0 then
    return "None"
  end

  return table.concat(parts, "  ")
end

function RuntimeContext:get_hazard_origin_label(origin)
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

function RuntimeContext:draw_wrapped_line(text, x, y, width, color, line_height)
  if color then
    love.graphics.setColor(unpack(color))
  else
    love.graphics.setColor(1, 1, 1, 1)
  end
  love.graphics.printf(text, x, y, width, "left")
  local font = love.graphics.getFont()
  local _, wrapped = font:getWrap(text, width)
  local font_h = font:getHeight()
  local effective_line_height = math.max(line_height or font_h, font_h + 2)
  return y + (math.max(1, #wrapped) * effective_line_height)
end

function RuntimeContext:initialize_card_library_state()
  CardLibraryState.initialize(self.card_library_state, {
    card_types = CardTypes,
    card_class = Card,
    stat_labels = self.STAT_LABELS
  })
end

function RuntimeContext:reset_energy()
  self.current_energy = self.max_energy
end

function RuntimeContext:can_afford(cost)
  return self.current_energy >= (cost or 0)
end

function RuntimeContext:spend_energy(cost)
  self.current_energy = self.current_energy - (cost or 0)
end

function RuntimeContext:setup_world(index)
  self.world_index = index
  local config = self.WORLD_CONFIGS[index]
  self.terraforming_state = TerraformingState.new(config)
  self.turn_summary = nil
  self.campaign_state = "playing"
  self.influence_ui:reset_for_new_campaign()

  self.player_deck:create_starter_deck()
  self.player_deck:draw(5)
  self:reset_energy()
end

function RuntimeContext:start_campaign()
  self:setup_world(1)
end

function RuntimeContext:end_turn()
  if self.campaign_state ~= "playing" then
    return
  end

  self.turn_summary = self.terraforming_state:end_turn()
  self.influence_ui:set_current_mode()

  if self.terraforming_state.status == "won" then
    if self.world_index == #self.WORLD_CONFIGS then
      self.campaign_state = "campaign_won"
    else
      self.campaign_state = "world_won"
    end
    return
  end

  if self.terraforming_state.status == "lost" then
    self.campaign_state = "campaign_lost"
    return
  end

  self.player_deck:discard_hand()
  self.player_deck:draw(5)
  self:reset_energy()
end

function RuntimeContext:get_forecast_context()
  return PreviewContextSystem.build(
    self.terraforming_state,
    self.player_deck.hand,
    self.influence_ui.selected_forecast_card_index,
    self.influence_ui.forecast_mode,
    function(cost)
      return self:can_afford(cost)
    end
  )
end

function RuntimeContext:get_edges_from_stat(stat_key)
  local edges = {}
  for _, edge in ipairs(self.INFLUENCE_EDGES) do
    if edge.source == stat_key then
      table.insert(edges, edge)
    end
  end
  return edges
end

function RuntimeContext:get_context_edge_delta(forecast_ctx, edge)
  local key = edge.source .. "->" .. edge.target
  local edge_deltas = forecast_ctx and forecast_ctx.active_edge_deltas or {}
  return edge_deltas[key] or 0
end

function RuntimeContext:compute_play_recommendations(limit)
  local recommendations = {}
  local baseline = self.terraforming_state:forecast_end_turn(self.terraforming_state.stats, {
    economy_state = self.terraforming_state:get_economy_snapshot()
  })
  local focused = self.influence_ui.focused_stat
  local current_distance = math.abs(self.terraforming_state.stats[focused] - self.terraforming_state.targets[focused])

  for i, card in ipairs(self.player_deck.hand) do
    if self:can_afford(card.cost or 0) then
      local snapshot = self:copy_stats(self.terraforming_state.stats)
      local economy = self.terraforming_state:get_economy_snapshot()
      ActionApplier.apply_card_preview(self.terraforming_state, card, snapshot, economy)
      local summary = self.terraforming_state:forecast_end_turn(snapshot, { economy_state = economy })
      local next_distance = math.abs(summary.projected_stats[focused] - self.terraforming_state.targets[focused])
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

function RuntimeContext:try_play_card(card_index)
  if self.campaign_state ~= "playing" then
    return false
  end

  local card_to_play = self.player_deck.hand[card_index]
  if not card_to_play then
    return false
  end

  local cost = card_to_play.cost or 0
  if not self:can_afford(cost) then
    return false
  end

  local context = {
    terraforming_state = self.terraforming_state,
    target = self.target
  }

  local played_card = self.player_deck:play_card(card_index, self.current_energy, context)
  if played_card then
    self:spend_energy(played_card.cost)
    self.influence_ui:set_current_mode()
    return true
  end

  return false
end

function RuntimeContext:enforce_window_mode()
  if not (love.window and love.window.getMode and love.window.setMode) then
    return
  end

  local width, height, flags = love.window.getMode()
  if width == self.VIEWPORT_REF_W and height == self.VIEWPORT_REF_H then
    return
  end

  local desired_flags = flags or {}
  desired_flags.resizable = false
  desired_flags.fullscreen = false
  desired_flags.vsync = true
  desired_flags.highdpi = true
  desired_flags.fullscreentype = desired_flags.fullscreentype or "desktop"
  love.window.setMode(self.VIEWPORT_REF_W, self.VIEWPORT_REF_H, desired_flags)
end

function RuntimeContext:load()
  love.math.setRandomSeed(os.time())
  self:enforce_window_mode()
  self.viewport = Viewport.new(self.VIEWPORT_REF_W, self.VIEWPORT_REF_H, self.VIEWPORT_SAFE_INSETS)
  self.viewport:update(love.graphics.getDimensions())
  Background.load()

  if self.launch_mode == "cards" then
    self:initialize_card_library_state()
    if love.window and love.window.setTitle then
      love.window.setTitle("Terraform Trek - Card Library")
    end
    return
  end

  self.player_deck = Deck:new()
  self.target = TerraformingTarget:new()
  self:start_campaign()
end

function RuntimeContext:resize(w, h)
  if self.viewport then
    self.viewport:update(w, h)
  end
end

function RuntimeContext:map_pointer_to_ui(x, y)
  local has_pointer = true
  local mapped_x = x
  local mapped_y = y
  if self.viewport then
    if self.viewport:is_inside(x, y) then
      mapped_x, mapped_y = self.viewport:to_ui(x, y)
    else
      has_pointer = false
    end
  end
  return has_pointer, mapped_x, mapped_y
end

function RuntimeContext:get_active_scene()
  if self.launch_mode == "cards" then
    return "card_library"
  end

  if self.view_mode == "influence" then
    return "influence"
  end

  return "gameplay"
end

function RuntimeContext:set_active_scene(scene_name)
  if scene_name == "card_library" then
    self.launch_mode = "cards"
    return
  end

  self.launch_mode = "game"
  if scene_name == "influence" then
    self.view_mode = "influence"
  else
    self.view_mode = "gameplay"
  end
end

function RuntimeContext:get_viewport()
  return self.viewport
end

return RuntimeContext
