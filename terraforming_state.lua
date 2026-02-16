local TerraformingState = {}
TerraformingState.__index = TerraformingState

local Defaults = require("domain.terraforming_defaults")
local TerraformingMath = require("domain.terraforming_math")

local STAT_KEYS = Defaults.STAT_KEYS
local MIN_MAGNETOSPHERE_LEVEL = Defaults.MIN_MAGNETOSPHERE_LEVEL
local MAX_MAGNETOSPHERE_LEVEL = Defaults.MAX_MAGNETOSPHERE_LEVEL
local DEFAULT_MAGNETOSPHERE_LEVEL = Defaults.DEFAULT_MAGNETOSPHERE_LEVEL
local DEFAULT_TARGETS = Defaults.DEFAULT_TARGETS
local DEFAULT_STAT_BOUNDS = Defaults.DEFAULT_STAT_BOUNDS
local DEFAULT_STARTING_RANGES = Defaults.DEFAULT_STARTING_RANGES
local DEFAULT_HAZARDS = Defaults.DEFAULT_HAZARDS
local DEFAULT_INDUSTRY_SLOTS = Defaults.DEFAULT_INDUSTRY_SLOTS
local COUPLING_EDGE_RULES = Defaults.COUPLING_EDGE_RULES

local shallow_copy = TerraformingMath.shallow_copy
local normalize_hazard_entry = TerraformingMath.normalize_hazard_entry
local copy_damage_rules = TerraformingMath.copy_damage_rules
local get_coupling_signal_from_distance = TerraformingMath.get_coupling_signal_from_distance
local edge_key = TerraformingMath.edge_key
local get_edge_delta_from_signal = TerraformingMath.get_edge_delta_from_signal
local format_signed = TerraformingMath.format_signed
local clamp = TerraformingMath.clamp
local make_scaled_deltas = TerraformingMath.make_scaled_deltas
local reduce_delta_by_block = TerraformingMath.reduce_delta_by_block
local shuffle_in_place = TerraformingMath.shuffle_in_place
local damage_rule_triggers = TerraformingMath.damage_rule_triggers

function TerraformingState.new(config)
  config = config or {}
  local self = setmetatable({}, TerraformingState)

  self.name = config.name or "Dustbound Expanse"
  self.tier = config.tier or "Normal World"
  self.goal = config.goal or 24
  self.turn_limit = config.turn_limit or 10
  self.hazard_strength = config.hazard_strength or 1
  self.magnetosphere_level = clamp(
    math.floor(config.magnetosphere_level or config.magnetosphere or DEFAULT_MAGNETOSPHERE_LEVEL),
    MIN_MAGNETOSPHERE_LEVEL,
    MAX_MAGNETOSPHERE_LEVEL
  )
  self.target_band = config.target_band or 1
  self.strain_threshold = config.strain_threshold or 4
  self.critical_threshold = config.critical_threshold or 7
  self.coupling_threshold = config.coupling_threshold or 4
  self.one_way_stress_threshold = config.one_way_stress_threshold or 6
  self.one_way_support_threshold = config.one_way_support_threshold or config.coupling_support_threshold or 3
  if self.one_way_stress_threshold <= self.one_way_support_threshold + 1 then
    self.one_way_stress_threshold = self.one_way_support_threshold + 2
  end
  self.population_good_threshold = config.population_good_threshold or 2
  self.population_ok_threshold = config.population_ok_threshold or 5
  if self.population_ok_threshold <= self.population_good_threshold then
    self.population_ok_threshold = self.population_good_threshold + 1
  end
  self.max_industry_slots = config.max_industry_slots or DEFAULT_INDUSTRY_SLOTS
  self.enforce_stat_bounds = config.enforce_stat_bounds == true
  self.cap_coupling_at_target = config.cap_coupling_at_target == true
  self.turn = 1
  self.status = "ongoing"
  self.habitability = 0
  self.population = math.max(0, config.population or 0)
  self.profit = math.max(0, config.profit or 0)
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
  for i, hazard in ipairs(hazard_source) do
    table.insert(self.hazards, normalize_hazard_entry(hazard, i))
  end
  if #self.hazards == 0 then
    table.insert(self.hazards, normalize_hazard_entry({
      id = "quiet_orbit",
      name = "Quiet Orbit",
      category = "No Immediate Threat",
      origin = "space",
      magnetosphere_blockable = true,
      deltas = {}
    }, 1))
  end
  shuffle_in_place(self.hazards)
  self.hazard_index = 1

  self.industries = {}
  for i = 1, self.max_industry_slots do
    self.industries[i] = nil
  end
  for i, industry in ipairs(config.industries or {}) do
    if i > self.max_industry_slots then
      break
    end
    self.industries[i] = self:create_industry_instance(industry)
  end

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

