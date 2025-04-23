local Card = require('card')

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

-- Function to create the initial 10-card deck
function Deck:create_starter_deck()
  -- Clear existing piles first
  self.draw_pile = {}
  self.hand = {}
  self.discard_pile = {}

  -- Add 5 Attack cards
  for i = 1, 5 do
    table.insert(self.draw_pile, Card:new{
      name = "Strike",
      description = "Deal 6 damage.",
      cost = 1,
      category = "Attack"
    })
  end

  -- Add 5 Defend cards
  for i = 1, 5 do
    table.insert(self.draw_pile, Card:new{
      name = "Defend",
      description = "Gain 5 block.",
      cost = 1,
      category = "Skill" -- Example category
    })
  end
  
  -- Important: Shuffle the starting deck
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

-- Attempt to play a card from hand, checking energy cost
-- Returns the card if played successfully, otherwise nil
function Deck:play_card(card_index, current_energy)
  -- Validate index
  if card_index < 1 or card_index > #self.hand then
    print("Error: Invalid card index for play: " .. card_index)
    return nil 
  end

  local card = self.hand[card_index] -- Get card without removing yet
  local cost = card.cost or 0 -- Default cost to 0 if nil

  -- Check energy
  if current_energy < cost then
    print("Error: Not enough energy to play " .. card.name .. ". Needs " .. cost .. ", has " .. current_energy)
    return nil
  end
  
  -- Energy check passed, now move the card
  -- Remove from hand (use the index, as it's validated)
  card = table.remove(self.hand, card_index) 
  
  -- Add to discard pile
  table.insert(self.discard_pile, card)
  
  print("Played card: " .. card.name .. " (Cost: " .. cost .. ")")
  -- The caller will be responsible for deducting the cost
  return card -- Return the played card
end

return Deck 