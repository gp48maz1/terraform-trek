local DeckWidget = {}

function DeckWidget.draw(rect, label, count, is_hovered)
  local base_fill = { 0.08, 0.11, 0.16, 0.95 }
  local hover_fill = { 0.12, 0.17, 0.24, 0.95 }
  local border = is_hovered and { 0.85, 0.92, 1.0, 1 } or { 0.55, 0.67, 0.82, 1 }
  local fill = is_hovered and hover_fill or base_fill

  love.graphics.setColor(unpack(fill))
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 8, 8)
  love.graphics.setColor(unpack(border))
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 8, 8)
  love.graphics.setLineWidth(1)

  local stack_w = rect.w - 46
  local stack_h = rect.h - 72
  local stack_x = rect.x + 23
  local stack_y = rect.y + 34
  for offset = 2, 0, -1 do
    love.graphics.setColor(0.16 + offset * 0.03, 0.2 + offset * 0.03, 0.28 + offset * 0.03, 0.95)
    love.graphics.rectangle("fill", stack_x + offset * 3, stack_y + offset * 2, stack_w, stack_h, 6, 6)
    love.graphics.setColor(0.85, 0.88, 0.95, 0.9)
    love.graphics.rectangle("line", stack_x + offset * 3, stack_y + offset * 2, stack_w, stack_h, 6, 6)
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(label, rect.x, rect.y + 10, rect.w, "center")
  love.graphics.printf("x" .. tostring(count), rect.x, rect.y + rect.h - 24, rect.w, "center")
end

return DeckWidget