function TerraformingState:get_magnetosphere_level()
  return self.magnetosphere_level
end

function TerraformingState:get_magnetosphere_tier(level)
  local value = clamp(
    math.floor(level or self.magnetosphere_level or DEFAULT_MAGNETOSPHERE_LEVEL),
    MIN_MAGNETOSPHERE_LEVEL,
    MAX_MAGNETOSPHERE_LEVEL
  )
  if value >= 4 then
    return "Strong"
  elseif value == 3 then
    return "Stable"
  elseif value == 2 then
    return "Thin"
  end
  return "Weak"
end

function TerraformingState:project_hazard(hazard, hazard_strength, magnetosphere_level)
  local hazard_data = normalize_hazard_entry(hazard or self:get_next_hazard(), self.hazard_index)
  local strength = math.max(0, math.floor(hazard_strength or self.hazard_strength or 1))
  local level = clamp(
    math.floor(magnetosphere_level or self.magnetosphere_level or DEFAULT_MAGNETOSPHERE_LEVEL),
    MIN_MAGNETOSPHERE_LEVEL,
    MAX_MAGNETOSPHERE_LEVEL
  )

  local raw = make_scaled_deltas(hazard_data.deltas, strength)
  local effective = {}
  local blocked = {}
  local blocked_total = 0
  local has_raw = false
  local has_effective = false
  local block_amount = hazard_data.magnetosphere_blockable and level or 0

  for _, key in ipairs(STAT_KEYS) do
    local raw_delta = raw[key] or 0
    if raw_delta ~= 0 then
      has_raw = true
      local effective_delta = raw_delta
      local blocked_delta = 0
      if block_amount > 0 then
        effective_delta, blocked_delta = reduce_delta_by_block(raw_delta, block_amount)
      end
      if effective_delta ~= 0 then
        effective[key] = effective_delta
        has_effective = true
      end
      if blocked_delta ~= 0 then
        blocked[key] = blocked_delta
        blocked_total = blocked_total + math.abs(blocked_delta)
      end
    end
  end

  return {
    hazard = hazard_data,
    raw_deltas = raw,
    effective_deltas = effective,
    blocked_deltas = blocked,
    has_raw = has_raw,
    has_effective = has_effective,
    fully_blocked = has_raw and not has_effective and block_amount > 0,
    block_amount = block_amount,
    blocked_total = blocked_total
  }
end

function TerraformingState:preview_next_hazard(opts)
  opts = opts or {}
  return self:project_hazard(
    opts.hazard or self:get_next_hazard(),
    opts.hazard_strength or self.hazard_strength,
    opts.magnetosphere_level or self.magnetosphere_level
  )
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
      if self.enforce_stat_bounds then
        target_stats[key] = self:clamp_for_key(key, before + delta)
      else
        target_stats[key] = before + delta
      end
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

function TerraformingState:create_industry_instance(industry_def)
  local def = industry_def or {}
  local max_health = math.max(1, def.max_health or def.health or 5)
  local industry = {
    id = def.id or "industry",
    name = def.name or "Industry",
    base_profit = def.base_profit or 1,
    population_factor = def.population_factor or 0,
    max_health = max_health,
    health = clamp(def.health or max_health, 0, max_health),
    damage_rules = copy_damage_rules(def.damage_rules or {})
  }
  return industry
