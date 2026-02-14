local CardTypes = {}

-- Base card type definitions
CardTypes.BaseTypes = {
    Terraform = {
        category = "Terraform",
        base_properties = {
            energy_cost = 1
        }
    },
    Chance = {
        category = "Chance",
        base_properties = {
            energy_cost = 1
        }
    },
    Power = {
        category = "Power",
        base_properties = {
            energy_cost = 1
        }
    }
}

-- Specific card definitions with IDs and effect function names.
CardTypes.Cards = {
    heat_up = {
        id = "heat_up",
        name = "Solar Mirrors",
        description = "Heat +2.",
        category = "Terraform",
        cost = 1,
        effect_fn_name = "apply_stat_changes",
        properties = {
            stat_changes = {
                heat = 2
            }
        }
    },
    heat_down = {
        id = "heat_down",
        name = "Orbital Shades",
        description = "Heat -2.",
        category = "Terraform",
        cost = 1,
        effect_fn_name = "apply_stat_changes",
        properties = {
            stat_changes = {
                heat = -2
            }
        }
    },
    air_up = {
        id = "air_up",
        name = "Atmo Seeding",
        description = "Air +2.",
        category = "Terraform",
        cost = 1,
        effect_fn_name = "apply_stat_changes",
        properties = {
            stat_changes = {
                air = 2
            }
        }
    },
    air_down = {
        id = "air_down",
        name = "Carbon Scrub",
        description = "Air -2.",
        category = "Terraform",
        cost = 1,
        effect_fn_name = "apply_stat_changes",
        properties = {
            stat_changes = {
                air = -2
            }
        }
    },
    water_up = {
        id = "water_up",
        name = "Comet Capture",
        description = "Water +2.",
        category = "Terraform",
        cost = 1,
        effect_fn_name = "apply_stat_changes",
        properties = {
            stat_changes = {
                water = 2
            }
        }
    },
    water_down = {
        id = "water_down",
        name = "Drain Basins",
        description = "Water -2.",
        category = "Terraform",
        cost = 1,
        effect_fn_name = "apply_stat_changes",
        properties = {
            stat_changes = {
                water = -2
            }
        }
    },
    soil_up = {
        id = "soil_up",
        name = "Nutrient Dust",
        description = "Soil +2.",
        category = "Terraform",
        cost = 1,
        effect_fn_name = "apply_stat_changes",
        properties = {
            stat_changes = {
                soil = 2
            }
        }
    },
    soil_down = {
        id = "soil_down",
        name = "Strip Mine",
        description = "Soil -2.",
        category = "Terraform",
        cost = 1,
        effect_fn_name = "apply_stat_changes",
        properties = {
            stat_changes = {
                soil = -2
            }
        }
    },
    stabilize = {
        id = "stabilize",
        name = "Stabilize Grid",
        description = "Move all stats 1 step toward target.",
        category = "Chance",
        cost = 1,
        effect_fn_name = "stabilize_system",
        properties = {}
    },
    survey = {
        id = "survey",
        name = "Deep Survey",
        description = "Draw 2 cards.",
        category = "Chance",
        cost = 1,
        effect_fn_name = "draw_cards",
        properties = {
            draw_amount = 2
        }
    }
}

function CardTypes.createCardData(cardId)
    local cardDef = CardTypes.Cards[cardId]
    if not cardDef then
        error("Invalid card ID: " .. tostring(cardId))
    end

    -- Start with the specific card definition
    local cardData = {
        id = cardDef.id,
        name = cardDef.name,
        description = cardDef.description,
        category = cardDef.category,
        cost = cardDef.cost,
        effect_fn_name = cardDef.effect_fn_name,
        properties = {}
    }

    local baseType = CardTypes.BaseTypes[cardDef.category]
    if baseType and baseType.base_properties then
        for k, v in pairs(baseType.base_properties) do
            if cardData.properties[k] == nil then
                 cardData.properties[k] = v
            end
        end
    end

    if cardDef.properties then
        for k, v in pairs(cardDef.properties) do
            cardData.properties[k] = v
        end
    end

    return cardData
end

function CardTypes.getAllCardIds()
    local ids = {}
    for id, _ in pairs(CardTypes.Cards) do
        table.insert(ids, id)
    end
    return ids
end

return CardTypes 
