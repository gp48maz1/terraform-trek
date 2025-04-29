local CardTypes = {}

-- Base card type definitions
CardTypes.BaseTypes = {
    ATTACK = {
        category = "Attack",
        base_properties = {
            damage = 0,
            energy_cost = 1
        }
    },
    SKILL = {
        category = "Skill",
        base_properties = {
            effect = "none",
            energy_cost = 1
        }
    },
    POWER = {
        category = "Power",
        base_properties = {
            duration = 1,
            energy_cost = 1
        }
    }
}

-- Specific card definitions
CardTypes.Cards = {
    -- Attack Cards
    Strike = {
        name = "Strike",
        description = "Deal 6 damage.",
        category = "Attack",
        cost = 1,
        properties = {
            damage = 6
        }
    },
    HeavyStrike = {
        name = "Heavy Strike",
        description = "Deal 10 damage. Costs 2 energy.",
        category = "Attack",
        cost = 2,
        properties = {
            damage = 10
        }
    },
    
    -- Skill Cards
    Defend = {
        name = "Defend",
        description = "Gain 5 block.",
        category = "Skill",
        cost = 1,
        properties = {
            effect = "block",
            block_amount = 5
        }
    },
    Draw = {
        name = "Draw",
        description = "Draw 2 cards.",
        category = "Skill",
        cost = 1,
        properties = {
            effect = "draw",
            draw_amount = 2
        }
    },
    
    -- Power Cards
    Strength = {
        name = "Strength",
        description = "Gain 2 strength for the rest of combat.",
        category = "Power",
        cost = 1,
        properties = {
            duration = -1, -- -1 means permanent
            effect = "strength",
            strength_amount = 2
        }
    },
    Dexterity = {
        name = "Dexterity",
        description = "Gain 2 dexterity for the rest of combat.",
        category = "Power",
        cost = 1,
        properties = {
            duration = -1,
            effect = "dexterity",
            dexterity_amount = 2
        }
    }
}

-- Function to create a card from a type definition
function CardTypes.createCard(cardType)
    local cardDef = CardTypes.Cards[cardType]
    if not cardDef then
        error("Invalid card type: " .. tostring(cardType))
    end
    
    -- Merge base properties with specific card properties
    local baseType = CardTypes.BaseTypes[cardDef.category]
    local properties = {}
    
    if baseType and baseType.base_properties then
        for k, v in pairs(baseType.base_properties) do
            properties[k] = v
        end
    end
    
    if cardDef.properties then
        for k, v in pairs(cardDef.properties) do
            properties[k] = v
        end
    end
    
    return {
        name = cardDef.name,
        description = cardDef.description,
        category = cardDef.category,
        cost = cardDef.cost,
        properties = properties
    }
end

-- Function to get all available card types
function CardTypes.getAllCardTypes()
    local types = {}
    for name, _ in pairs(CardTypes.Cards) do
        table.insert(types, name)
    end
    return types
end

return CardTypes 