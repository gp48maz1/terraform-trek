local Deck = require('deck')
local TerraformingTarget = require('terraforming_target')
local DrawHelpers = require('draw_helpers')
local RelationshipsView = require('planetary_system_relationships') -- Require the new module
local PlanetarySystem = require('planetary_system_of_equations') -- Require the system module
local Background = require('background') -- Require the background module

local player_deck
local max_energy = 3
local current_energy = 0
local target
local hovered_card_index = nil

-- Create a sample planetary system instance for the relationship view
-- In a real game, you would pass the actual system instance you want to inspect
local relationship_system_instance = PlanetarySystem.new(
    {S = 1.0, M = 1.0, T = 1.0, L = 0.8, A = 1.1, H = 0.9, B = 1.2}, 
    {alpha1 = 0.1, alpha2 = 0.05, beta1 = 0.03} -- Example with some custom coeffs
)

local gameState = 'gameplay' -- Initial game state

-- Helper functions for energy management
local function reset_energy()
  current_energy = max_energy
  print("Energy reset to " .. current_energy)
end

local function can_afford(cost)
  return current_energy >= (cost or 0) -- Treat nil cost as 0
end

local function spend_energy(cost)
  current_energy = current_energy - (cost or 0)
  print("Spent " .. (cost or 0) .. " energy. Remaining: " .. current_energy)
end

function love.load()
  -- Set random seed based on time for better shuffling
  love.math.setRandomSeed(os.time())
  
  Background.load() -- Load the background first

  -- Create and initialize the deck
  player_deck = Deck:new()
  player_deck:create_starter_deck() -- Creates and shuffles
  
  -- Create the target
  target = TerraformingTarget:new()
  
  -- Start the first turn
  reset_energy() 
  player_deck:draw(5) -- Draw initial hand
  
  print("Game Loaded. Initial Hand Drawn. Energy set.")
end

-- Function to draw the player's hand
local function draw_hand()
  -- Use the globally tracked hovered_card_index
  -- love.graphics.print("Hand:", 10, 400) -- Keep label on left (Keep or remove as desired)
  local hand = player_deck.hand
  local num_cards = #hand
  local card_width = 150 
  local card_height = 225
  local card_spacing = 175 
  
  -- Calculate total width and starting position for centering
  local total_hand_width = 0
  if num_cards > 0 then
    total_hand_width = card_width + (num_cards - 1) * card_spacing
  end
  local start_x = (love.graphics.getWidth() - total_hand_width) / 2
  
  -- Constants for drawing
  local max_angle_degrees = 10 
  local pixel_offset_per_step = 20 
  local base_y = 420

  -- 1. Draw non-hovered cards first
  for i, card in ipairs(hand) do
    if i ~= hovered_card_index then -- Only draw if NOT hovered
      local card_x = start_x + (i-1) * card_spacing
      local angle_rad = DrawHelpers.calculate_card_angle(i, num_cards, max_angle_degrees)
      local dy = DrawHelpers.calculate_vertical_offset(i, num_cards, pixel_offset_per_step)
      
      DrawHelpers.draw_transformed_card(card, card_x, base_y, dy, angle_rad, card_width, card_height)
      
      -- Draw index number 
      local number_x = card_x + card_width / 2 - 5 
      local number_y = base_y + dy - 15 
      love.graphics.print(i, number_x, number_y) 
    end
  end

  -- 2. Draw the hovered card last (if any)
  if hovered_card_index then
    local i = hovered_card_index
    local card = hand[i]
    local card_x = start_x + (i-1) * card_spacing
    
    -- Original transformation values
    local angle_rad = DrawHelpers.calculate_card_angle(i, num_cards, max_angle_degrees)
    local dy = DrawHelpers.calculate_vertical_offset(i, num_cards, pixel_offset_per_step)
    
    -- Hover effect parameters
    local hover_scale = 1.15 -- Make it noticeably larger
    local hover_y_offset = -40 -- Move it up significantly

    -- Use push/pop for isolation
    love.graphics.push()
    
    -- Apply transformations for hover effect:
    -- 1. Translate to the card's final base position (including vertical offset and hover offset)
    love.graphics.translate(card_x + card_width / 2, base_y + dy + hover_y_offset + card_height / 2)
    -- 2. Scale
    love.graphics.scale(hover_scale, hover_scale)
    -- 3. Rotate
    love.graphics.rotate(angle_rad)
    -- 4. Translate back by half width/height to draw from top-left corner of the *scaled* card
    love.graphics.translate(-card_width / 2, -card_height / 2)
    
    -- Draw the card itself (at 0,0 because transformations handle position)
    card:draw(0, 0) -- Assuming Card:draw draws at given x,y

    love.graphics.pop() -- Restore previous graphics state

    -- Draw index number for hovered card (optional, might be visually cluttered)
    -- Position it relative to the original position for consistency
    -- local number_x = card_x + card_width / 2 - 5 
    -- local number_y = base_y + dy - 15 - hover_y_offset -- Adjust slightly higher due to hover
    -- love.graphics.setColor(1,1,0) -- Maybe highlight?
    -- love.graphics.print(i, number_x, number_y)
    -- love.graphics.setColor(1,1,1)
  end
