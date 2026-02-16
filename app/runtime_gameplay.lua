local DrawHelpers = require("draw_helpers")
local Background = require("background")

local GameplayLayout = require("ui.layout.gameplay_layout")

local DeckWidget = require("ui.components.deck_widget")
local EnergyOrb = require("ui.components.energy_orb")
local HazardCard = require("ui.components.hazard_card")
local GameplayHUD = require("ui.components.gameplay_hud")
local PrimitiveSnapshot = require("ui.components.primitive_snapshot")

local RuntimeGameplay = {}
RuntimeGameplay.__index = RuntimeGameplay

function RuntimeGameplay.new(ctx)
  return setmetatable({ ctx = ctx }, RuntimeGameplay)
end

function RuntimeGameplay:get_hand_layout(num_cards)
  return GameplayLayout.get_hand_layout(self.ctx:get_safe_rect(), num_cards, self.ctx.HAND_UI)
end

function RuntimeGameplay:get_draw_pile_rect()
  return GameplayLayout.get_deck_rect(self.ctx:get_safe_rect(), self.ctx.PILE_UI)
end

function RuntimeGameplay:get_discard_pile_rect()
  return GameplayLayout.get_discard_rect(self.ctx:get_safe_rect(), self.ctx.PILE_UI)
end

function RuntimeGameplay:get_end_turn_rect()
  local hand_layout = self:get_hand_layout(#self.ctx.player_deck.hand)
  return GameplayLayout.get_end_turn_rect(self.ctx:get_safe_rect(), hand_layout, self.ctx.HAND_UI, self.ctx.END_TURN_UI, self.ctx.PILE_UI)
end

function RuntimeGameplay:get_hazard_card_rect()
  return GameplayLayout.get_hazard_card_rect(self.ctx:get_safe_rect(), {
    x = self.ctx.target.x,
    y = self.ctx.target.y,
    radius = self.ctx.target.radius
  })
end

function RuntimeGameplay:get_primitive_snapshot_anchor()
  local safe = self.ctx:get_safe_rect()
  local planet = self.ctx.target
  local discard_rect = self:get_discard_pile_rect()
  local end_turn_rect = self:get_end_turn_rect()
  local radius = 30
  local half_w = 86 + radius + 10
  local half_h = 74 + radius + 24
  local desired_x = planet.x + planet.radius + 154
  local max_x = safe.x + safe.w - half_w - 4
  local min_x = safe.x + half_w + 10
  local min_x_by_planet = planet.x + planet.radius + half_w + 20
  local desired_y = planet.y + 6
  local max_y = math.min(discard_rect.y, end_turn_rect.y) - half_h - 14
  local min_y = safe.y + half_h + 12
  return {
    x = self.ctx:clamp_value(desired_x, math.max(min_x, min_x_by_planet), max_x),
    y = self.ctx:clamp_value(desired_y, min_y, max_y)
  }
end

function RuntimeGameplay:update_target_layout()
  if not self.ctx.target then
    return
  end
  local planet = GameplayLayout.get_planet(self.ctx:get_safe_rect())
  self.ctx.target.x = planet.x
  self.ctx.target.y = planet.y
  self.ctx.target.radius = planet.radius
end

function RuntimeGameplay:get_card_index_at_position(mx, my)
  local hand = self.ctx.player_deck.hand
  local num_cards = #hand
  local layout = self:get_hand_layout(num_cards)

  for i = num_cards, 1, -1 do
    local card_x = layout.start_x + (i - 1) * self.ctx.HAND_UI.card_spacing
    local dy = DrawHelpers.calculate_vertical_offset(i, num_cards, self.ctx.HAND_UI.pixel_offset_per_step)
    local current_y = layout.base_y + dy

    if self.ctx:point_in_rect(mx, my, card_x, current_y, self.ctx.HAND_UI.card_width, self.ctx.HAND_UI.card_height) then
      return i
    end
  end

  return nil
end

function RuntimeGameplay:draw_card_energy_overlay(card_x, card_y, angle_rad, scale)
  local overlay_scale = scale or 1
  love.graphics.setColor(0.42, 0.08, 0.08, 0.34)
  love.graphics.push()
  love.graphics.translate(card_x + self.ctx.HAND_UI.card_width / 2, card_y + self.ctx.HAND_UI.card_height / 2)
  love.graphics.scale(overlay_scale, overlay_scale)
  love.graphics.rotate(angle_rad)
  love.graphics.translate(-self.ctx.HAND_UI.card_width / 2, -self.ctx.HAND_UI.card_height / 2)
  love.graphics.rectangle("fill", 0, 0, self.ctx.HAND_UI.card_width, self.ctx.HAND_UI.card_height)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1, 1)
