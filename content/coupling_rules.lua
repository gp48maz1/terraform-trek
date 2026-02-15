local CouplingRules = {}

CouplingRules.stat_order = { "heat", "air", "water", "soil" }

CouplingRules.edges = {
  { source = "heat", target = "water", factor = 1, text = "Heat -> Water", curve = 0 },
  { source = "heat", target = "soil", factor = 1, text = "Heat -> Soil", curve = 68 },
  { source = "air", target = "heat", factor = 1, text = "Air -> Heat", curve = 0 },
  { source = "air", target = "water", factor = 1, text = "Air -> Water", curve = -72 },
  { source = "water", target = "soil", factor = 1, text = "Water -> Soil", curve = 0 },
  { source = "water", target = "air", factor = 1, text = "Water -> Air", curve = 72 },
  { source = "soil", target = "air", factor = 1, text = "Soil -> Air", curve = 0 }
}

CouplingRules.help = {
  heat = {
    summary = "Heat is bipolar: too low freezes systems, too high scorches systems.",
    incoming = "Air influences Heat continuously based on how close Air is to target.",
    outgoing = {
      "Heat can shift Water.",
      "Heat can shift Soil."
    }
  },
  air = {
    summary = "Air is one-directional health: very negative is toxic/thin, zero is ideal.",
    incoming = "Water and Soil influence Air continuously based on source quality.",
    outgoing = {
      "Air can shift Heat.",
      "Air can shift Water."
    }
  },
  water = {
    summary = "Water is bipolar: very negative means ice lock, very positive means steam lock.",
    incoming = "Heat and Air both influence Water continuously based on source quality.",
    outgoing = {
      "Water can shift Soil.",
      "Water can shift Air."
    }
  },
  soil = {
    summary = "Soil is one-directional health: very negative is sterile regolith, zero is ideal.",
    incoming = "Heat and Water influence Soil continuously based on source quality.",
    outgoing = {
      "Soil can shift Air."
    }
  }
}

return CouplingRules
