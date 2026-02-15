package.path = package.path .. ";./?.lua;./?/init.lua"

love = {
  math = {
    random = math.random,
    setRandomSeed = math.randomseed
  }
}

local PreviewSpec = require("tests.preview_spec")
local ForecastTraceSpec = require("tests.forecast_trace_spec")
local ActionApplierSpec = require("tests.action_applier_spec")

local function run_section(name, fn)
  print("")
  print("=== " .. name .. " ===")
  local passed, failed = fn()
  print(string.format("Section result: %d passed, %d failed", passed, failed))
  return passed, failed
end

local passed_total = 0
local failed_total = 0

local p1, f1 = run_section("Preview Context Spec", PreviewSpec.run)
passed_total = passed_total + p1
failed_total = failed_total + f1

local p2, f2 = run_section("Forecast Trace Spec", ForecastTraceSpec.run)
passed_total = passed_total + p2
failed_total = failed_total + f2

local p3, f3 = run_section("Action Applier Spec", ActionApplierSpec.run)
passed_total = passed_total + p3
failed_total = failed_total + f3

print("")
print(string.format("math spec suite: %d scenario(s) passed, %d failed", passed_total, failed_total))

if failed_total > 0 then
  os.exit(1)
end
