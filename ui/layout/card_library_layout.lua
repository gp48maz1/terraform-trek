local CardLibraryLayout = {}

function CardLibraryLayout.compute(safe_rect)
  local safe = safe_rect
  local left_w = math.floor(safe.w * 0.2)
  local gap = 16

  return {
    topics_rect = {
      x = safe.x,
      y = safe.y,
      w = left_w,
      h = safe.h
    },
    cards_rect = {
      x = safe.x + left_w + gap,
      y = safe.y,
      w = safe.w - left_w - gap,
      h = safe.h
    }
  }
end

function CardLibraryLayout.compute_for_window(window_w, window_h, topics, measure_text)
  local sw = window_w or 0
  local sh = window_h or 0
  local margin = 20
  local filter_y = 88
  local filter_h = 28
  local filter_gap = 8
  local x = margin
  local y = filter_y
  local measure = measure_text or function(text)
    return #(text or "")
  end
  local filter_rects = {}

  for _, topic in ipairs(topics or {}) do
    local w = math.max(84, measure(topic) + 22)
    if x + w > sw - margin then
      x = margin
      y = y + filter_h + filter_gap
    end
    table.insert(filter_rects, {
      topic = topic,
      x = x,
      y = y,
      w = w,
      h = filter_h
    })
    x = x + w + filter_gap
  end

  local filters_bottom = y + filter_h
  local content_top = filters_bottom + 12
  local detail_w = math.max(300, math.floor(sw * 0.29))
  local content_h = math.max(220, sh - content_top - 20)
  local grid_w = sw - (margin * 2) - detail_w - 12
  if grid_w < 380 then
    detail_w = math.max(260, math.floor(sw * 0.34))
    grid_w = sw - (margin * 2) - detail_w - 12
  end

  local grid_rect = {
    x = margin,
    y = content_top,
    w = grid_w,
    h = content_h
  }
  local detail_rect = {
    x = grid_rect.x + grid_rect.w + 12,
    y = content_top,
    w = detail_w,
    h = content_h
  }

  return {
    filter_rects = filter_rects,
    grid_rect = grid_rect,
    detail_rect = detail_rect
  }
end

function CardLibraryLayout.get_card_rects(grid_rect, filtered_entries, scroll_offset)
  local inner_pad = 10
  local card_w = 150
  local card_h = 225
  local gap_x = 14
  local gap_y = 16
  local usable_w = math.max(1, grid_rect.w - (inner_pad * 2))
  local cols = math.max(1, math.floor((usable_w + gap_x) / (card_w + gap_x)))
  local used_w = cols * card_w + (cols - 1) * gap_x
  local start_x = grid_rect.x + inner_pad + math.max(0, math.floor((usable_w - used_w) / 2))
  local start_y = grid_rect.y + inner_pad - (scroll_offset or 0)

  local rects = {}
  for i, entry in ipairs(filtered_entries or {}) do
    local row = math.floor((i - 1) / cols)
    local col = (i - 1) % cols
    local x = start_x + col * (card_w + gap_x)
    local y = start_y + row * (card_h + gap_y)
    table.insert(rects, {
      x = x,
      y = y,
      w = card_w,
      h = card_h,
      entry = entry
    })
  end

  local rows = math.ceil(#(filtered_entries or {}) / cols)
  local total_h = 0
  if rows > 0 then
    total_h = rows * card_h + (rows - 1) * gap_y
  end
  local max_scroll = math.max(0, total_h - (grid_rect.h - inner_pad * 2))
  return rects, max_scroll
end

return CardLibraryLayout