end

function RuntimeGameplay:draw_hand()
  local hand = self.ctx.player_deck.hand
  local num_cards = #hand
  local layout = self:get_hand_layout(num_cards)
  local start_x = layout.start_x
  local base_y = layout.base_y

  for i, card in ipairs(hand) do
    if i ~= self.ctx.hovered_card_index then
      local card_x = start_x + (i - 1) * self.ctx.HAND_UI.card_spacing
      local angle_rad = DrawHelpers.calculate_card_angle(i, num_cards, self.ctx.HAND_UI.max_angle_degrees)
      local dy = DrawHelpers.calculate_vertical_offset(i, num_cards, self.ctx.HAND_UI.pixel_offset_per_step)

      DrawHelpers.draw_transformed_card(card, card_x, base_y, dy, angle_rad, self.ctx.HAND_UI.card_width, self.ctx.HAND_UI.card_height)
      local number_x = card_x + self.ctx.HAND_UI.card_width / 2 - 5
      local number_y = base_y + dy - 15
      love.graphics.print(i, number_x, number_y)

      local cost = card.cost or 0
      if cost > self.ctx.current_energy then
        self:draw_card_energy_overlay(card_x, base_y + dy, angle_rad, 1)
      end
    end
  end

  if self.ctx.hovered_card_index then
    local i = self.ctx.hovered_card_index
    local card = hand[i]
    local card_x = start_x + (i - 1) * self.ctx.HAND_UI.card_spacing
    local angle_rad = DrawHelpers.calculate_card_angle(i, num_cards, self.ctx.HAND_UI.max_angle_degrees)
    local dy = DrawHelpers.calculate_vertical_offset(i, num_cards, self.ctx.HAND_UI.pixel_offset_per_step)

    local hover_scale = 1.15
    local hover_y_offset = -40
    love.graphics.push()
    love.graphics.translate(card_x + self.ctx.HAND_UI.card_width / 2, base_y + dy + hover_y_offset + self.ctx.HAND_UI.card_height / 2)
    love.graphics.scale(hover_scale, hover_scale)
    love.graphics.rotate(angle_rad)
    love.graphics.translate(-self.ctx.HAND_UI.card_width / 2, -self.ctx.HAND_UI.card_height / 2)
    card:draw(0, 0)
    love.graphics.pop()

    if (card.cost or 0) > self.ctx.current_energy then
      self:draw_card_energy_overlay(card_x, base_y + dy + hover_y_offset, angle_rad, hover_scale)
    end
  end
end

function RuntimeGameplay:draw_card_pile_widget(rect, label, count, is_hovered)
  DeckWidget.draw(rect, label, count, is_hovered)
end

function RuntimeGameplay:draw_energy_orb()
  local draw_rect = self:get_draw_pile_rect()
  local cx = draw_rect.x + math.floor(draw_rect.w * 0.5)
  local cy = draw_rect.y - 34
  EnergyOrb.draw(cx, cy, self.ctx.current_energy, self.ctx.max_energy)
end

