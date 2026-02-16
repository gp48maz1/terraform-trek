local Background = require("background")

local CardLibraryLayout = require("ui.layout.card_library_layout")
local CardLibraryState = require("app.card_library_state")

local RuntimeCardLibrary = {}
RuntimeCardLibrary.__index = RuntimeCardLibrary

function RuntimeCardLibrary.new(ctx)
  return setmetatable({ ctx = ctx }, RuntimeCardLibrary)
end

function RuntimeCardLibrary:get_filtered_entries()
  return CardLibraryState.get_filtered_entries(self.ctx.card_library_state)
end

function RuntimeCardLibrary:ensure_selection(filtered)
  CardLibraryState.ensure_selection(self.ctx.card_library_state, filtered)
end

function RuntimeCardLibrary:get_layout()
  local sw, sh = love.graphics.getDimensions()
  local font = love.graphics.getFont()
  return CardLibraryLayout.compute_for_window(sw, sh, self.ctx.card_library_state.topics, function(text)
    return font:getWidth(text)
  end)
end

function RuntimeCardLibrary:get_card_rects(layout, filtered_entries)
  return CardLibraryLayout.get_card_rects(layout.grid_rect, filtered_entries, self.ctx.card_library_state.scroll_offset)
end

function RuntimeCardLibrary:get_selected_entry(filtered_entries)
  return CardLibraryState.get_selected_entry(self.ctx.card_library_state, filtered_entries)
end

function RuntimeCardLibrary:update_hover_state()
  local mx, my = love.mouse.getPosition()
  local layout = self:get_layout()
  local filtered_entries = self:get_filtered_entries()
  self:ensure_selection(filtered_entries)
  local card_rects, max_scroll = self:get_card_rects(layout, filtered_entries)
  CardLibraryState.set_max_scroll(self.ctx.card_library_state, max_scroll)
  CardLibraryState.reset_hover(self.ctx.card_library_state)

  for _, filter_rect in ipairs(layout.filter_rects) do
    if self.ctx:point_in_rect(mx, my, filter_rect.x, filter_rect.y, filter_rect.w, filter_rect.h) then
      self.ctx.card_library_state.hovered_topic = filter_rect.topic
      break
    end
  end

  local grid_rect = layout.grid_rect
  for _, rect in ipairs(card_rects) do
    local visible = rect.y + rect.h >= grid_rect.y and rect.y <= grid_rect.y + grid_rect.h
    if visible and self.ctx:point_in_rect(mx, my, rect.x, rect.y, rect.w, rect.h) then
      self.ctx.card_library_state.hovered_card_id = rect.entry.id
      break
    end
  end
end

