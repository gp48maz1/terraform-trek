local CardEffects = {}

--[[
This module contains functions that implement the specific effects of cards when played.
Each function will receive a 'context' table containing relevant game state information.
For now, context might include:
  - context.card: The card object being played.
  - context.target: The TerraformingTarget object.
  - context.deck: The player's Deck object.
  - context.player: (Future) A table representing the player state (e.g., buffs).
]]

-- Effect for cards like Basic Strike, Heavy Strike
function CardEffects.deal_damage(context)
  local card = context.card
  local target = context.target
  local damage = card.properties.damage or 0

  print("Applying effect: deal_damage")
  print("  Card: " .. card.name)
  print("  Damage: " .. damage)
  -- In the future, this would interact with the target object:
  -- target:take_damage(damage)
  -- print("  Target health remaining: " .. target.health)
end

-- Effect for cards like Basic Defend
function CardEffects.gain_block(context)
  local card = context.card
  -- local player = context.player -- We'll need a player object later
  local block_amount = card.properties.block_amount or 0

  print("Applying effect: gain_block")
  print("  Card: " .. card.name)
  print("  Block Amount: " .. block_amount)
  -- In the future, this would modify player state:
  -- player:add_block(block_amount)
  -- print("  Player block: " .. player.block)
end

-- Effect for cards like Draw Cards
function CardEffects.draw_cards(context)
  local card = context.card
  local deck = context.deck
  local draw_amount = card.properties.draw_amount or 0

  print("Applying effect: draw_cards")
  print("  Card: " .. card.name)
  print("  Draw Amount: " .. draw_amount)

  if deck and draw_amount > 0 then
    deck:draw(draw_amount)
  else
    print("  Warning: Could not draw cards (deck missing or draw_amount is zero).")
  end
end

-- Effect for cards like Gain Strength, Gain Dexterity
function CardEffects.apply_buff(context)
  local card = context.card
  -- local player = context.player -- Need player state
  local buff_type = card.properties.buff_type
  local buff_amount = card.properties.buff_amount or 0
  local duration = card.properties.duration -- Not used yet

  print("Applying effect: apply_buff")
  print("  Card: " .. card.name)
  print("  Buff Type: " .. tostring(buff_type))
  print("  Amount: " .. buff_amount)
  print("  Duration: " .. tostring(duration))
  -- In the future, modify player state:
  -- player:apply_buff(buff_type, buff_amount, duration)
end

return CardEffects 