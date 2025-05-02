local Card = require('card')
local CardTypes = require('card_types')
local CardEffects = require('card_effects')

local Deck = {}
Deck.__index = Deck

function Deck:new()
  local o = {}
  setmetatable(o, self)

  o.draw_pile = {}
  o.hand = {}
  o.discard_pile = {}
  
  return o
end

-- Function to create the initial starter deck using CardTypes
function Deck:create_starter_deck()
  self.draw_pile = {}
  self.hand = {}
  self.discard_pile = {}

  -- Define starter deck composition by ID
  local starter_card_ids = {
    'basic_strike', 'basic_strike', 'basic_strike', 'basic_strike', 'basic_strike', -- 5 Strikes
    'basic_defend', 'basic_defend', 'basic_defend', 'basic_defend', 'basic_defend'  -- 5 Defends
  }

  -- Create card objects from IDs
  for _, card_id in ipairs(starter_card_ids) do
    local cardData = CardTypes.createCardData(card_id)
    if cardData then
      table.insert(self.draw_pile, Card:new(cardData))
    else
      print("Warning: Could not create card data for ID: " .. card_id)
    end
  end

  self:shuffle()
end

-- Shuffle the draw pile using Fisher-Yates algorithm
function Deck:shuffle()
  local pile = self.draw_pile
  local n = #pile
  for i = n, 2, -1 do
    local j = love.math.random(i) -- LÖVE's random function
    pile[i], pile[j] = pile[j], pile[i] -- Swap
  end
  print("Draw pile shuffled.")
end

-- Draw 'count' cards from the draw pile into the hand
function Deck:draw(count)
  local drawn_count = 0
  for i = 1, count do
    -- Check if draw pile is empty
    if #self.draw_pile == 0 then
      -- If discard pile is also empty, we can't draw anymore
      if #self.discard_pile == 0 then
        print("No cards left in draw or discard piles.")
        break -- Exit the loop
      end
      
      -- Move discard pile to draw pile and shuffle
      print("Draw pile empty. Reshuffling discard pile...")
      self.draw_pile = self.discard_pile
      self.discard_pile = {}
      self:shuffle() -- Shuffle the newly refilled draw pile
      
      -- Check again if draw pile is empty after reshuffle (could happen if discard was empty)
      if #self.draw_pile == 0 then
         print("No cards left after reshuffle.")
         break
      end
    end
    
    -- Move one card from draw pile to hand
    local card = table.remove(self.draw_pile)
    table.insert(self.hand, card)
    drawn_count = drawn_count + 1
  end
  print("Drew " .. drawn_count .. " card(s).")
end

-- Attempt to play a card from hand, checking energy and executing effects
-- Returns the card if played successfully, otherwise nil
-- Accepts a 'context' table containing necessary game state (e.g., context.target)
function Deck:play_card(card_index, current_energy, context)
  context = context or {} -- Ensure context table exists

  -- Validate index
  if card_index < 1 or card_index > #self.hand then
    print("Error: Invalid card index for play: " .. card_index)
    return nil
  end

  local card = self.hand[card_index] -- Get card object
  local cost = card.cost or 0

  -- Check energy
  if current_energy < cost then
    print("Error: Not enough energy to play " .. card.name .. ". Needs " .. cost .. ", has " .. current_energy)
    return nil
  end

  -- Energy check passed
  print("Playing card: " .. card.name .. " (Cost: " .. cost .. ")")

  -- Execute card effect if defined
  if card.effect_fn_name then
    local effect_func = CardEffects[card.effect_fn_name]
    if effect_func and type(effect_func) == 'function' then
      -- Prepare context for the effect function
      local effect_context = {
        card = card,        -- The card object itself
        deck = self,        -- The deck instance
        target = context.target -- Pass the target from the main game loop
        -- Add other needed context later (e.g., player state)
      }
      print("Calling effect function: " .. card.effect_fn_name)
      effect_func(effect_context) -- Execute the effect
    else
      print("Warning: Effect function '" .. card.effect_fn_name .. "' not found or not a function in CardEffects.")
    end
  else
     print("Card '" .. card.name .. "' has no defined effect function.")
  end

  -- Now move the card from hand to discard AFTER effects are resolved
  local played_card = table.remove(self.hand, card_index)
  table.insert(self.discard_pile, played_card)

  -- The caller is still responsible for deducting the cost
  return played_card -- Return the played card object
end

return Deck 