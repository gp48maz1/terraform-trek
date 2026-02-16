local Defaults = {}

Defaults.STAT_KEYS = { "heat", "air", "water", "soil" }
Defaults.MIN_MAGNETOSPHERE_LEVEL = 1
Defaults.MAX_MAGNETOSPHERE_LEVEL = 4
Defaults.DEFAULT_MAGNETOSPHERE_LEVEL = 2

Defaults.DEFAULT_TARGETS = {
  heat = 0,
  air = 0,
  water = 0,
  soil = 0
}

Defaults.DEFAULT_STAT_BOUNDS = {
  heat = { min = -10, max = 10 },
  air = { min = -10, max = 0 },
  water = { min = -10, max = 10 },
  soil = { min = -10, max = 0 }
}

Defaults.DEFAULT_STARTING_RANGES = {
  heat = { min = -4, max = 4 },
  air = { min = -7, max = -1 },
  water = { min = -4, max = 4 },
  soil = { min = -7, max = -1 }
}

Defaults.DEFAULT_HAZARDS = {
  {
    id = "solar_flare",
    name = "Solar Flare",
    category = "Radiation Burst",
    origin = "space",
    magnetosphere_blockable = true,
    deltas = { heat = 2, air = 1 }
  },
  {
    id = "comet_crash_landing",
    name = "Comet Crash Landing",
    category = "Orbital Impact",
    origin = "space",
    magnetosphere_blockable = true,
    deltas = { soil = -2, water = 2 }
  },
  {
    id = "micrometeor_swarm",
    name = "Micrometeor Swarm",
    category = "Orbital Debris",
    origin = "space",
    magnetosphere_blockable = true,
    deltas = { air = -1, soil = -1 }
  },
  {
    id = "upper_atmos_leak",
    name = "Upper Atmos Leak",
    category = "Atmospheric Loss",
    origin = "atmospheric",
    magnetosphere_blockable = false,
    deltas = { air = -2, heat = -1 }
  },
  {
    id = "flash_freeze",
    name = "Flash Freeze",
    category = "Climate Shock",
    origin = "climate",
    magnetosphere_blockable = false,
    deltas = { heat = -2, water = -2 }
  },
  {
    id = "dust_storm",
    name = "Dust Storm",
    category = "Aeolian Event",
    origin = "climate",
    magnetosphere_blockable = false,
    deltas = { air = -1, soil = -2 }
  },
  {
    id = "acid_rain",
    name = "Acid Rain",
    category = "Chemical Event",
    origin = "chemical",
    magnetosphere_blockable = false,
    deltas = { water = 2, soil = -2 }
  },
  {
    id = "dry_front",
    name = "Dry Front",
    category = "Hydrologic Shift",
    origin = "climate",
    magnetosphere_blockable = false,
    deltas = { water = -2, soil = -1 }
  },
  {
    id = "volcanic_outgassing",
    name = "Volcanic Outgassing",
    category = "Geologic Surge",
    origin = "geologic",
    magnetosphere_blockable = false,
    deltas = { heat = 2, air = -1, soil = 1 }
  },
  {
    id = "spore_bloom",
    name = "Spore Bloom",
    category = "Biological Bloom",
    origin = "biological",
    magnetosphere_blockable = false,
    deltas = { soil = 2, air = 1 }
  }
}

Defaults.DEFAULT_INDUSTRY_SLOTS = 4
Defaults.COUPLING_EDGE_RULES = {
  { source = "heat", target = "water", factor = 1 },
  { source = "heat", target = "soil", factor = 1 },
  { source = "air", target = "heat", factor = 1 },
  { source = "air", target = "water", factor = 1 },
  { source = "water", target = "soil", factor = 1 },
  { source = "water", target = "air", factor = 1 },
  { source = "soil", target = "air", factor = 1 }
}

return Defaults
