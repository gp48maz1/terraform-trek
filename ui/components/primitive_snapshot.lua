local PrimitiveSnapshot = {}

local OFFSETS = {
  heat = { x = 0, y = -74 },
  air = { x = -86, y = 0 },
  water = { x = 86, y = 0 },
  soil = { x = 0, y = 74 }
}

local function fit_single_line(text, max_width)
  local font = love.graphics.getFont()
  if font:getWidth(text) <= max_width then
    return text
  end

  local suffix = "..."
  local suffix_w = font:getWidth(suffix)
  local trimmed = text
  while #trimmed > 0 and (font:getWidth(trimmed) + suffix_w) > max_width do
    trimmed = string.sub(trimmed, 1, #trimmed - 1)
  end

  if #trimmed == 0 then
    return suffix
  end
  return trimmed .. suffix
end

function PrimitiveSnapshot.draw(opts)
  if not opts then
    return
  end

  local center_x = opts.center_x
  local center_y = opts.center_y
  local stats = opts.stats or {}
  local stat_order = opts.stat_order or {}
  local stat_labels = opts.stat_labels or {}
  local get_stat_status = opts.get_stat_status
  local format_signed = opts.format_signed
  local radius = opts.node_radius or 30

  if not center_x or not center_y or not get_stat_status or not format_signed then
    return
  end

  local shell_color = opts.shell_color or { 0.28, 0.62, 0.95, 0.16 }
  love.graphics.setColor(unpack(shell_color))
  for i = 1, 3 do
    local shell_r = radius + 24 + (i * 9)
    love.graphics.circle("line", center_x, center_y, shell_r)
  end

  for _, key in ipairs(stat_order) do
    local offset = OFFSETS[key]
    if offset then
      local value = stats[key] or 0
      local status, color = get_stat_status(key, value)
      local node_x = center_x + offset.x
      local node_y = center_y + offset.y

      love.graphics.setColor(0.08, 0.1, 0.14, 0.95)
      love.graphics.circle("fill", node_x, node_y, radius)
      love.graphics.setColor(color[1], color[2], color[3], 1)
      love.graphics.setLineWidth(2.5)
      love.graphics.circle("line", node_x, node_y, radius)
      love.graphics.setLineWidth(1)

      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.printf(stat_labels[key] or key, node_x - radius + 8, node_y - 16, (radius * 2) - 16, "center")
      love.graphics.printf(format_signed(value), node_x - radius + 8, node_y + 1, (radius * 2) - 16, "center")

      local status_w = math.max(96, (radius * 2) + 26)
      local status_h = 16
      local status_x = node_x - math.floor(status_w * 0.5)
      local status_y = node_y + radius + 7
      love.graphics.setColor(0.06, 0.08, 0.12, 0.88)
      love.graphics.rectangle("fill", status_x, status_y, status_w, status_h, 7, 7)
      love.graphics.setColor(color[1], color[2], color[3], 0.95)
      love.graphics.rectangle("line", status_x, status_y, status_w, status_h, 7, 7)
      love.graphics.setColor(0.83, 0.9, 0.98, 1)
      love.graphics.printf(fit_single_line(status, status_w - 10), status_x + 5, status_y + 2, status_w - 10, "center")
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return PrimitiveSnapshot
