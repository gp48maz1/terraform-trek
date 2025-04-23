local DrawHelpers = {}

-- Helper function to calculate card rotation angle
function DrawHelpers.calculate_card_angle(index, num_cards, max_angle_degrees)
  local center_index = (num_cards + 1) / 2
  local offset_factor = 0
  if num_cards > 1 then
    offset_factor = (index - center_index) / (num_cards / 2)
  end
  return offset_factor * math.rad(max_angle_degrees)
end

-- Helper function to calculate card vertical offset
function DrawHelpers.calculate_vertical_offset(index, num_cards, pixel_offset_per_step)
  local dy = 0
  if num_cards > 1 then
    if num_cards % 2 == 1 then -- Odd number of cards
      local center_idx = (num_cards + 1) / 2
      local steps = math.abs(index - center_idx)
      if steps == 0 then
        dy = 10 -- Specific offset for the middle card
      else
        dy = steps * pixel_offset_per_step
      end
    else -- Even number of cards
      local center1_idx = num_cards / 2
      local center2_idx = center1_idx + 1
      local steps = 0
      if index <= center1_idx then
        steps = center1_idx - index
      else -- index >= center2_idx
        steps = index - center2_idx
      end
      dy = steps * pixel_offset_per_step
    end
  end
  return dy
end

-- Helper function to draw a single card with transformations
function DrawHelpers.draw_transformed_card(card, x, y, dy, angle_rad, card_width, card_height)
  local card_ox = card_width / 2
  local card_oy = card_height / 2
  
  love.graphics.push()
  love.graphics.translate(x, y + dy)
  love.graphics.translate(card_ox, card_oy)
  love.graphics.rotate(angle_rad)
  love.graphics.translate(-card_ox, -card_oy)
  card:draw(0, 0)
  love.graphics.pop()
end

return DrawHelpers 