end

function TerraformingState:clone_industry(industry)
  if not industry then
    return nil
  end
  return {
    id = industry.id,
    name = industry.name,
    base_profit = industry.base_profit,
    population_factor = industry.population_factor,
    max_health = industry.max_health,
    health = industry.health,
    damage_rules = copy_damage_rules(industry.damage_rules or {})
  }
end

function TerraformingState:clone_industry_slots(source_slots)
  local slots = {}
  for i = 1, self.max_industry_slots do
    slots[i] = self:clone_industry(source_slots and source_slots[i] or nil)
  end
  return slots
end

function TerraformingState:get_industry_slot_count()
  return self.max_industry_slots
end

function TerraformingState:get_open_industry_slots_count(slots)
  local source = slots or self.industries
  local open = 0
  for i = 1, self.max_industry_slots do
    if not source[i] then
      open = open + 1
    end
  end
  return open
end

function TerraformingState:get_economy_snapshot()
  return {
    population = self.population,
    profit = self.profit,
    industries = self:clone_industry_slots(self.industries)
  }
end

function TerraformingState:install_industry_in_slots(industry_def, slots)
  if not industry_def then
    return false, nil
  end
  local target_slots = slots or self.industries
  for i = 1, self.max_industry_slots do
    if not target_slots[i] then
      target_slots[i] = self:create_industry_instance(industry_def)
      return true, i
    end
  end
  return false, nil
end

function TerraformingState:install_industry(industry_def)
  return self:install_industry_in_slots(industry_def, self.industries)
end

function TerraformingState:remove_industry(slot_index, slots)
  local target_slots = slots or self.industries
  if slot_index < 1 or slot_index > self.max_industry_slots then
    return false
  end
  if not target_slots[slot_index] then
    return false
  end
  target_slots[slot_index] = nil
  return true
end

function TerraformingState:replace_industry(slot_index, industry_def, slots)
  if not industry_def then
    return false
  end
  local target_slots = slots or self.industries
  if slot_index < 1 or slot_index > self.max_industry_slots then
    return false
  end
  target_slots[slot_index] = self:create_industry_instance(industry_def)
  return true
end

function TerraformingState:get_stat_quality(key, value)
  local target = self.targets[key] or 0
  local distance = math.abs((value or 0) - target)
  if distance <= self.population_good_threshold then
    return "good", 1
  elseif distance <= self.population_ok_threshold then
    return "ok", 0
  end
  return "bad", -1
end

function TerraformingState:compute_population_delta(snapshot)
  local quality = {}
  local primitive = 0
  local good_count = 0
  local base = 1

  for _, key in ipairs(STAT_KEYS) do
    local grade, score = self:get_stat_quality(key, snapshot[key])
    quality[key] = grade
    primitive = primitive + score
    if grade == "good" then
      good_count = good_count + 1
    end
  end

  local synergy = 0
  if good_count >= 2 then
    synergy = math.min(4, good_count)
  end

  local delta = base + primitive + synergy
  return delta, {
    base = base,
    primitive = primitive,
    synergy = synergy,
    good_count = good_count,
    quality = quality
  }
end

function TerraformingState:simulate_industry_phase(snapshot, population, slots)
  local profit_delta = 0
  local report = {}
  for i = 1, self.max_industry_slots do
    local industry = slots[i]
    if industry then
      local damage = 0
      local reasons = {}
      for _, rule in ipairs(industry.damage_rules or {}) do
        if damage_rule_triggers(rule, snapshot) then
          local rule_damage = rule.damage or 1
          damage = damage + rule_damage
          if rule.reason then
            table.insert(reasons, rule.reason)
          end
        end
      end

      local before_health = industry.health
      industry.health = clamp(industry.health - damage, 0, industry.max_health)
      local destroyed = industry.health <= 0
      local income = 0
      if not destroyed then
        local population_bonus = math.floor((population or 0) * (industry.population_factor or 0) + 0.5)
        income = (industry.base_profit or 0) + population_bonus
        profit_delta = profit_delta + income
      else
        slots[i] = nil
      end

      report[i] = {
        empty = false,
        name = industry.name,
        before_health = before_health,
        after_health = industry.health,
        damage = damage,
        income = income,
        destroyed = destroyed,
        reasons = reasons
      }
    else
      report[i] = { empty = true }
    end
  end
  return profit_delta, report
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
  local base_snapshot = snapshot or self.stats
  local changes, _ = self:compute_coupling(base_snapshot)
  if self.cap_coupling_at_target then
    changes = self:cap_coupling_changes_to_targets(base_snapshot, changes)
  end
  return changes
