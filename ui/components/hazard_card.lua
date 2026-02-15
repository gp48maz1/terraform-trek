local HazardCard = {}

local function origin_color(origin)
  if origin == "space" then
    return { 0.86, 0.6, 0.24, 1 }
  end
  if origin == "climate" then
    return { 0.64, 0.8, 1, 1 }
  end
  if origin == "geologic" then
    return { 0.8, 0.52, 0.4, 1 }
  end
  return { 0.72, 0.8, 0.95, 1 }
end

function HazardCard.draw(rect, hazard)
  local border = origin_color(hazard and hazard.origin)

  love.graphics.setColor(0.08, 0.11, 0.18, 0.94)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 10, 10)
  love.graphics.setColor(border)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 10, 10)
  love.graphics.setLineWidth(1)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("INCOMING", rect.x, rect.y + 10, rect.w, "center")
  love.graphics.printf((hazard and hazard.name) or "Unknown Hazard", rect.x + 8, rect.y + 36, rect.w - 16, "center")
end

return HazardCard
