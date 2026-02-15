local PreviewContextSystem = {}
local ActionApplier = require("systems.action_applier")

local function shallow_copy(input)
  local out = {}
  for k, v in pairs(input or {}) do
    out[k] = v
  end
  return out
end

local function normalize_mode(mode)
  if mode == "current" or mode == "do_nothing" or mode == "selected" then
    return mode
  end
  return "current"
end

local function get_edges_for_snapshot(state, snapshot)
  local _, edges = state:compute_coupling(snapshot)
  return shallow_copy(edges)
end

function PreviewContextSystem.build(state, hand, selected_card_index, forecast_mode, can_afford_fn)
  local cards = hand or {}
  local selected_index = tonumber(selected_card_index)
  local mode = normalize_mode(forecast_mode)

  local current_snapshot = shallow_copy(state.stats or {})
  local current_economy = state:get_economy_snapshot()
  local baseline = state:forecast_end_turn(current_snapshot, {
    economy_state = current_economy
  })

  local scenario = nil
  local card_push_snapshot = nil
  if selected_index and selected_index >= 1 and selected_index <= #cards then
    local card = cards[selected_index]
    if card then
      local preview_snapshot = shallow_copy(current_snapshot)
      local preview_economy = state:get_economy_snapshot()
      ActionApplier.apply_card_preview(state, card, preview_snapshot, preview_economy)
      card_push_snapshot = shallow_copy(preview_snapshot)
      scenario = {
        card = card,
        card_index = selected_index,
        affordable = can_afford_fn and can_afford_fn(card.cost or 0) or true,
        summary = state:forecast_end_turn(preview_snapshot, { economy_state = preview_economy })
      }
    end
  end

  if mode == "selected" and not scenario then
    mode = "do_nothing"
  end

  local active_snapshot = current_snapshot
  local active_summary = nil
  local active_edge_deltas = get_edges_for_snapshot(state, current_snapshot)
  local active_economy = current_economy

  if mode == "do_nothing" then
    active_summary = baseline
    active_snapshot = baseline.projected_stats or current_snapshot
    active_edge_deltas = shallow_copy(baseline.coupling_edge_deltas)
    active_economy = {
      population = baseline.projected_population or current_economy.population,
      profit = baseline.projected_profit or current_economy.profit,
      industries = state:clone_industry_slots(baseline.projected_industries or current_economy.industries)
    }
  elseif mode == "selected" and scenario then
    local summary = scenario.summary
    active_summary = summary
    active_snapshot = summary.projected_stats or current_snapshot
    active_edge_deltas = shallow_copy(summary.coupling_edge_deltas)
    active_economy = {
      population = summary.projected_population or current_economy.population,
      profit = summary.projected_profit or current_economy.profit,
      industries = state:clone_industry_slots(summary.projected_industries or current_economy.industries)
    }
  end

  return {
    baseline = baseline,
    scenario = scenario,
    card_push_snapshot = card_push_snapshot,
    active_mode = mode,
    active_snapshot = active_snapshot,
    active_summary = active_summary,
    active_edge_deltas = active_edge_deltas,
    current_economy = current_economy,
    active_economy = active_economy
  }
end

return PreviewContextSystem
