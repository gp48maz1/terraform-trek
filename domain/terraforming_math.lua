local TerraformingMath = {}

function TerraformingMath.shallow_copy(input)
  local out = {}
  for k, v in pairs(input or {}) do
    out[k] = v
  end
  return out
end

function TerraformingMath.normalize_hazard_entry(hazard, index)
  local item = hazard or {}
  local origin = item.origin
  local blockable = item.magnetosphere_blockable

  if blockable == nil then
    blockable = origin == "space"
  end
  if origin == nil then
    origin = blockable and "space" or "planetary"
  end

  local category = item.category
  if not category or category == "" then
    category = origin == "space" and "Orbital Event" or "Planetary Event"
  end

  return {
    id = item.id or ("hazard_" .. tostring(index or 0)),
    name = item.name or ("Hazard " .. tostring(index or 0)),
    category = category,
    origin = origin,
    magnetosphere_blockable = blockable and true or false,
    deltas = TerraformingMath.shallow_copy(item.deltas or {})
  }
end

function TerraformingMath.copy_damage_rules(rules)
  local out = {}
  for _, rule in ipairs(rules or {}) do
    table.insert(out, {
      stat = rule.stat,
      min = rule.min,
      max = rule.max,
      damage = rule.damage,
      reason = rule.reason
    })
  end
  return out
end

function TerraformingMath.sign(value)
  if value > 0 then
    return 1
  end
  if value < 0 then
    return -1
  end
  return 0
end

function TerraformingMath.get_coupling_signal_from_distance(distance)
  if distance <= 0 then
    return 3
  elseif distance <= 1 then
    return 2
  elseif distance <= 2 then
    return 1
  elseif distance <= 5 then
    return 0
  elseif distance >= 10 then
    return -5
  end

  local whole = math.floor(distance + 0.0001)
  return -(whole - 5)
end

function TerraformingMath.edge_key(source_key, target_key)
  return tostring(source_key) .. "->" .. tostring(target_key)
end

function TerraformingMath.get_edge_delta_from_signal(signal, factor)
  local strength = math.max(0, math.abs(factor or 1))
  if strength == 0 then
    return 0
  end
  return signal * strength
end

function TerraformingMath.format_signed(value)
  if value > 0 then
    return "+" .. tostring(value)
  end
  return tostring(value)
end

function TerraformingMath.clamp(value, min_value, max_value)
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
end

function TerraformingMath.make_scaled_deltas(deltas, scale)
  local scaled = {}
  for key, value in pairs(deltas or {}) do
    scaled[key] = value * scale
  end
  return scaled
end

function TerraformingMath.reduce_delta_by_block(delta, block_amount)
  if delta == 0 then
    return 0, 0
  end

  local magnitude = math.abs(delta)
  local reduced = math.max(0, magnitude - math.max(0, block_amount or 0))
  local direction = delta > 0 and 1 or -1
  local effective = direction * reduced
  local blocked = delta - effective
  return effective, blocked
end

function TerraformingMath.shuffle_in_place(items)
  for i = #items, 2, -1 do
    local j = love.math.random(i)
    items[i], items[j] = items[j], items[i]
  end
end

function TerraformingMath.damage_rule_triggers(rule, snapshot)
  local stat_value = (snapshot and snapshot[rule.stat]) or 0
  if rule.min and stat_value < rule.min then
    return false
  end
  if rule.max and stat_value > rule.max then
    return false
  end
  return true
end

return TerraformingMath
