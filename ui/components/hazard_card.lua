local HazardCard = {}

local function origin_color(origin)
  if origin == "space" then
    return { 0.95, 0.62, 0.28, 1 }
  elseif origin == "atmospheric" then
    return { 0.55, 0.76, 0.97, 1 }
  elseif origin == "climate" then
    return { 0.75, 0.84, 0.95, 1 }
  elseif origin == "geologic" then
    return { 0.9, 0.57, 0.4, 1 }
  elseif origin == "biological" then
    return { 0.56, 0.86, 0.53, 1 }
  elseif origin == "chemical" then
    return { 0.94, 0.72, 0.36, 1 }
  elseif origin == "planetary" then
    return { 0.82, 0.84, 0.9, 1 }
  end
  return { 0.82, 0.84, 0.9, 1 }
end

local function origin_label(origin)
  local labels = {
    space = "Spaceborne",
    atmospheric = "Atmospheric",
    climate = "Climate",
    geologic = "Geologic",
    biological = "Biological",
    chemical = "Chemical",
    planetary = "Planetary"
  }
  return labels[origin] or "Hazard"
end

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

local function draw_wrapped_limited(text, x, y, width, color, max_lines)
  love.graphics.setColor(unpack(color or { 1, 1, 1, 1 }))
  local font = love.graphics.getFont()
  local _, wrapped = font:getWrap(text, width)
  local lines = wrapped
  local keep = max_lines or #lines
  if #lines > keep then
    local clipped = {}
    for i = 1, keep do
      clipped[i] = lines[i]
    end
    clipped[keep] = fit_single_line(clipped[keep], width)
    lines = clipped
  end

  local line_h = font:getHeight() + 2
  for i = 1, #lines do
    love.graphics.print(lines[i], x, y + ((i - 1) * line_h))
  end
  return y + (#lines * line_h)
end

function HazardCard.draw(opts)
  local rect = opts.rect
  local target = opts.target
  local show_target_vector = opts.show_target_vector ~= false
  local projection = opts.projection or {}
  local hazard = projection.hazard or {}
  local format_delta_list = opts.format_delta_list
  local magnetosphere_level = opts.magnetosphere_level or 1
  local magnetosphere_tier = opts.magnetosphere_tier or "Weak"
  local pulse = opts.pulse or 0

  local accent = origin_color(hazard.origin)
  local body_color = { 0.07, 0.09, 0.13, 0.95 }
  local border_color = { accent[1], accent[2], accent[3], 1 }
  local header_h = 28
  local text_x = rect.x + 8
  local text_w = rect.w - 16
  local art_h = math.max(52, math.floor(rect.h * 0.26))

  love.graphics.setColor(unpack(body_color))
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 8, 8)
  love.graphics.setColor(border_color[1], border_color[2], border_color[3], 0.88 + pulse * 0.12)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 8, 8)
  love.graphics.setLineWidth(1)

  love.graphics.setColor(accent[1], accent[2], accent[3], 0.86)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, header_h, 8, 8)
  love.graphics.setColor(0.03, 0.05, 0.08, 1)
  love.graphics.printf("INCOMING", rect.x + 4, rect.y + 8, rect.w - 8, "center")

  local line_y = rect.y + header_h + 7
  line_y = draw_wrapped_limited(fit_single_line(hazard.name or "Hazard", text_w), text_x, line_y, text_w, { 1, 1, 1, 1 }, 1)
  line_y = draw_wrapped_limited(
    fit_single_line((hazard.category or "Event") .. " | " .. origin_label(hazard.origin), text_w),
    text_x,
    line_y,
    text_w,
    { 0.76, 0.87, 0.95, 1 },
    1
  )
  line_y = line_y + 3

  local art_x = text_x
  local art_y = line_y
  local art_w = text_w
  love.graphics.setColor(0.09, 0.11, 0.16, 0.95)
  love.graphics.rectangle("fill", art_x, art_y, art_w, art_h, 6, 6)
  love.graphics.setColor(accent[1], accent[2], accent[3], 0.55)
  love.graphics.rectangle("line", art_x, art_y, art_w, art_h, 6, 6)

  love.graphics.setScissor(art_x + 1, art_y + 1, art_w - 2, art_h - 2)
  love.graphics.setLineWidth(2)
  if hazard.origin == "space" then
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.85)
    love.graphics.line(art_x + 10, art_y + art_h - 8, art_x + art_w - 18, art_y + 10)
    love.graphics.circle("fill", art_x + art_w - 22, art_y + 12, 5)
    love.graphics.setColor(1, 0.94, 0.74, 0.7)
    love.graphics.circle("fill", art_x + art_w - 22, art_y + 12, 3)
  elseif hazard.origin == "biological" then
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.85)
    love.graphics.circle("line", art_x + 24, art_y + 16, 8)
    love.graphics.circle("line", art_x + 40, art_y + 28, 10)
    love.graphics.circle("line", art_x + 58, art_y + 17, 7)
  else
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.8)
    for i = 0, 2 do
      local wave_y = art_y + 10 + (i * 10)
      love.graphics.line(art_x + 8, wave_y, art_x + art_w - 8, wave_y + 3 + (pulse * 2))
    end
  end
  love.graphics.setLineWidth(1)
  love.graphics.setScissor()
  line_y = line_y + art_h + 8

  line_y = draw_wrapped_limited("Raw: " .. format_delta_list(projection.raw_deltas), text_x, line_y, text_w, { 1, 1, 1, 1 }, 2)
  line_y = line_y + 1

  if hazard.magnetosphere_blockable then
    line_y = draw_wrapped_limited(
      "Magnetosphere: L" .. tostring(magnetosphere_level) .. " (" .. magnetosphere_tier .. ")",
      text_x,
      line_y,
      text_w,
      { 0.68, 0.87, 1, 1 },
      1
    )
    draw_wrapped_limited("Applied: " .. format_delta_list(projection.effective_deltas), text_x, line_y, text_w, { 0.86, 0.93, 1, 1 }, 2)
  else
    line_y = draw_wrapped_limited("Bypasses magnetosphere", text_x, line_y, text_w, { 0.9, 0.78, 0.42, 1 }, 1)
    draw_wrapped_limited("Applied: " .. format_delta_list(projection.effective_deltas), text_x, line_y, text_w, { 0.86, 0.93, 1, 1 }, 2)
  end

  if show_target_vector and target then
    local start_x = rect.x + rect.w + 8
    local start_y = rect.y + math.floor(rect.h * 0.5)
    local end_x = target.x - target.radius - 10
    local end_y = target.y
    local dx = end_x - start_x
    local dy = end_y - start_y
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0 then
      local ux = dx / length
      local uy = dy / length
      local arrow_len = 9
      local base_x = end_x - ux * 8
      local base_y = end_y - uy * 8
      local perp_x = -uy
      local perp_y = ux
      love.graphics.setColor(accent[1], accent[2], accent[3], 0.45 + pulse * 0.45)
      love.graphics.setLineWidth(2)
      love.graphics.line(start_x, start_y, end_x, end_y)
      love.graphics.polygon(
        "fill",
        end_x,
        end_y,
        base_x + perp_x * (arrow_len * 0.45),
        base_y + perp_y * (arrow_len * 0.45),
        base_x - perp_x * (arrow_len * 0.45),
        base_y - perp_y * (arrow_len * 0.45)
      )
      love.graphics.setLineWidth(1)
    end
  end
end

return HazardCard
