local Viewport = {}
Viewport.__index = Viewport

local function clamp(value, min_value, max_value)
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
end

function Viewport.new(ref_w, ref_h, safe_insets)
  local self = setmetatable({}, Viewport)
  self.ref_w = math.max(1, math.floor(ref_w or 1728))
  self.ref_h = math.max(1, math.floor(ref_h or 798))
  self.safe_insets = {
    left = (safe_insets and safe_insets.left) or 0,
    right = (safe_insets and safe_insets.right) or 0,
    top = (safe_insets and safe_insets.top) or 0,
    bottom = (safe_insets and safe_insets.bottom) or 0
  }

  self.canvas = love.graphics.newCanvas(self.ref_w, self.ref_h)
  self.canvas:setFilter("linear", "linear")

  self.window_w = self.ref_w
  self.window_h = self.ref_h
  self.scale = 1
  self.viewport_w = self.ref_w
  self.viewport_h = self.ref_h
  self.offset_x = 0
  self.offset_y = 0
  self.safe_rect = { x = 0, y = 0, w = self.ref_w, h = self.ref_h }

  self:update(self.ref_w, self.ref_h)
  return self
end

function Viewport:update(window_w, window_h)
  self.window_w = math.max(1, math.floor(window_w or self.ref_w))
  self.window_h = math.max(1, math.floor(window_h or self.ref_h))

  self.scale = math.min(self.window_w / self.ref_w, self.window_h / self.ref_h)
  if self.scale <= 0 then
    self.scale = 1
  end

  self.viewport_w = self.ref_w * self.scale
  self.viewport_h = self.ref_h * self.scale
  self.offset_x = (self.window_w - self.viewport_w) * 0.5
  self.offset_y = (self.window_h - self.viewport_h) * 0.5

  local left = clamp(math.floor(self.safe_insets.left or 0), 0, self.ref_w - 1)
  local right = clamp(math.floor(self.safe_insets.right or 0), 0, self.ref_w - 1)
  local top = clamp(math.floor(self.safe_insets.top or 0), 0, self.ref_h - 1)
  local bottom = clamp(math.floor(self.safe_insets.bottom or 0), 0, self.ref_h - 1)

  local safe_w = math.max(1, self.ref_w - left - right)
  local safe_h = math.max(1, self.ref_h - top - bottom)
  self.safe_rect = { x = left, y = top, w = safe_w, h = safe_h }
end

function Viewport:begin_draw()
  love.graphics.setCanvas(self.canvas)
  love.graphics.origin()
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(1, 1, 1, 1)
end

function Viewport:end_draw()
  love.graphics.setCanvas()
  love.graphics.origin()
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.canvas, self.offset_x, self.offset_y, 0, self.scale, self.scale)
end

function Viewport:to_ui(x, y)
  local ui_x = (x - self.offset_x) / self.scale
  local ui_y = (y - self.offset_y) / self.scale
  return ui_x, ui_y
end

function Viewport:is_inside(x, y)
  return x >= self.offset_x and x <= (self.offset_x + self.viewport_w) and
    y >= self.offset_y and y <= (self.offset_y + self.viewport_h)
end

function Viewport:get_safe_rect()
  return {
    x = self.safe_rect.x,
    y = self.safe_rect.y,
    w = self.safe_rect.w,
    h = self.safe_rect.h
  }
end

return Viewport