function RuntimeGameplay:draw_pile_widgets()
  self:draw_card_pile_widget(self:get_draw_pile_rect(), "DECK", #self.ctx.player_deck.draw_pile, self.ctx.hovered_draw_pile)
  self:draw_card_pile_widget(self:get_discard_pile_rect(), "DISCARD", #self.ctx.player_deck.discard_pile, self.ctx.hovered_discard_pile)
  self:draw_energy_orb()
end

function RuntimeGameplay:draw_end_turn_button()
  local rect = self:get_end_turn_rect()
  local base = { 0.2, 0.32, 0.15, 0.95 }
  local hover = { 0.28, 0.45, 0.2, 0.98 }
  local border = { 0.72, 0.9, 0.62, 1 }
  local fill = self.ctx.hovered_end_turn and hover or base

  love.graphics.setColor(unpack(fill))
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 8, 8)
  love.graphics.setColor(unpack(border))
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 8, 8)
  love.graphics.setLineWidth(1)

  love.graphics.setColor(1, 1, 1, 1)
  local title_y = rect.y + math.floor(rect.h * 0.16)
  local key_y = rect.y + math.floor(rect.h * 0.5)
  love.graphics.printf("END TURN", rect.x, title_y, rect.w, "center")
  love.graphics.printf("(E)", rect.x, key_y, rect.w, "center")
end

function RuntimeGameplay:draw_hud()
  GameplayHUD.draw_hud({
    safe_rect = self.ctx:get_safe_rect(),
    world_index = self.ctx.world_index,
    world_count = #self.ctx.WORLD_CONFIGS,
    world_config = self.ctx.WORLD_CONFIGS[self.ctx.world_index],
    terraforming_state = self.ctx.terraforming_state,
    hazard_projection = self.ctx.terraforming_state:preview_next_hazard(),
    economy_snapshot = self.ctx.terraforming_state:get_economy_snapshot(),
    turn_summary = self.ctx.turn_summary,
    show_real_world_values = self.ctx.show_real_world_values,
    stat_order = self.ctx.STAT_ORDER,
    stat_labels = self.ctx.STAT_LABELS,
    get_stat_status = function(stat, value)
      return self.ctx:get_stat_status(stat, value)
    end,
    format_signed = function(value)
      return self.ctx:format_signed(value)
    end,
    get_real_world_mapping = function(stat, value)
      return self.ctx:get_real_world_mapping(stat, value)
    end,
    format_delta_list = function(deltas)
      return self.ctx:format_delta_list(deltas)
    end,
    get_hazard_origin_label = function(origin)
      return self.ctx:get_hazard_origin_label(origin)
    end
  })
end

function RuntimeGameplay:draw_controls_hint()
  local safe = self.ctx:get_safe_rect()
  local hand_layout = self:get_hand_layout(#self.ctx.player_deck.hand)
  GameplayHUD.draw_controls_hint({
    safe_rect = safe,
    hand_base_y = hand_layout.base_y,
    clamp_value = function(value, min_value, max_value)
      return self.ctx:clamp_value(value, min_value, max_value)
    end
  })
end

function RuntimeGameplay:draw_primitive_snapshot()
  local anchor = self:get_primitive_snapshot_anchor()
  PrimitiveSnapshot.draw({
    center_x = anchor.x,
    center_y = anchor.y,
    stats = self.ctx.terraforming_state.stats,
    stat_order = self.ctx.STAT_ORDER,
    stat_labels = self.ctx.STAT_LABELS,
    get_stat_status = function(stat, value)
      return self.ctx:get_stat_status(stat, value)
    end,
    format_signed = function(value)
      return self.ctx:format_signed(value)
    end,
    node_radius = 30
  })
end

function RuntimeGameplay:draw_status_overlay()
  GameplayHUD.draw_status_overlay({
    screen_w = love.graphics.getWidth(),
    campaign_state = self.ctx.campaign_state
  })
end

function RuntimeGameplay:draw_next_hazard_card()
  local projection = self.ctx.terraforming_state:preview_next_hazard()
  local rect = self:get_hazard_card_rect()
  local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 3.1)
  HazardCard.draw({
    rect = rect,
    projection = projection,
    target = { x = self.ctx.target.x, y = self.ctx.target.y, radius = self.ctx.target.radius },
    pulse = pulse,
    format_delta_list = function(deltas)
      return self.ctx:format_delta_list(deltas)
    end,
    magnetosphere_level = self.ctx.terraforming_state:get_magnetosphere_level(),
    magnetosphere_tier = self.ctx.terraforming_state:get_magnetosphere_tier(self.ctx.terraforming_state:get_magnetosphere_level())
  })
