local ObjectivesSystem = {}

function ObjectivesSystem.compute(run_state)
  local state = run_state and run_state.terraforming_state or run_state
  if not state then
    return 0, 0, {
      error = "missing_state"
    }
  end

  local snapshot = state.stats or {}
  local economy = state:get_economy_snapshot()

  local population_delta, population_breakdown = state:compute_population_delta(snapshot)
  local projected_population = math.max(0, (economy.population or 0) + population_delta)

  local industries = state:clone_industry_slots(economy.industries)
  local profit_delta, industry_report = state:simulate_industry_phase(snapshot, projected_population, industries)

  return population_delta, profit_delta, {
    population_before = economy.population,
    population_after = projected_population,
    population_breakdown = population_breakdown,
    profit_before = economy.profit,
    profit_after = math.max(0, (economy.profit or 0) + profit_delta),
    industry_report = industry_report,
    projected_industries = industries
  }
end

return ObjectivesSystem
