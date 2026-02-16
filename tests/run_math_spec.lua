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
local InfluenceUIStateSpec = require("tests.influence_ui_state_spec")
local InfluenceLayoutSpec = require("tests.influence_layout_spec")
local GameplayLayoutSpec = require("tests.gameplay_layout_spec")
local CardLibraryLayoutSpec = require("tests.card_library_layout_spec")
local CardLibraryStateSpec = require("tests.card_library_state_spec")
local RuntimeDispatchSpec = require("tests.runtime_dispatch_spec")
local RuntimeSceneContractSpec = require("tests.runtime_scene_contract_spec")

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

local p4, f4 = run_section("Influence UI State Spec", InfluenceUIStateSpec.run)
passed_total = passed_total + p4
failed_total = failed_total + f4

local p5, f5 = run_section("Influence Layout Spec", InfluenceLayoutSpec.run)
passed_total = passed_total + p5
failed_total = failed_total + f5

local p6, f6 = run_section("Gameplay Layout Spec", GameplayLayoutSpec.run)
passed_total = passed_total + p6
failed_total = failed_total + f6

local p7, f7 = run_section("Card Library Layout Spec", CardLibraryLayoutSpec.run)
passed_total = passed_total + p7
failed_total = failed_total + f7

local p8, f8 = run_section("Card Library State Spec", CardLibraryStateSpec.run)
passed_total = passed_total + p8
failed_total = failed_total + f8

local p9, f9 = run_section("Runtime Dispatch Spec", RuntimeDispatchSpec.run)
passed_total = passed_total + p9
failed_total = failed_total + f9

local p10, f10 = run_section("Runtime Scene Contract Spec", RuntimeSceneContractSpec.run)
passed_total = passed_total + p10
failed_total = failed_total + f10

print("")
print(string.format("math spec suite: %d scenario(s) passed, %d failed", passed_total, failed_total))

if failed_total > 0 then
  os.exit(1)
end
