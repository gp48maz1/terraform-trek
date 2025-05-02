local CardTypes = {}

-- Base card type definitions (Renamed categories)
CardTypes.BaseTypes = {
    TERRAFORM = {
        category = "Terraform",
        base_properties = {
            -- Define base terraform properties if any, e.g., target_type?
            energy_cost = 1
        }
    },
    CHANCE = {
        category = "Chance",
        base_properties = {
            -- Define base chance properties if any
            energy_cost = 1
        }
    },
    POWER = { -- Keeping Power for now, can remove later if not needed
        category = "Power",
        base_properties = {
            duration = 1,
            energy_cost = 1
        }
    }
}

-- Specific card definitions with IDs and effect function names
CardTypes.Cards = {
    -- Terraform Cards (Previously Attack)
    basic_strike = { -- Using snake_case for IDs
        id = "basic_strike",
        name = "Basic Strike",
        description = "Deal 6 damage to the target.",
        category = "Terraform", -- Renamed
        cost = 1,
        effect_fn_name = "deal_damage", -- Effect function name
        properties = {
            damage = 6
        }
    },
    heavy_strike = {
        id = "heavy_strike",
        name = "Heavy Strike",
        description = "Deal 10 damage. Costs 2 energy.",
        category = "Terraform", -- Renamed
        cost = 2,
        effect_fn_name = "deal_damage", -- Same effect, different parameters
        properties = {
            damage = 10
        }
    },

    -- Chance Cards (Previously Skill)
    basic_defend = {
        id = "basic_defend",
        name = "Basic Defend",
        description = "Gain 5 block.", -- Need to define what "block" means
        category = "Chance", -- Renamed
        cost = 1,
        effect_fn_name = "gain_block", -- Effect function name
        properties = {
            block_amount = 5
        }
    },
    draw_cards = {
        id = "draw_cards",
        name = "Draw Cards",
        description = "Draw 2 cards.",
        category = "Chance", -- Renamed
        cost = 1,
        effect_fn_name = "draw_cards", -- Effect function name
        properties = {
            draw_amount = 2
        }
    },

    -- Power Cards (Keep or modify as needed)
    gain_strength = {
        id = "gain_strength",
        name = "Gain Strength",
        description = "Gain 2 strength for the rest of combat.", -- Define "strength"
        category = "Power",
        cost = 1,
        effect_fn_name = "apply_buff", -- Generic buff function?
        properties = {
            duration = -1, -- -1 means permanent
            buff_type = "strength",
            buff_amount = 2
        }
    },
    gain_dexterity = {
        id = "gain_dexterity",
        name = "Gain Dexterity",
        description = "Gain 2 dexterity for the rest of combat.", -- Define "dexterity"
        category = "Power",
        cost = 1,
        effect_fn_name = "apply_buff",
        properties = {
            duration = -1,
            buff_type = "dexterity",
            buff_amount = 2
        }
    }
}

-- Function to create card data from a type definition (ID)
function CardTypes.createCardData(cardId) -- Renamed function for clarity
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
        effect_fn_name = cardDef.effect_fn_name, -- Include effect function name
        properties = {}
    }

    -- Merge base properties (if category exists in BaseTypes)
    local baseType = CardTypes.BaseTypes[cardDef.category]
    if baseType and baseType.base_properties then
        for k, v in pairs(baseType.base_properties) do
            -- Only add base property if not already defined in specific card
            if cardData.properties[k] == nil then
                 cardData.properties[k] = v
            end
        end
    end

    -- Merge specific card properties (overwriting base properties if needed)
    if cardDef.properties then
        for k, v in pairs(cardDef.properties) do
            cardData.properties[k] = v
        end
    end

    return cardData
end

-- Function to get all available card IDs
function CardTypes.getAllCardIds() -- Renamed function for clarity
    local ids = {}
    for id, _ in pairs(CardTypes.Cards) do
        table.insert(ids, id)
    end
    return ids
end

return CardTypes 