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

-- Draw the card at position x, y
function Card:draw(x, y)
  local gfx = love.graphics
  local card_w = self.image_placeholder.width
  local card_h = self.image_placeholder.height
  local padding = 5
  local border_thickness = 2

  -- Colors
  local bg_color = {0.2, 0.2, 0.2} -- Dark gray background
  local border_color = {0.8, 0.8, 0.8} -- Light gray border
  local text_color = {1, 1, 1} -- White text
  local cost_color = {1, 1, 0} -- Yellow cost
  local category_color = {0.7, 0.7, 1} -- Light blue category

  -- Draw background
  gfx.setColor(bg_color[1], bg_color[2], bg_color[3])
  gfx.rectangle("fill", x, y, card_w, card_h)

  -- Draw border
  gfx.setColor(border_color[1], border_color[2], border_color[3])
  gfx.setLineWidth(border_thickness)
  gfx.rectangle("line", x, y, card_w, card_h)
  gfx.setLineWidth(1) -- Reset line width

  -- Draw Name (Larger font, centered maybe? For now, top-left)
  gfx.setColor(text_color[1], text_color[2], text_color[3])
  local current_font = gfx.getFont()
  -- If we had a larger font: gfx.setFont(larger_font)
  gfx.printf(self.name, x + padding, y + padding, card_w - 2 * padding, 'left')
  -- gfx.setFont(current_font) -- Reset font if changed

  -- Draw Cost (Top right)
  if self.cost then
    gfx.setColor(cost_color[1], cost_color[2], cost_color[3])
    gfx.printf(self.cost, x + card_w - padding - 15, y + padding, 15, 'right') 
  end

  -- Draw Description (Centered below name/cost)
  gfx.setColor(text_color[1], text_color[2], text_color[3])
  gfx.printf(self.description, x + padding, y + 40, card_w - 2 * padding, 'left')

  -- Draw Category (Bottom center)
  gfx.setColor(category_color[1], category_color[2], category_color[3])
  gfx.printf(self.category, x + padding, y + card_h - padding - 15, card_w - 2 * padding, 'center')

  -- Reset color
  gfx.setColor(1, 1, 1)
end

return Card 