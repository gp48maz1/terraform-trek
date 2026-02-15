local CardTypes = require("card_types")

local Cards = {}

Cards.by_id = CardTypes.Cards

function Cards.all_ids()
  return CardTypes.getAllCardIds()
end

function Cards.create(card_id)
  return CardTypes.createCardData(card_id)
end

function Cards.list()
  local entries = {}
  for card_id, definition in pairs(Cards.by_id) do
    entries[#entries + 1] = { id = card_id, card = definition }
  end
  table.sort(entries, function(a, b)
    return a.id < b.id
  end)
  return entries
end

return Cards