end

function TerraformingState:cap_coupling_changes_to_targets(snapshot, changes)
  local capped = {}
  local source = snapshot or self.stats

  for _, key in ipairs(STAT_KEYS) do
    local delta = (changes and changes[key]) or 0
    if delta ~= 0 then
      local value = source[key] or 0
      local target = self.targets[key] or 0
      local projected = value + delta
      if value < target and projected > target then
        delta = target - value
      elseif value > target and projected < target then
        delta = target - value
      end
      if delta ~= 0 then
        capped[key] = delta
      end
    end
  end

  return capped
end

function TerraformingState:compute_coupling(snapshot)
  local source_snapshot = snapshot or self.stats
  local changes = {}
  local edge_deltas = {}

  for _, rule in ipairs(COUPLING_EDGE_RULES) do
    local signal = self:get_source_coupling_signal(rule.source, source_snapshot)
    local applied = get_edge_delta_from_signal(signal, rule.factor)
    edge_deltas[edge_key(rule.source, rule.target)] = applied

    if applied ~= 0 then
      changes[rule.target] = (changes[rule.target] or 0) + applied
    end
  end

  return changes, edge_deltas
end

function TerraformingState:is_one_directional_stat(key)
  local bounds = self:get_stat_bounds(key)
  local target = self.targets[key] or 0
  return bounds.max <= target
end

function TerraformingState:get_source_coupling_signal(source_key, snapshot)
  local source_table = snapshot or self.stats
  local value = source_table[source_key] or 0
  local target = self.targets[source_key] or 0
  local delta_from_target = value - target
  local distance = math.abs(delta_from_target)
  return get_coupling_signal_from_distance(distance)
end

function TerraformingState:get_coupling_delta_for_edge(source_key, factor, snapshot, target_key)
  local signal = self:get_source_coupling_signal(source_key, snapshot)
  if target_key then
    local _, edge_deltas = self:compute_coupling(snapshot)
    local key = edge_key(source_key, target_key)
    if edge_deltas[key] ~= nil then
      return edge_deltas[key]
    end
  end
  return get_edge_delta_from_signal(signal, factor)
end

function TerraformingState:get_coupling_rules_summary()
  return "Source quality uses |value-target| bands for all primitives: 0=>+3, 1=>+2, 2=>+1, 3-5=>0, 6=>-1, 7=>-2, 8=>-3, 9=>-4, >=10=>-5."
end

function TerraformingState:get_coupling_rule_text(source_key)
  local target = self.targets[source_key] or 0
  return "Rule: |" .. source_key .. "-target| sets source signal (+3 to -5). Signal > 0 supports linked stats toward target " ..
    format_signed(target) .. "; signal < 0 stresses linked stats away from target. Per-edge effects are summed before final stat update."
end

