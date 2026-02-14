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

local WORLD_CONFIGS = {
  {
    name = "Dustbound Expanse",
    tier = "Low Threat",
    goal = 18,
    turn_limit = 9,
    hazard_strength = 1,
    targets = { heat = 0, air = 0, water = 0, soil = 0 }
  },
  {
    name = "Iron Tempest",
    tier = "Elite",
    goal = 22,
    turn_limit = 9,
    hazard_strength = 1,
    targets = { heat = 1, air = 0, water = 1, soil = 0 }
  },
  {
    name = "Abyssal Crown",
    tier = "Boss",
    goal = 26,
    turn_limit = 10,
    hazard_strength = 2,
    targets = { heat = -1, air = 1, water = 0, soil = 1 }
  }
}

local player_deck
local target
local terraforming_state
local world_index = 1
local campaign_state = "playing" -- playing | world_won | campaign_won | campaign_lost
local turn_summary = nil
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
  width = 110,
  height = 150
}

local END_TURN_UI = {
  width = 170,
  height = 50,
  x_padding = 30,
  y = 520
}

local function format_signed(value)
  if value > 0 then
    return "+" .. tostring(value)
  end
  return tostring(value)
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

local function point_in_rect(px, py, rx, ry, rw, rh)
  return px >= rx and px <= rx + rw and py >= ry and py <= ry + rh
end

local function get_hand_layout(num_cards)
  local total_hand_width = 0
  if num_cards > 0 then
    total_hand_width = HAND_UI.card_width + (num_cards - 1) * HAND_UI.card_spacing
  end
  local start_x = (love.graphics.getWidth() - total_hand_width) / 2
  return {
    start_x = start_x,
    base_y = HAND_UI.base_y
  }
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

local function setup_world(index)
  world_index = index
  local config = WORLD_CONFIGS[index]
  terraforming_state = TerraformingState.new(config)
  turn_summary = nil
  campaign_state = "playing"

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
  end
end

local function draw_stats()
  local base_x = 10
  local base_y = 110

  for i, key in ipairs(STAT_ORDER) do
    local value = terraforming_state.stats[key]
    local target_value = terraforming_state.targets[key]
    local distance = math.abs(value - target_value)

    local color = { 0.85, 0.85, 0.85, 1 }
    if distance <= 1 then
      color = { 0.45, 0.9, 0.45, 1 }
    elseif distance >= 3 then
      color = { 0.95, 0.45, 0.45, 1 }
    elseif distance == 2 then
      color = { 0.95, 0.82, 0.35, 1 }
    end

    love.graphics.setColor(unpack(color))
    love.graphics.print(
      STAT_LABELS[key] .. ": " .. format_signed(value) .. "  (target " .. format_signed(target_value) .. ")",
      base_x,
      base_y + (i - 1) * 22
    )
  end

  love.graphics.setColor(1, 1, 1, 1)
end

local function draw_card_pile_widget(rect, label, count, is_hovered)
  local base_fill = { 0.08, 0.11, 0.16, 0.95 }
  local hover_fill = { 0.12, 0.17, 0.24, 0.95 }
  local border = is_hovered and { 0.85, 0.92, 1.0, 1 } or { 0.55, 0.67, 0.82, 1 }

  local fill = base_fill
  if is_hovered then
    fill = hover_fill
  end

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
    love.graphics.print("Last Turn Hazard: " .. turn_summary.hazard, 10, 210)
    love.graphics.print("Hazard Delta: " .. format_delta_list(turn_summary.hazard_deltas), 10, 230)
    love.graphics.print("Coupling Delta: " .. format_delta_list(turn_summary.coupling_deltas), 10, 250)
    love.graphics.print(
      "Growth " .. turn_summary.growth ..
      " - Penalty " .. turn_summary.penalty ..
      " = Net " .. format_signed(turn_summary.net),
      10,
      270
    )
  end

  love.graphics.print("Controls: Click card or 1-9 | Click End Turn or E | R restart", 10, love.graphics.getHeight() - 22)
end

local function draw_status_overlay()
  local width = love.graphics.getWidth()
  local height = love.graphics.getHeight()
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

function love.update(dt)
  target:update(dt)
  hovered_card_index = nil
  hovered_draw_pile = false
  hovered_discard_pile = false
  hovered_end_turn = false

  if campaign_state ~= "playing" then
    return
  end

  local mx, my = love.mouse.getPosition()
  hovered_card_index = get_card_index_at_position(mx, my)

  local draw_rect = get_draw_pile_rect()
  hovered_draw_pile = point_in_rect(mx, my, draw_rect.x, draw_rect.y, draw_rect.w, draw_rect.h)

  local discard_rect = get_discard_pile_rect()
  hovered_discard_pile = point_in_rect(mx, my, discard_rect.x, discard_rect.y, discard_rect.w, discard_rect.h)

  local end_turn_rect = get_end_turn_rect()
  hovered_end_turn = point_in_rect(mx, my, end_turn_rect.x, end_turn_rect.y, end_turn_rect.w, end_turn_rect.h)
end

function love.draw()
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
end

function love.keypressed(key)
  if key == "r" then
    start_campaign()
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
  if not num or num < 1 or num > 9 then
    return
  end

  if num > #player_deck.hand then
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
