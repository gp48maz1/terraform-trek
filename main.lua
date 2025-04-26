local Deck = require('deck')
local TerraformingTarget = require('terraforming_target')
local DrawHelpers = require('draw_helpers')
local RelationshipsView = require('planetary_system_relationships') -- Require the new module

local player_deck
local max_energy = 3
local current_energy = 0
local target

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
  love.graphics.print("Hand:", 10, 400) -- Keep label on left
  local hand = player_deck.hand
  local num_cards = #hand
  local card_width = 150 -- Assuming width from card.lua
  local card_height = 225 -- Assuming height from card.lua
  local card_spacing = 175 -- Increased spacing to prevent overlap (was 160)
  
  -- Calculate total width and starting position for centering
  local total_hand_width = 0
  if num_cards > 0 then
    total_hand_width = card_width + (num_cards - 1) * card_spacing
  end
  local start_x = (love.graphics.getWidth() - total_hand_width) / 2
  
  -- Constants for drawing
  local max_angle_degrees = 10 -- Max rotation for outer cards
  local pixel_offset_per_step = 20 -- Increased from 2
  local base_y = 420

  for i, card in ipairs(hand) do
    local card_x = start_x + (i-1) * card_spacing
    
    -- Calculate properties using helper functions
    local angle_rad = DrawHelpers.calculate_card_angle(i, num_cards, max_angle_degrees)
    local dy = DrawHelpers.calculate_vertical_offset(i, num_cards, pixel_offset_per_step)
    
    -- Draw the card using the helper function
    DrawHelpers.draw_transformed_card(card, card_x, base_y, dy, angle_rad, card_width, card_height)
    
    -- Draw index number above card's original (unrotated) top-center position for simplicity
    local number_x = card_x + card_width / 2 - 5 -- Adjust slightly for number width
    local number_y = base_y + dy - 15 -- Position above the card, considering the offset
    love.graphics.print(i, number_x, number_y) 
  end
end

-- Add the update function to handle time-based changes
function love.update(dt)
  if gameState == 'gameplay' then
    target:update(dt) -- Update the terraforming target (for spinning, etc.)
    -- Add other gameplay-specific updates here if needed
  elseif gameState == 'relationships' then
    -- No updates needed for the static relationship view (yet)
  end
end

function love.draw()
  if gameState == 'gameplay' then
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

  elseif gameState == 'relationships' then
    RelationshipsView.draw() -- Call the draw function from the relationships module
    love.graphics.print("Press 'v' to return to Game", 10, love.graphics.getHeight() - 20)
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
