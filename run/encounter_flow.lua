local EncounterFlow = {}

EncounterFlow.states = {
  MAP = "map",
  ENCOUNTER = "encounter",
  REWARD = "reward",
  EVENT = "event",
  SHOP = "shop",
  BOSS = "boss"
}

function EncounterFlow.next_state(current_state, result)
  if current_state == EncounterFlow.states.MAP then
    return EncounterFlow.states.ENCOUNTER
  end

  if current_state == EncounterFlow.states.ENCOUNTER then
    if result == "won" then
      return EncounterFlow.states.REWARD
    end
    return EncounterFlow.states.MAP
  end

  if current_state == EncounterFlow.states.REWARD then
    return EncounterFlow.states.MAP
  end

  if current_state == EncounterFlow.states.EVENT then
    return EncounterFlow.states.MAP
  end

  if current_state == EncounterFlow.states.SHOP then
    return EncounterFlow.states.MAP
  end

  if current_state == EncounterFlow.states.BOSS then
    return EncounterFlow.states.REWARD
  end

  return EncounterFlow.states.MAP
end

return EncounterFlow
