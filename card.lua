local Card = {}
Card.__index = Card

function Card:new(o)
  o = o or {}
  setmetatable(o, self)

  -- Validate required fields
  assert(o.name, "Card must have a name.")
  assert(o.description, "Card must have a description.")
  assert(o.category, "Card must have a category.")

  -- Set defaults
  o.cost = o.cost -- Can be nil if not provided
  
  -- Placeholder for image - we can refine this later
  o.image_placeholder = { width = 100, height = 150, color = {0, 0, 0} } -- Black box

  return o
end

-- Example draw function (placeholder)
function Card:draw(x, y)
  local gfx = love.graphics
  
  -- Draw placeholder box
  gfx.setColor(self.image_placeholder.color[1], self.image_placeholder.color[2], self.image_placeholder.color[3])
  gfx.rectangle("fill", x, y, self.image_placeholder.width, self.image_placeholder.height)
  
  -- Draw text (simple layout)
  gfx.setColor(1, 1, 1) -- White text
  gfx.printf(self.name, x + 5, y + 5, self.image_placeholder.width - 10)
  if self.cost then
    gfx.printf("Cost: " .. self.cost, x + 5, y + 30, self.image_placeholder.width - 10)
  end
  gfx.printf(self.description, x + 5, y + 50, self.image_placeholder.width - 10)
  gfx.printf("Category: " .. self.category, x + 5, y + self.image_placeholder.height - 20, self.image_placeholder.width - 10)
  
  -- Reset color
  gfx.setColor(1, 1, 1)
end

return Card 