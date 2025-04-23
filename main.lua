local Deck = require('deck')

local player_deck
local max_energy = 3
local current_energy = 0

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
  
  -- Start the first turn
  reset_energy() 
  player_deck:draw(5) -- Draw initial hand
  
  print("Game Loaded. Initial Hand Drawn. Energy set.")
end

function love.draw()
  -- Display Energy
  love.graphics.print("Energy: " .. current_energy .. " / " .. max_energy, 10, 10)
  
  -- Display Draw Pile and Discard Pile counts
  love.graphics.print("Draw Pile: " .. #player_deck.draw_pile, 10, 30)
  love.graphics.print("Discard Pile: " .. #player_deck.discard_pile, 10, 50)
  
  -- Display Hand
  love.graphics.print("Hand:", 10, 400) -- Keep label on left
  local hand = player_deck.hand
  local num_cards = #hand
  local card_width = 150 -- Assuming width from card.lua
  local card_spacing = 175 -- Increased spacing to prevent overlap (was 160)
  
  -- Calculate total width and starting position for centering
  local total_hand_width = 0
  if num_cards > 0 then
    total_hand_width = card_width + (num_cards - 1) * card_spacing
  end
  local start_x = (love.graphics.getWidth() - total_hand_width) / 2
  
  -- Draw the cards centered and fanned out
  local max_angle_degrees = 10 -- Max rotation for outer cards
  local card_height = 225 -- Assuming height from card.lua
  
  for i, card in ipairs(hand) do
    local card_x = start_x + (i-1) * card_spacing
    local card_y = 420 -- Reset to constant base Y
    
    -- Calculate rotation based on position in hand
    local center_index = (num_cards + 1) / 2
    local offset_factor = 0
    if num_cards > 1 then
      offset_factor = (i - center_index) / (num_cards / 2)
    end
    local angle_rad = offset_factor * math.rad(max_angle_degrees)
    
    -- Calculate stepped vertical offset based on distance from center
    local dy = 0
    local pixel_offset_per_step = 20 -- Increased from 2
    if num_cards > 1 then
      if num_cards % 2 == 1 then -- Odd number of cards
        local center_idx = (num_cards + 1) / 2
        local steps = math.abs(i - center_idx)
        if steps == 0 then
          dy = 10 -- Specific offset for the middle card
        else
          dy = steps * pixel_offset_per_step
        end
      else -- Even number of cards
        local center1_idx = num_cards / 2
        local center2_idx = center1_idx + 1
        local steps = 0
        if i <= center1_idx then
          steps = center1_idx - i
        else -- i >= center2_idx
          steps = i - center2_idx
        end
        dy = steps * pixel_offset_per_step
      end
    end

    -- Define rotation origin (center)
    local card_ox = card_width / 2
    local card_oy = card_height / 2
    
    -- Apply transformations
    love.graphics.push()
    -- 1. Translate to card's base position + arc offset (reverted)
    love.graphics.translate(card_x, card_y + dy) 
    -- 2. Translate to rotation origin (center of the card)
    love.graphics.translate(card_ox, card_oy)
    -- 3. Rotate
    love.graphics.rotate(angle_rad)
    -- 4. Translate back from rotation origin
    love.graphics.translate(-card_ox, -card_oy) 
    -- 5. Draw the card itself at (0,0)
    card:draw(0, 0)
    -- 6. Restore previous transformations
    love.graphics.pop()
    
    -- Draw index number above card's original (unrotated) top-center position for simplicity
    local number_x = card_x + card_width / 2 - 5 -- Adjust slightly for number width
    local number_y = card_y + dy - 15 -- Position above the card, considering the reverted drop
    love.graphics.print(i, number_x, number_y) 
  end
end

function love.keypressed(key)
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
