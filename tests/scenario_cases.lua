local TerraformingState = require("terraforming_state")
local CardTypes = require("card_types")

local ScenarioCases = {}

local function is_array(tbl)
  if type(tbl) ~= "table" then
    return false
  end
  local count = 0
  for key, _ in pairs(tbl) do
    if type(key) ~= "number" then
      return false
    end
    count = count + 1
  end
  return count > 0
end

local function deep_copy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for k, v in pairs(value) do
    out[k] = deep_copy(v)
  end
  return out
end

local function merge_into(target, overrides)
  for key, value in pairs(overrides or {}) do
    if type(value) == "table" and not is_array(value) and type(target[key]) == "table" then
      merge_into(target[key], value)
    else
      target[key] = deep_copy(value)
    end
  end
end

local BASE_CONFIG = {
  name = "Spec World",
  goal = 20,
  turn_limit = 10,
  hazard_strength = 1,
  magnetosphere_level = 2,
  targets = { heat = 0, air = 0, water = 0, soil = 0 },
  starting_stats = { heat = -2, air = -5, water = -3, soil = -1 },
  hazards = {
    {
      id = "spec_micrometeor",
      name = "Micrometeor Swarm",
      category = "Orbital Debris",
      origin = "space",
      magnetosphere_blockable = true,
      deltas = { air = -1, soil = -1 }
    }
  }
}

function ScenarioCases.spec_config(overrides)
  local config = deep_copy(BASE_CONFIG)
  merge_into(config, overrides or {})
  return config
end

function ScenarioCases.new_state(overrides)
  return TerraformingState.new(ScenarioCases.spec_config(overrides))
end

function ScenarioCases.new_state_from_config(config)
  return TerraformingState.new(deep_copy(config))
end

function ScenarioCases.make_hand(card_ids)
  local hand = {}
  for _, card_id in ipairs(card_ids or {}) do
    hand[#hand + 1] = CardTypes.createCardData(card_id)
  end
  return hand
end

return ScenarioCases
