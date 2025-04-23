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
  love.graphics.print("Hand:", 10, 400)
  local hand = player_deck.hand
  local card_spacing = 110 -- Width + spacing
  for i, card in ipairs(hand) do
    card:draw(10 + (i-1) * card_spacing, 420)
    -- Draw index number above card
    love.graphics.print(i, 10 + (i-1) * card_spacing + 45, 405) 
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
