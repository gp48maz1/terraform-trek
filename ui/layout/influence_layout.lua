local InfluenceLayout = {}

function InfluenceLayout.compute(safe_rect)
  local safe = safe_rect
  local top_h = math.floor(safe.h * 0.67)
  local graph_w = math.floor(safe.w * 0.54)
  local gap = 16

  local graph_rect = {
    x = safe.x,
    y = safe.y,
    w = graph_w,
    h = top_h
  }

  local objectives_rect = {
    x = graph_rect.x + graph_rect.w + gap,
    y = safe.y,
    w = safe.w - graph_rect.w - gap,
    h = top_h
  }

  local preview_rect = {
    x = safe.x,
    y = safe.y + top_h + gap,
    w = safe.w,
    h = safe.h - top_h - gap
  }

  return {
    graph_rect = graph_rect,
    objectives_rect = objectives_rect,
    preview_rect = preview_rect
  }
end

return InfluenceLayout
