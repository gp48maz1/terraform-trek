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

return CardLibraryLayout
