local TerraformingState = {}
TerraformingState.__index = TerraformingState

local STAT_KEYS = { "heat", "air", "water", "soil" }

local DEFAULT_TARGETS = {
  heat = 0,
  air = 0,
  water = 0,
  soil = 0
}

local DEFAULT_STAT_BOUNDS = {
  heat = { min = -10, max = 10 },
  air = { min = -10, max = 0 },
  water = { min = -10, max = 10 },
  soil = { min = -10, max = 0 }
}

local DEFAULT_STARTING_RANGES = {
  heat = { min = -4, max = 4 },
  air = { min = -7, max = -1 },
  water = { min = -4, max = 4 },
  soil = { min = -7, max = -1 }
}

local DEFAULT_HAZARDS = {
  { name = "Solar Flare", deltas = { heat = 2, air = 1 } },
  { name = "Upper Atmos Leak", deltas = { air = -2, heat = -1 } },
  { name = "Flash Freeze", deltas = { heat = -2, water = -2 } },
  { name = "Dust Storm", deltas = { air = -1, soil = -2 } },
  { name = "Melt Surge", deltas = { heat = 2, water = 1 } },
  { name = "Acid Rain", deltas = { water = 2, soil = -2 } },
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
  self.goal = config.goal or 24
  self.turn_limit = config.turn_limit or 10
  self.hazard_strength = config.hazard_strength or 1
  self.target_band = config.target_band or 1
  self.strain_threshold = config.strain_threshold or 4
  self.critical_threshold = config.critical_threshold or 7
  self.coupling_threshold = config.coupling_threshold or 3
  self.turn = 1
  self.status = "ongoing"
  self.habitability = 0
  self.last_turn_summary = nil

  self.stat_bounds = shallow_copy(DEFAULT_STAT_BOUNDS)
  for key, bound in pairs(config.stat_bounds or {}) do
    local fallback = DEFAULT_STAT_BOUNDS[key] or { min = -10, max = 10 }
    local min_value = bound.min or fallback.min
    local max_value = bound.max or fallback.max
    self.stat_bounds[key] = {
      min = math.min(min_value, max_value),
      max = math.max(min_value, max_value)
    }
  end

  self.starting_ranges = shallow_copy(DEFAULT_STARTING_RANGES)
  for key, range in pairs(config.starting_ranges or {}) do
    local bound = self.stat_bounds[key]
    local min_value = clamp(range.min or bound.min, bound.min, bound.max)
    local max_value = clamp(range.max or bound.max, bound.min, bound.max)
    self.starting_ranges[key] = {
      min = math.min(min_value, max_value),
      max = math.max(min_value, max_value)
    }
  end

  self.targets = shallow_copy(DEFAULT_TARGETS)
  for key, value in pairs(config.targets or {}) do
    self.targets[key] = self:clamp_for_key(key, value)
  end

  self.stats = shallow_copy(DEFAULT_TARGETS)
  for key, value in pairs(config.starting_stats or {}) do
    self.stats[key] = self:clamp_for_key(key, value)
  end

  if not config.starting_stats then
    for _, key in ipairs(STAT_KEYS) do
      local range = self.starting_ranges[key]
      self.stats[key] = love.math.random(range.min, range.max)
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

function TerraformingState:get_stat_bounds(key)
  local bounds = self.stat_bounds[key]
  if not bounds then
    return { min = -10, max = 10 }
  end
  return bounds
end

function TerraformingState:clamp_for_key(key, value)
  local bounds = self:get_stat_bounds(key)
  return clamp(value, bounds.min, bounds.max)
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

function TerraformingState:apply_stat_changes_to(changes, target_stats, bucket)
  local applied = {}
  for _, key in ipairs(STAT_KEYS) do
    local delta = (changes and changes[key]) or 0
    if delta ~= 0 then
      local before = target_stats[key]
      target_stats[key] = self:clamp_for_key(key, before + delta)
      local real_delta = target_stats[key] - before
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

function TerraformingState:apply_stat_changes(changes, bucket)
  return self:apply_stat_changes_to(changes, self.stats, bucket)
end

function TerraformingState:apply_player_changes(changes)
  return self:apply_stat_changes(changes)
end

function TerraformingState:adjust_snapshot_toward_targets(snapshot, amount)
  local step = amount or 1
  local changes = {}
  for _, key in ipairs(STAT_KEYS) do
    local target = self.targets[key]
    local value = snapshot[key]
    if value < target then
      changes[key] = step
    elseif value > target then
      changes[key] = -step
    end
  end
  self:apply_stat_changes_to(changes, snapshot)
  return changes
end

function TerraformingState:adjust_toward_targets(amount)
  return self:adjust_snapshot_toward_targets(self.stats, amount)
end

function TerraformingState:count_in_band_for(snapshot)
  local in_band = 0
  local perfect = 0
  local strained = 0
  local critical = 0

  for _, key in ipairs(STAT_KEYS) do
    local distance = math.abs(snapshot[key] - self.targets[key])
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

function TerraformingState:count_in_band()
  return self:count_in_band_for(self.stats)
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

function TerraformingState:forecast_end_turn(base_snapshot, opts)
  opts = opts or {}
  local start_snapshot = base_snapshot or self.stats
  local snapshot = shallow_copy(start_snapshot)
  local hazard = opts.hazard or self:get_next_hazard()
  local hazard_strength = opts.hazard_strength or self.hazard_strength

  local summary = {
    hazard = hazard.name,
    hazard_deltas = {},
    coupling_deltas = {},
    in_band = 0,
    perfect = 0,
    strained = 0,
    critical = 0,
    growth = 0,
    penalty = 0,
    net = 0,
    projected_stats = nil
  }

  local scaled = make_scaled_deltas(hazard.deltas, hazard_strength)
  self:apply_stat_changes_to(scaled, snapshot, summary.hazard_deltas)

  local coupling_changes = self:build_coupling_changes(shallow_copy(snapshot))
  self:apply_stat_changes_to(coupling_changes, snapshot, summary.coupling_deltas)

  local in_band, perfect, strained, critical = self:count_in_band_for(snapshot)
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
  summary.projected_stats = snapshot

  return summary
end

function TerraformingState:end_turn()
  if self.status ~= "ongoing" then
    return self.last_turn_summary
  end

  local summary = self:forecast_end_turn(self.stats)
  summary.turn = self.turn
  self.stats = shallow_copy(summary.projected_stats)
  self.habitability = clamp(self.habitability + summary.net, 0, self.goal)
  self.turn = self.turn + 1
  self:advance_hazard()

  if self.habitability >= self.goal then
    self.status = "won"
  elseif self.turn > self.turn_limit then
    self.status = "lost"
  end

  self.last_turn_summary = summary
  return summary
end

return TerraformingState
