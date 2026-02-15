local CouplingRules = require("content.coupling_rules")

local CouplingSystem = {}

local function sign(value)
  if value > 0 then
    return 1
  end
  if value < 0 then
    return -1
  end
  return 0
end

function CouplingSystem.compute(stats, rules, terraforming_state)
  local active_rules = rules or CouplingRules.edges
  local snapshot = stats or {}
  local deltas = {}
  local edge_impacts = {}

  for _, edge in ipairs(active_rules) do
    local signal = 0
    local delta = 0
    if terraforming_state and terraforming_state.get_source_coupling_signal then
      signal = terraforming_state:get_source_coupling_signal(edge.source, snapshot)
      delta = terraforming_state:get_coupling_delta_for_edge(edge.source, edge.factor or 1, snapshot, edge.target)
    else
      signal = sign(snapshot[edge.source] or 0)
      delta = signal * math.abs(edge.factor or 1)
    end

    edge_impacts[#edge_impacts + 1] = {
      source = edge.source,
      target = edge.target,
      signal = signal,
      delta = delta
    }

    if delta ~= 0 then
      deltas[edge.target] = (deltas[edge.target] or 0) + delta
    end
  end

  return deltas, edge_impacts
end

return CouplingSystem