function TerraformingState:forecast_end_turn(base_snapshot, opts)
  opts = opts or {}
  local start_snapshot = shallow_copy(base_snapshot or self.stats)
  local snapshot = shallow_copy(start_snapshot)
  local hazard = opts.hazard or self:get_next_hazard()
  local hazard_strength = opts.hazard_strength or self.hazard_strength
  local magnetosphere_level = opts.magnetosphere_level or self.magnetosphere_level
  local hazard_projection = self:project_hazard(hazard, hazard_strength, magnetosphere_level)
  local active_hazard = hazard_projection.hazard
  local source_economy = opts.economy_state or self:get_economy_snapshot()
  local economy = {
    population = math.max(0, source_economy.population or 0),
    profit = math.max(0, source_economy.profit or 0),
    industries = self:clone_industry_slots(source_economy.industries)
  }

  local summary = {
    hazard = active_hazard.name,
    hazard_id = active_hazard.id,
    hazard_category = active_hazard.category,
    hazard_origin = active_hazard.origin,
    hazard_blockable = active_hazard.magnetosphere_blockable and true or false,
    hazard_strength = hazard_strength,
    magnetosphere_level = clamp(
      math.floor(magnetosphere_level or DEFAULT_MAGNETOSPHERE_LEVEL),
      MIN_MAGNETOSPHERE_LEVEL,
      MAX_MAGNETOSPHERE_LEVEL
    ),
    hazard_block_amount = hazard_projection.block_amount or 0,
    hazard_raw_deltas = shallow_copy(hazard_projection.raw_deltas),
    hazard_effective_deltas = shallow_copy(hazard_projection.effective_deltas),
    hazard_blocked_deltas = shallow_copy(hazard_projection.blocked_deltas),
    hazard_fully_blocked = hazard_projection.fully_blocked and true or false,
    start_stats = shallow_copy(start_snapshot),
    post_hazard_stats = shallow_copy(start_snapshot),
    coupling_input_stats = shallow_copy(start_snapshot),
    coupling_edge_deltas = {},
    coupling_target_deltas_raw = {},
    coupling_target_deltas_applied = {},
    hazard_deltas = {},
    coupling_deltas = {},
    in_band = 0,
    perfect = 0,
    strained = 0,
    critical = 0,
    growth = 0,
    penalty = 0,
    net = 0,
    projected_stats = nil,
    population_before = economy.population,
    population_delta = 0,
    population_breakdown = nil,
    projected_population = economy.population,
    profit_before = economy.profit,
    profit_delta = 0,
    projected_profit = economy.profit,
    projected_industries = nil,
    industry_report = nil,
    open_industry_slots = 0
  }

  self:apply_stat_changes_to(hazard_projection.effective_deltas, snapshot, summary.hazard_deltas)
  summary.post_hazard_stats = shallow_copy(snapshot)
  summary.coupling_input_stats = shallow_copy(snapshot)

  local coupling_changes_raw, coupling_edge_deltas = self:compute_coupling(summary.coupling_input_stats)
  summary.coupling_edge_deltas = shallow_copy(coupling_edge_deltas)
  summary.coupling_target_deltas_raw = shallow_copy(coupling_changes_raw)

  local coupling_changes = shallow_copy(coupling_changes_raw)
  if self.cap_coupling_at_target then
    coupling_changes = self:cap_coupling_changes_to_targets(summary.coupling_input_stats, coupling_changes)
  end
  self:apply_stat_changes_to(coupling_changes, snapshot, summary.coupling_deltas)
  summary.coupling_target_deltas_applied = shallow_copy(summary.coupling_deltas)

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

  local population_delta, population_breakdown = self:compute_population_delta(snapshot)
  economy.population = math.max(0, economy.population + population_delta)
  summary.population_delta = population_delta
  summary.population_breakdown = population_breakdown
  summary.projected_population = economy.population

  local profit_delta, industry_report = self:simulate_industry_phase(snapshot, economy.population, economy.industries)
  economy.profit = math.max(0, economy.profit + profit_delta)
  summary.profit_delta = profit_delta
  summary.projected_profit = economy.profit
  summary.projected_industries = self:clone_industry_slots(economy.industries)
  summary.industry_report = industry_report
  summary.open_industry_slots = self:get_open_industry_slots_count(summary.projected_industries)

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
  self.population = summary.projected_population or self.population
  self.profit = summary.projected_profit or self.profit
  self.industries = self:clone_industry_slots(summary.projected_industries or self.industries)
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
