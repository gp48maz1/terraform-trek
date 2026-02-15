local MagnetosphereSystem = {}

local function clamp(value, min_value, max_value)
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
end

function MagnetosphereSystem.normalize_level(level)
  return clamp(math.floor(level or 1), 1, 4)
end

function MagnetosphereSystem.get_tier(level)
  local value = MagnetosphereSystem.normalize_level(level)
  if value >= 4 then
    return "Strong"
  end
  if value == 3 then
    return "Stable"
  end
  if value == 2 then
    return "Thin"
  end
  return "Weak"
end

function MagnetosphereSystem.block_delta(raw_delta, level)
  local value = raw_delta or 0
  if value == 0 then
    return 0, 0
  end

  local amount = MagnetosphereSystem.normalize_level(level)
  local direction = value > 0 and 1 or -1
  local magnitude = math.abs(value)
  local effective_magnitude = math.max(0, magnitude - amount)
  local effective = direction * effective_magnitude
  local blocked = value - effective
  return effective, blocked
end

return MagnetosphereSystem
