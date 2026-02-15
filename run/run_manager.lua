local RunState = require("domain.run_state")
local EncounterFlow = require("run.encounter_flow")

local RunManager = {}
RunManager.__index = RunManager

function RunManager.new(config)
  return setmetatable({
    run_state = RunState.new(config),
    flow_state = EncounterFlow.states.MAP
  }, RunManager)
end

function RunManager:get_state()
  return self.run_state
end

function RunManager:get_flow_state()
  return self.flow_state
end

function RunManager:advance_flow(result)
  self.flow_state = EncounterFlow.next_state(self.flow_state, result)
  return self.flow_state
end

return RunManager
