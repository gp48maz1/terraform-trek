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
  o.image_placeholder = { width = 150, height = 225, color = {0, 0, 0} } -- Larger card size

  return o
end

-- Draw the card at position x, y
function Card:draw(x, y)
  local gfx = love.graphics
  local card_w = self.image_placeholder.width
  local card_h = self.image_placeholder.height
  local padding = 5
  local border_thickness = 2
  local header_h = 25
  local footer_h = 20
  local cost_radius = 10

  -- Colors
  local bg_color = {0.2, 0.2, 0.2} -- Dark gray background
  local border_color = {0.8, 0.8, 0.8} -- Light gray border
  local text_color = {1, 1, 1} -- White text
  local cost_bg_color = {1, 1, 0} -- Yellow cost background
  local cost_text_color = {0, 0, 0} -- Black cost text (better contrast on yellow)
  local img_placeholder_color = {0.7, 0.7, 0.7} -- Light gray for image area
  
  -- Determine category color
  local category_color = {0.5, 0.5, 0.5} -- Default gray
  if self.category == "Attack" then
    category_color = {1, 0, 0} -- Red
  elseif self.category == "Skill" then
    category_color = {0, 0, 1} -- Blue
  end -- Add more categories later if needed

  -- 1. Draw background
  gfx.setColor(bg_color[1], bg_color[2], bg_color[3])
  gfx.rectangle("fill", x, y, card_w, card_h)

  -- 2. Draw Header rectangle (based on category)
  gfx.setColor(category_color[1], category_color[2], category_color[3])
  gfx.rectangle("fill", x, y, card_w, header_h)
  
  -- 3. Draw Name text (on header)
  gfx.setColor(text_color[1], text_color[2], text_color[3])
  gfx.printf(self.name, x + padding, y + padding, card_w - 2 * padding, 'center')

  -- NEW: Draw Image Placeholder Box
  local img_w = card_w - 2 * padding
  local img_h = card_h * 0.5
  local img_x = x + padding
  local img_y = y + header_h + padding
  gfx.setColor(img_placeholder_color[1], img_placeholder_color[2], img_placeholder_color[3])
  gfx.rectangle("fill", img_x, img_y, img_w, img_h)

  -- 4. Draw Footer rectangle (based on category)
  gfx.setColor(category_color[1], category_color[2], category_color[3])
  gfx.rectangle("fill", x, y + card_h - footer_h, card_w, footer_h)
  
  -- 5. Draw Category text (on footer)
  gfx.setColor(text_color[1], text_color[2], text_color[3])
  gfx.printf(self.category, x + padding, y + card_h - footer_h + (footer_h - 12) / 2, card_w - 2 * padding, 'center') -- Adjust vertical alignment slightly
  
  -- 6. Draw Description (below image placeholder)
  gfx.setColor(text_color[1], text_color[2], text_color[3])
  local desc_y = img_y + img_h + padding -- Position below the image box
  -- Remove height constraint for simplicity, just center horizontally
  gfx.printf(self.description, x + padding, desc_y, card_w - 2 * padding, 'center')

  -- 7. Draw Cost (bottom-left, potentially overlapping footer slightly)
  if self.cost then
    local cost_cx = x + padding + cost_radius
    -- Position the center of the circle slightly inside the top edge of the footer, then nudge up
    local cost_cy = y + card_h - footer_h + cost_radius * 0.5 - 4
    
    -- Draw yellow circle background
    gfx.setColor(cost_bg_color[1], cost_bg_color[2], cost_bg_color[3])
    gfx.circle("fill", cost_cx, cost_cy, cost_radius)
    
    -- Draw cost text (black for contrast)
    gfx.setColor(cost_text_color[1], cost_text_color[2], cost_text_color[3])
    local font = gfx.getFont()
    local text_y = cost_cy - font:getHeight() / 2 -- Center vertically based on font height
    gfx.printf(self.cost, cost_cx - cost_radius, text_y, cost_radius * 2, 'center')
  end

  -- 8. Draw border (last, so it's on top)
  gfx.setColor(border_color[1], border_color[2], border_color[3])
  gfx.setLineWidth(border_thickness)
  gfx.rectangle("line", x, y, card_w, card_h)
  gfx.setLineWidth(1) -- Reset line width

  -- Reset color
  gfx.setColor(1, 1, 1)
end

return Card 