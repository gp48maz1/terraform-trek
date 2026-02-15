local MagnetosphereSystem = require("systems.magnetosphere_system")

local HazardSystem = {}

local STAT_KEYS = { "heat", "air", "water", "soil" }

function HazardSystem.apply(hazard, magnetosphere_level, stats)
  local hazard_data = hazard or {}
  local deltas = hazard_data.deltas or {}
  local bypass = hazard_data.bypass_magnetosphere == true or hazard_data.magnetosphere_blockable == false
  local block_level = bypass and 0 or MagnetosphereSystem.normalize_level(magnetosphere_level)

  local effective = {}
  local blocked = {}
  local next_stats = {}

  for _, key in ipairs(STAT_KEYS) do
    local raw = deltas[key] or 0
    local value = raw
    local absorbed = 0
    if raw ~= 0 and block_level > 0 then
      value, absorbed = MagnetosphereSystem.block_delta(raw, block_level)
    end

    if value ~= 0 then
      effective[key] = value
    end
    if absorbed ~= 0 then
      blocked[key] = absorbed
    end

    local base_value = stats and stats[key] or 0
    next_stats[key] = base_value + value
  end

  return effective, blocked, {
    bypass_magnetosphere = bypass,
    block_level = block_level,
    next_stats = next_stats
  }
end

return HazardSystem
