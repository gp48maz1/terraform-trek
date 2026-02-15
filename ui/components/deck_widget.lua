local DeckWidget = {}

function DeckWidget.draw(rect, label, count, is_hovered)
  local fill = is_hovered and { 0.12, 0.17, 0.24, 0.95 } or { 0.08, 0.11, 0.16, 0.95 }
  local border = is_hovered and { 0.85, 0.92, 1.0, 1 } or { 0.55, 0.67, 0.82, 1 }

  love.graphics.setColor(fill)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 8, 8)
  love.graphics.setColor(border)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 8, 8)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(label, rect.x, rect.y + 10, rect.w, "center")
  love.graphics.printf("x" .. tostring(count), rect.x, rect.y + rect.h - 24, rect.w, "center")
end

return DeckWidget
