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

-- Placeholder for draw function (to be implemented next)
function Deck:draw(count)
  print("Drawing " .. count .. " cards...")
  -- Implementation needed here
end

return Deck 