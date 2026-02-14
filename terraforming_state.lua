local TerraformingState = {}
TerraformingState.__index = TerraformingState

local STAT_KEYS = { "heat", "air", "water", "soil" }

local DEFAULT_TARGETS = {
  heat = 0,
  air = 0,
  water = 0,
  soil = 0
}

local DEFAULT_HAZARDS = {
  { name = "Solar Flare", deltas = { heat = 1, air = 1 } },
  { name = "Upper Atmos Leak", deltas = { air = -2, heat = -1 } },
  { name = "Flash Freeze", deltas = { heat = -2, water = -1 } },
  { name = "Dust Storm", deltas = { air = -1, soil = -1 } },
  { name = "Melt Surge", deltas = { heat = 2, water = 1 } },
  { name = "Acid Rain", deltas = { water = 1, soil = -2 } },
  { name = "Spore Bloom", deltas = { soil = 2, air = 1 } },
  { name = "Dry Front", deltas = { water = -2, soil = -1 } }
}

local function shallow_copy(input)
  local out = {}
  for k, v in pairs(input or {}) do
    out[k] = v
  end
  return out
end

local function sign(value)
  if value > 0 then
    return 1
  end
  if value < 0 then
    return -1
  end
  return 0
end

local function clamp(value, min_value, max_value)
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
end

local function make_scaled_deltas(deltas, scale)
  local scaled = {}
  for key, value in pairs(deltas or {}) do
    scaled[key] = value * scale
  end
  return scaled
end

local function shuffle_in_place(items)
  for i = #items, 2, -1 do
    local j = love.math.random(i)
    items[i], items[j] = items[j], items[i]
  end
end

function TerraformingState.new(config)
  config = config or {}
  local self = setmetatable({}, TerraformingState)

  self.name = config.name or "Dustbound Expanse"
  self.tier = config.tier or "Normal World"
  self.min_stat = config.min_stat or -4
  self.max_stat = config.max_stat or 4
  self.goal = config.goal or 20
  self.turn_limit = config.turn_limit or 10
  self.hazard_strength = config.hazard_strength or 1
  self.target_band = config.target_band or 1
  self.strain_threshold = config.strain_threshold or 3
  self.critical_threshold = config.critical_threshold or 4
  self.coupling_threshold = config.coupling_threshold or 3
  self.turn = 1
  self.status = "ongoing"
  self.habitability = 0
  self.last_turn_summary = nil

  self.targets = shallow_copy(DEFAULT_TARGETS)
  for key, value in pairs(config.targets or {}) do
    self.targets[key] = clamp(value, self.min_stat, self.max_stat)
  end

  self.stats = shallow_copy(DEFAULT_TARGETS)
  for key, value in pairs(config.starting_stats or {}) do
    self.stats[key] = clamp(value, self.min_stat, self.max_stat)
  end

  if not config.starting_stats then
    for _, key in ipairs(STAT_KEYS) do
      self.stats[key] = love.math.random(-2, 2)
    end
  end

  self.hazards = {}
  local hazard_source = config.hazards or DEFAULT_HAZARDS
  for _, hazard in ipairs(hazard_source) do
    table.insert(self.hazards, {
      name = hazard.name,
      deltas = shallow_copy(hazard.deltas)
    })
  end
  shuffle_in_place(self.hazards)
  self.hazard_index = 1

  return self
end

function TerraformingState:stat_keys()
  return STAT_KEYS
end

function TerraformingState:get_next_hazard()
  return self.hazards[self.hazard_index]
end

function TerraformingState:advance_hazard()
  self.hazard_index = self.hazard_index + 1
  if self.hazard_index > #self.hazards then
    self.hazard_index = 1
    shuffle_in_place(self.hazards)
  end
end

function TerraformingState:apply_stat_changes(changes, bucket)
  local applied = {}
  for _, key in ipairs(STAT_KEYS) do
    local delta = (changes and changes[key]) or 0
    if delta ~= 0 then
      local before = self.stats[key]
      self.stats[key] = clamp(before + delta, self.min_stat, self.max_stat)
      local real_delta = self.stats[key] - before
      if real_delta ~= 0 then
        applied[key] = real_delta
      end
    end
  end

  if bucket then
    for key, delta in pairs(applied) do
      bucket[key] = (bucket[key] or 0) + delta
    end
  end

  return applied
end

function TerraformingState:apply_player_changes(changes)
  return self:apply_stat_changes(changes)
end

function TerraformingState:adjust_toward_targets(amount)
  local changes = {}
  local step = amount or 1
  for _, key in ipairs(STAT_KEYS) do
    local target = self.targets[key]
    local value = self.stats[key]
    if value < target then
      changes[key] = step
    elseif value > target then
      changes[key] = -step
    end
  end
  return self:apply_stat_changes(changes)
end

function TerraformingState:count_in_band()
  local in_band = 0
  local perfect = 0
  local strained = 0
  local critical = 0

  for _, key in ipairs(STAT_KEYS) do
    local distance = math.abs(self.stats[key] - self.targets[key])
    if distance <= self.target_band then
      in_band = in_band + 1
    end
    if distance == 0 then
      perfect = perfect + 1
    end
    if distance >= self.strain_threshold then
      strained = strained + 1
    end
    if distance >= self.critical_threshold then
      critical = critical + 1
    end
  end

  return in_band, perfect, strained, critical
end

function TerraformingState:build_coupling_changes(snapshot)
  local changes = {}

  local function apply_rule(source_key, target_key, factor)
    local source_value = snapshot[source_key] or 0
    if math.abs(source_value) >= self.coupling_threshold then
      local delta = sign(source_value) * factor
      changes[target_key] = (changes[target_key] or 0) + delta
    end
  end

  apply_rule("heat", "water", -1)
  apply_rule("heat", "soil", -1)
  apply_rule("air", "heat", 1)
  apply_rule("air", "water", 1)
  apply_rule("water", "soil", 1)
  apply_rule("water", "air", 1)
  apply_rule("soil", "air", 1)

  return changes
end

function TerraformingState:end_turn()
  if self.status ~= "ongoing" then
    return self.last_turn_summary
  end

  local summary = {
    turn = self.turn,
    hazard = nil,
    hazard_deltas = {},
    coupling_deltas = {},
    in_band = 0,
    perfect = 0,
    strained = 0,
    critical = 0,
    growth = 0,
    penalty = 0,
    net = 0
  }

  local hazard = self:get_next_hazard()
  summary.hazard = hazard.name
  local scaled = make_scaled_deltas(hazard.deltas, self.hazard_strength)
  self:apply_stat_changes(scaled, summary.hazard_deltas)
  self:advance_hazard()

  local snapshot = shallow_copy(self.stats)
  local coupling_changes = self:build_coupling_changes(snapshot)
  self:apply_stat_changes(coupling_changes, summary.coupling_deltas)

  local in_band, perfect, strained, critical = self:count_in_band()
  summary.in_band = in_band
  summary.perfect = perfect
  summary.strained = strained
  summary.critical = critical

  local growth = in_band
  if perfect == #STAT_KEYS then
    growth = growth + 2
  end
  local penalty = strained + critical
  local net = growth - penalty

  summary.growth = growth
  summary.penalty = penalty
  summary.net = net

  self.habitability = clamp(self.habitability + net, 0, self.goal)
  self.turn = self.turn + 1

  if self.habitability >= self.goal then
    self.status = "won"
  elseif self.turn > self.turn_limit then
    self.status = "lost"
  end

  self.last_turn_summary = summary
  return summary
end

return TerraformingState