function RuntimeCardLibrary:draw_screen()
  local layout = self:get_layout()
  local filtered_entries = self:get_filtered_entries()
  self:ensure_selection(filtered_entries)
  local card_rects, max_scroll = self:get_card_rects(layout, filtered_entries)
  CardLibraryState.set_max_scroll(self.ctx.card_library_state, max_scroll)
  local selected_entry = self:get_selected_entry(filtered_entries)

  Background.draw_fill()
  Background.draw_stars()

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("Card Library", 16, 12)
  love.graphics.print("Browse all cards or filter by topic. Click a card to inspect details.", 16, 32)
  love.graphics.print("Filters + mouse wheel. Press ESC to quit this mode.", 16, 52)

  for _, filter_rect in ipairs(layout.filter_rects) do
    local active = self.ctx.card_library_state.selected_topic == filter_rect.topic
    local hovered = self.ctx.card_library_state.hovered_topic == filter_rect.topic
    local fill = active and { 0.24, 0.42, 0.26, 0.98 } or { 0.13, 0.18, 0.25, 0.98 }
    local border = active and { 0.65, 0.95, 0.64, 1 } or { 0.62, 0.78, 0.95, 1 }
    if hovered and not active then
      fill = { 0.18, 0.24, 0.33, 0.98 }
    end
    love.graphics.setColor(unpack(fill))
    love.graphics.rectangle("fill", filter_rect.x, filter_rect.y, filter_rect.w, filter_rect.h, 7, 7)
    love.graphics.setColor(unpack(border))
    love.graphics.rectangle("line", filter_rect.x, filter_rect.y, filter_rect.w, filter_rect.h, 7, 7)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(filter_rect.topic, filter_rect.x + 4, filter_rect.y + 6, filter_rect.w - 8, "center")
  end

  local grid_rect = layout.grid_rect
  love.graphics.setColor(0.06, 0.08, 0.12, 0.95)
  love.graphics.rectangle("fill", grid_rect.x, grid_rect.y, grid_rect.w, grid_rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", grid_rect.x, grid_rect.y, grid_rect.w, grid_rect.h, 10, 10)
  love.graphics.setColor(0.75, 0.87, 0.95, 1)
  love.graphics.printf(
    "Cards: " .. tostring(#filtered_entries) .. "/" .. tostring(#self.ctx.card_library_state.cards) .. "  |  Topic: " .. self.ctx.card_library_state.selected_topic,
    grid_rect.x + 10,
    grid_rect.y + 8,
    grid_rect.w - 20,
    "left"
  )

  local scissor_y = grid_rect.y + 28
  local scissor_h = grid_rect.h - 36
  love.graphics.setScissor(grid_rect.x + 2, scissor_y, grid_rect.w - 4, scissor_h)
  for _, rect in ipairs(card_rects) do
    local visible = rect.y + rect.h >= scissor_y and rect.y <= scissor_y + scissor_h
    if visible then
      rect.entry.card:draw(rect.x, rect.y)
      local selected = self.ctx.card_library_state.selected_card_id == rect.entry.id
      local hovered = self.ctx.card_library_state.hovered_card_id == rect.entry.id
      if selected or hovered then
        local color = selected and { 0.64, 0.94, 0.63, 1 } or { 0.7, 0.82, 0.98, 1 }
        love.graphics.setColor(unpack(color))
        love.graphics.setLineWidth(selected and 3 or 2)
        love.graphics.rectangle("line", rect.x - 3, rect.y - 3, rect.w + 6, rect.h + 6, 6, 6)
        love.graphics.setLineWidth(1)
      end
    end
  end
  love.graphics.setScissor()

  if self.ctx.card_library_state.max_scroll > 0 then
    local track_x = grid_rect.x + grid_rect.w - 8
    local track_y = scissor_y + 4
    local track_h = scissor_h - 8
    local thumb_h = math.max(30, math.floor(track_h * (scissor_h / (scissor_h + self.ctx.card_library_state.max_scroll))))
    local thumb_t = self.ctx.card_library_state.scroll_offset / self.ctx.card_library_state.max_scroll
    local thumb_y = track_y + math.floor((track_h - thumb_h) * thumb_t)
    love.graphics.setColor(0.16, 0.22, 0.3, 0.95)
    love.graphics.rectangle("fill", track_x, track_y, 4, track_h, 3, 3)
    love.graphics.setColor(0.65, 0.78, 0.95, 0.95)
    love.graphics.rectangle("fill", track_x, thumb_y, 4, thumb_h, 3, 3)
  end

  local detail_rect = layout.detail_rect
  love.graphics.setColor(0.06, 0.08, 0.12, 0.95)
  love.graphics.rectangle("fill", detail_rect.x, detail_rect.y, detail_rect.w, detail_rect.h, 10, 10)
  love.graphics.setColor(0.72, 0.82, 0.96, 1)
  love.graphics.rectangle("line", detail_rect.x, detail_rect.y, detail_rect.w, detail_rect.h, 10, 10)

  local text_x = detail_rect.x + 12
  local text_w = detail_rect.w - 24
  local y = detail_rect.y + 12

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf("Card Detail", text_x, y, text_w, "left")
  y = y + 22

  if not selected_entry then
    love.graphics.setColor(0.75, 0.87, 0.95, 1)
    love.graphics.printf("No cards match this filter.", text_x, y, text_w, "left")
    return
  end

  local data = selected_entry.data
  local topic_list = {}
  for topic, _ in pairs(selected_entry.topics) do
    table.insert(topic_list, topic)
  end
  table.sort(topic_list)

  y = self.ctx:draw_wrapped_line(data.name .. "  (Cost " .. tostring(data.cost or 0) .. ")", text_x, y, text_w, { 1, 1, 1, 1 }, 16)
  y = self.ctx:draw_wrapped_line("Category: " .. tostring(data.category), text_x, y + 2, text_w, { 0.75, 0.87, 0.95, 1 }, 16)
  y = self.ctx:draw_wrapped_line("ID: " .. tostring(data.id), text_x, y, text_w, { 0.75, 0.87, 0.95, 1 }, 16)
  y = self.ctx:draw_wrapped_line("Topics: " .. table.concat(topic_list, ", "), text_x, y, text_w, { 0.75, 0.87, 0.95, 1 }, 16)
  y = self.ctx:draw_wrapped_line("Description: " .. tostring(data.description), text_x, y + 6, text_w, { 1, 1, 1, 1 }, 16)
  y = self.ctx:draw_wrapped_line("Effect: " .. tostring(data.effect_fn_name), text_x, y + 6, text_w, { 0.75, 0.87, 0.95, 1 }, 16)

  local properties = data.properties or {}
  if properties.stat_changes then
    local change_parts = {}
    for _, key in ipairs(self.ctx.STAT_ORDER) do
      local delta = properties.stat_changes[key]
      if delta and delta ~= 0 then
        table.insert(change_parts, (self.ctx.STAT_LABELS[key] or key) .. " " .. self.ctx:format_signed(delta))
      end
    end
    if #change_parts > 0 then
      y = self.ctx:draw_wrapped_line("Stat changes: " .. table.concat(change_parts, ", "), text_x, y, text_w, { 1, 1, 1, 1 }, 16)
    end
  end

  if properties.draw_amount then
    y = self.ctx:draw_wrapped_line("Draw amount: " .. tostring(properties.draw_amount), text_x, y, text_w, { 1, 1, 1, 1 }, 16)
  end

  if properties.industry_def then
    local industry = properties.industry_def
    y = self.ctx:draw_wrapped_line(
      "Industry: base " .. tostring(industry.base_profit or 0) ..
        ", pop factor " .. tostring(industry.population_factor or 0) ..
        ", HP " .. tostring(industry.max_health or industry.health or 0),
      text_x,
      y + 4,
      text_w,
      { 1, 1, 1, 1 },
      16
    )
    if industry.damage_rules and #industry.damage_rules > 0 then
      y = self.ctx:draw_wrapped_line("Damage rules:", text_x, y + 2, text_w, { 0.75, 0.87, 0.95, 1 }, 16)
      for _, rule in ipairs(industry.damage_rules) do
        local stat_label = self.ctx.STAT_LABELS[rule.stat] or tostring(rule.stat)
        local conditions = {}
        if rule.min ~= nil then
          table.insert(conditions, stat_label .. " >= " .. tostring(rule.min))
        end
        if rule.max ~= nil then
          table.insert(conditions, stat_label .. " <= " .. tostring(rule.max))
        end
        local cond_text = table.concat(conditions, " and ")
        local rule_text = "- " .. cond_text .. ": -" .. tostring(rule.damage or 1) .. " HP"
        if rule.reason and rule.reason ~= "" then
          rule_text = rule_text .. " (" .. rule.reason .. ")"
        end
        y = self.ctx:draw_wrapped_line(rule_text, text_x, y, text_w, { 1, 1, 1, 1 }, 16)
        if y > detail_rect.y + detail_rect.h - 20 then
          break
        end
      end
    end
  end
end

function RuntimeCardLibrary:handle_mousepressed(x, y)
  local layout = self:get_layout()
  local filtered_entries = self:get_filtered_entries()
  self:ensure_selection(filtered_entries)
  local card_rects, max_scroll = self:get_card_rects(layout, filtered_entries)
  CardLibraryState.set_max_scroll(self.ctx.card_library_state, max_scroll)

  for _, filter_rect in ipairs(layout.filter_rects) do
    if self.ctx:point_in_rect(x, y, filter_rect.x, filter_rect.y, filter_rect.w, filter_rect.h) then
      CardLibraryState.select_topic(self.ctx.card_library_state, filter_rect.topic)
      local refreshed = self:get_filtered_entries()
      self:ensure_selection(refreshed)
      return
    end
  end

  local grid_rect = layout.grid_rect
  for _, rect in ipairs(card_rects) do
    local visible = rect.y + rect.h >= grid_rect.y and rect.y <= grid_rect.y + grid_rect.h
    if visible and self.ctx:point_in_rect(x, y, rect.x, rect.y, rect.w, rect.h) then
      CardLibraryState.select_card(self.ctx.card_library_state, rect.entry.id)
      return
    end
  end
end

function RuntimeCardLibrary:handle_wheel(y)
  CardLibraryState.scroll_by(self.ctx.card_library_state, y, 44)
end

function RuntimeCardLibrary:handle_keypressed(key)
  if key == "escape" then
    love.event.quit()
    return
  end

  if key == "up" then
    self:handle_wheel(1)
    return
  elseif key == "down" then
    self:handle_wheel(-1)
    return
  end

  if key == "left" then
    CardLibraryState.cycle_topic(self.ctx.card_library_state, -1)
    local filtered = self:get_filtered_entries()
    self:ensure_selection(filtered)
    return
  elseif key == "right" then
    CardLibraryState.cycle_topic(self.ctx.card_library_state, 1)
    local filtered = self:get_filtered_entries()
    self:ensure_selection(filtered)
    return
  end
end

function RuntimeCardLibrary:update(_dt)
  self.ctx:update_viewport_from_graphics()
  self:update_hover_state()
end

function RuntimeCardLibrary:draw()
  self:draw_screen()
end

function RuntimeCardLibrary:keypressed(key)
  self:handle_keypressed(key)
end

function RuntimeCardLibrary:mousepressed(x, y, button)
  if button ~= 1 then
    return
  end
  self:handle_mousepressed(x, y)
end

function RuntimeCardLibrary:wheelmoved(_, y)
  self:handle_wheel(y)
end

return RuntimeCardLibrary
