local Hazards = {
  {
    id = "solar_flare",
    name = "Solar Flare",
    category = "Radiation Burst",
    origin = "space",
    tags = { "space", "radiation" },
    bypass_magnetosphere = false,
    intensity = 1,
    deltas = { heat = 2, air = 1 }
  },
  {
    id = "comet_crash_landing",
    name = "Comet Crash Landing",
    category = "Orbital Impact",
    origin = "space",
    tags = { "space", "impact" },
    bypass_magnetosphere = false,
    intensity = 2,
    deltas = { soil = -2, water = 2 }
  },
  {
    id = "micrometeor_swarm",
    name = "Micrometeor Swarm",
    category = "Orbital Debris",
    origin = "space",
    tags = { "space", "debris" },
    bypass_magnetosphere = false,
    intensity = 1,
    deltas = { air = -1, soil = -1 }
  },
  {
    id = "upper_atmos_leak",
    name = "Upper Atmos Leak",
    category = "Atmospheric Loss",
    origin = "atmospheric",
    tags = { "atmospheric" },
    bypass_magnetosphere = true,
    intensity = 2,
    deltas = { air = -2, heat = -1 }
  },
  {
    id = "flash_freeze",
    name = "Flash Freeze",
    category = "Climate Shock",
    origin = "climate",
    tags = { "climate" },
    bypass_magnetosphere = true,
    intensity = 2,
    deltas = { heat = -2, water = -2 }
  },
  {
    id = "dust_storm",
    name = "Dust Storm",
    category = "Aeolian Event",
    origin = "climate",
    tags = { "climate" },
    bypass_magnetosphere = true,
    intensity = 2,
    deltas = { air = -1, soil = -2 }
  },
  {
    id = "acid_rain",
    name = "Acid Rain",
    category = "Chemical Event",
    origin = "chemical",
    tags = { "chemical" },
    bypass_magnetosphere = true,
    intensity = 2,
    deltas = { water = 2, soil = -2 }
  },
  {
    id = "dry_front",
    name = "Dry Front",
    category = "Hydrologic Shift",
    origin = "climate",
    tags = { "climate", "hydrologic" },
    bypass_magnetosphere = true,
    intensity = 2,
    deltas = { water = -2, soil = -1 }
  },
  {
    id = "volcanic_outgassing",
    name = "Volcanic Outgassing",
    category = "Geologic Surge",
    origin = "geologic",
    tags = { "geologic" },
    bypass_magnetosphere = true,
    intensity = 2,
    deltas = { heat = 2, air = -1, soil = 1 }
  },
  {
    id = "spore_bloom",
    name = "Spore Bloom",
    category = "Biological Bloom",
    origin = "biological",
    tags = { "biological" },
    bypass_magnetosphere = true,
    intensity = 1,
    deltas = { soil = 2, air = 1 }
  }
}

return Hazards
