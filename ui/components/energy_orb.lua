local EnergyOrb = {}

local function clamp(value, min_value, max_value)
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
end

function EnergyOrb.draw(x, y, current, max_value)
  local radius = 20
  local ratio = 0
  if max_value and max_value > 0 then
    ratio = clamp((current or 0) / max_value, 0, 1)
  end

  local start_angle = -math.pi * 0.5
  local end_angle = start_angle + (math.pi * 2 * ratio)

  love.graphics.setColor(0.09, 0.1, 0.14, 0.96)
  love.graphics.circle("fill", x, y, radius + 5)
  love.graphics.setColor(0.88, 0.28, 0.28, 0.9)
  love.graphics.setLineWidth(6)
  love.graphics.arc("line", "open", x, y, radius + 1, 0, math.pi * 2)
  love.graphics.setColor(0.95, 0.82, 0.35, 1)
  if ratio > 0 then
    love.graphics.arc("line", "open", x, y, radius + 1, start_angle, end_angle)
  end
  love.graphics.setLineWidth(1)

  love.graphics.setColor(0.18, 0.14, 0.08, 1)
  love.graphics.circle("fill", x, y, radius - 5)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(tostring(current or 0) .. "/" .. tostring(max_value or 0), x - radius, y - 6, radius * 2, "center")
end

return EnergyOrb
