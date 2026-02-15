package.path = package.path .. ";./?.lua;./?/init.lua"

love = {
  math = {
    random = math.random,
    setRandomSeed = math.randomseed
  }
}

local characterization = require("tests.characterization")
local result = characterization.run_baseline()

print("characterization baseline")
print("hazard forecast: " .. tostring(result.forecast_hazard))
print("hazard resolved: " .. tostring(result.realized_hazard))
print("net: " .. tostring(result.realized_net))
print("population: " .. tostring(result.population))
print("profit: " .. tostring(result.profit))
