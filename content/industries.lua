local Industries = {
  {
    id = "hydroponics_array",
    name = "Hydroponics Array",
    slot_type = "general",
    base_income = 2,
    durability = 6,
    base_profit = 2,
    population_factor = 0.05,
    max_health = 6,
    damage_rules = {
      { stat = "heat", min = 6, damage = 1, reason = "heat stress" },
      { stat = "heat", max = -6, damage = 1, reason = "freeze stress" },
      { stat = "water", max = -7, damage = 1, reason = "ice lock" }
    }
  },
  {
    id = "regolith_mine",
    name = "Regolith Mine",
    slot_type = "general",
    base_income = 3,
    durability = 7,
    base_profit = 3,
    population_factor = 0,
    max_health = 7,
    damage_rules = {
      { stat = "water", min = 6, damage = 1, reason = "flooding" },
      { stat = "air", max = -8, damage = 1, reason = "air corrosion" },
      { stat = "soil", max = -8, damage = 1, reason = "substrate collapse" }
    }
  }
}

local by_id = {}
for _, entry in ipairs(Industries) do
  by_id[entry.id] = entry
end

return {
  all = Industries,
  by_id = by_id
}