end

-- Add the update function to handle time-based changes
function love.update(dt)
  -- Reset hovered card each frame
  hovered_card_index = nil

  -- Get mouse position
  local mx, my = love.mouse.getPosition()

  if gameState == 'gameplay' then
    target:update(dt) -- Update the terraforming target (for spinning, etc.)
    
    -- Calculate hand layout parameters (reuse from draw_hand if possible, or recalculate)
    local hand = player_deck.hand
    local num_cards = #hand
    local card_width = 150
    local card_height = 225
    local card_spacing = 175
    local total_hand_width = 0
    if num_cards > 0 then
      total_hand_width = card_width + (num_cards - 1) * card_spacing
    end
    local start_x = (love.graphics.getWidth() - total_hand_width) / 2
    local max_angle_degrees = 10 
    local pixel_offset_per_step = 20
    local base_y = 420

    -- Check for hover, iterating backwards (top cards first)
    for i = num_cards, 1, -1 do
      local card = hand[i]
      local card_x = start_x + (i-1) * card_spacing
      local angle_rad = DrawHelpers.calculate_card_angle(i, num_cards, max_angle_degrees)
      local dy = DrawHelpers.calculate_vertical_offset(i, num_cards, pixel_offset_per_step)
      local current_y = base_y + dy

      -- Create a rough bounding box check (ignoring rotation for simplicity first)
      -- More accurate check would involve transforming mouse coordinates or using polygons
      if mx >= card_x and mx <= card_x + card_width and 
         my >= current_y and my <= current_y + card_height then
         hovered_card_index = i
         break -- Found the topmost hovered card
      end
    end

    -- Add other gameplay-specific updates here if needed
  elseif gameState == 'relationships' then
    RelationshipsView:update(dt) -- Call the relationships view update function
  end
end

function love.draw()
  -- Note: Background drawing is now handled *within* each state block

  if gameState == 'gameplay' then
    -- Draw only the fill and stars for gameplay
    Background.draw_fill()
    Background.draw_stars()

    -- Display Energy
    love.graphics.print("Energy: " .. current_energy .. " / " .. max_energy, 10, 10)

    -- Draw the target planet
    target:draw()

    -- Display Draw Pile and Discard Pile counts
    love.graphics.print("Draw Pile: " .. #player_deck.draw_pile, 10, 30)
    love.graphics.print("Discard Pile: " .. #player_deck.discard_pile, 10, 50)

    -- Display Hand (using the new function)
    draw_hand()

    -- Instructions to switch view
    love.graphics.print("Press 'v' to view System Relationships", 10, love.graphics.getHeight() - 20)
    
    -- Reset color after gameplay drawing
    love.graphics.setColor(1, 1, 1, 1) 

  elseif gameState == 'relationships' then
    -- 1. Draw the solid light background color
    local bg_color = {0.7, 0.75, 0.8, 1} -- Light Blue-Grey
    love.graphics.setColor(unpack(bg_color))
    love.graphics.rectangle('fill', 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    -- 2. Draw *only* the clouds on top
    Background.draw_clouds()

    -- 3. Draw the relationships view
    RelationshipsView.draw(relationship_system_instance) 
    love.graphics.print("Press 'v' to return to Game", 10, love.graphics.getHeight() - 20)
    
    -- 4. Reset color to white afterwards for safety
    love.graphics.setColor(1, 1, 1, 1) 
  end
end

function love.keypressed(key)
  -- State switching key
  if key == 'v' then
    if gameState == 'gameplay' then
      gameState = 'relationships'
      print("Switched to Relationships View")
    elseif gameState == 'relationships' then
      gameState = 'gameplay'
      print("Switched to Gameplay View")
    end
    return -- Don't process other keys if we just switched state
  end

  -- Gameplay specific key handling
  if gameState == 'gameplay' then
    -- Try to play card corresponding to number keys 1-9
    local num = tonumber(key)
    if num and num >= 1 and num <= 9 then
      local card_index = num
      if card_index <= #player_deck.hand then
        local card_to_play = player_deck.hand[card_index] -- Get card to check cost
        local cost = card_to_play.cost or 0
        
        if can_afford(cost) then
          local played_card = player_deck:play_card(card_index, current_energy)
          if played_card then
            spend_energy(played_card.cost) -- Use cost from the actually played card
          end
        else
          print("Cannot afford card " .. card_index .. " (" .. card_to_play.name .. ")")
        end
      else
        print("Invalid hand index: " .. card_index)
      end
    end
    
    -- Manual energy reset for testing
    if key == 'r' then
      reset_energy()
    end

    -- Manual draw for testing
    if key == 'd' then
      player_deck:draw(1)
    end
  end
  
  -- Add key handling for other states here if needed
end