end

function RuntimeGameplay:update(dt)
  self.ctx:update_viewport_from_graphics()

  if not self.ctx.target or not self.ctx.player_deck then
    return
  end

  self.ctx.target:update(dt)
  self.ctx.influence_ui:sanitize_selection(#self.ctx.player_deck.hand)

  self.ctx.hovered_card_index = nil
  self.ctx.hovered_draw_pile = false
  self.ctx.hovered_discard_pile = false
  self.ctx.hovered_end_turn = false
  self.ctx.influence_ui:reset_hover_state()

  if self.ctx.campaign_state ~= "playing" then
    return
  end

  local raw_mx, raw_my = love.mouse.getPosition()
  local has_pointer, mx, my = self.ctx:map_pointer_to_ui(raw_mx, raw_my)
  if not has_pointer then
    return
  end

  self.ctx.hovered_card_index = self:get_card_index_at_position(mx, my)
  local draw_rect = self:get_draw_pile_rect()
  self.ctx.hovered_draw_pile = self.ctx:point_in_rect(mx, my, draw_rect.x, draw_rect.y, draw_rect.w, draw_rect.h)
  local discard_rect = self:get_discard_pile_rect()
  self.ctx.hovered_discard_pile = self.ctx:point_in_rect(mx, my, discard_rect.x, discard_rect.y, discard_rect.w, discard_rect.h)
  local end_turn_rect = self:get_end_turn_rect()
  self.ctx.hovered_end_turn = self.ctx:point_in_rect(mx, my, end_turn_rect.x, end_turn_rect.y, end_turn_rect.w, end_turn_rect.h)
end

function RuntimeGameplay:draw()
  if not self.ctx.player_deck or not self.ctx.target then
    return
  end

  if self.ctx.viewport then
    self.ctx.viewport:begin_draw()
  end

  self:update_target_layout()
  Background.draw_fill()
  Background.draw_stars()
  self.ctx.target:draw()
  self:draw_next_hazard_card()
  self:draw_primitive_snapshot()
  self:draw_hud()
  self:draw_pile_widgets()
  self:draw_end_turn_button()
  self:draw_hand()
  self:draw_controls_hint()

  if self.ctx.campaign_state ~= "playing" then
    self:draw_status_overlay()
  end

  if self.ctx.viewport then
    self.ctx.viewport:end_draw()
  end
end

function RuntimeGameplay:keypressed(key)
  if key == "r" then
    self.ctx:start_campaign()
    return
  end

  if key == "v" then
    self.ctx.view_mode = "influence"
    return
  end

  if key == "m" then
    self.ctx.show_real_world_values = not self.ctx.show_real_world_values
    return
  end

  if self.ctx.campaign_state == "world_won" then
    if key == "n" then
      self.ctx:setup_world(self.ctx.world_index + 1)
    end
    return
  end

  if self.ctx.campaign_state ~= "playing" then
    return
  end

  if key == "e" then
    self.ctx:end_turn()
    return
  end

  local num = tonumber(key)
  if not num or num < 1 or num > #self.ctx.player_deck.hand then
    return
  end

  self.ctx:try_play_card(num)
end

function RuntimeGameplay:mousepressed(x, y, button)
  if button ~= 1 then
    return
  end

  local has_pointer, mapped_x, mapped_y = self.ctx:map_pointer_to_ui(x, y)
  if not has_pointer then
    return
  end

  if self.ctx.campaign_state ~= "playing" then
    return
  end

  local end_turn_rect = self:get_end_turn_rect()
  if self.ctx:point_in_rect(mapped_x, mapped_y, end_turn_rect.x, end_turn_rect.y, end_turn_rect.w, end_turn_rect.h) then
    self.ctx:end_turn()
    return
  end

  local card_index = self:get_card_index_at_position(mapped_x, mapped_y)
  if card_index then
    self.ctx:try_play_card(card_index)
  end
end

function RuntimeGameplay:wheelmoved(_, _)
end

return RuntimeGameplay
