local Worlds = {
  {
    name = "Dustbound Expanse",
    tier = "Low Threat",
    goal = 20,
    turn_limit = 10,
    hazard_strength = 1,
    magnetosphere_level = 3,
    targets = { heat = 0, air = 0, water = 0, soil = 0 },
    starting_ranges = {
      heat = { min = -4, max = 4 },
      air = { min = -6, max = -1 },
      water = { min = -4, max = 4 },
      soil = { min = -6, max = -1 }
    }
  },
  {
    name = "Iron Tempest",
    tier = "Elite",
    goal = 24,
    turn_limit = 10,
    hazard_strength = 1,
    magnetosphere_level = 2,
    targets = { heat = 0, air = 0, water = 0, soil = 0 },
    starting_ranges = {
      heat = { min = -6, max = 6 },
      air = { min = -8, max = -2 },
      water = { min = -6, max = 6 },
      soil = { min = -8, max = -2 }
    }
  },
  {
    name = "Abyssal Crown",
    tier = "Boss",
    goal = 28,
    turn_limit = 11,
    hazard_strength = 2,
    magnetosphere_level = 1,
    targets = { heat = 0, air = 0, water = 0, soil = 0 },
    starting_ranges = {
      heat = { min = -8, max = 8 },
      air = { min = -10, max = -3 },
      water = { min = -8, max = 8 },
      soil = { min = -10, max = -3 }
    }
  }
}

return Worlds
