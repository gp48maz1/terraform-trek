package.path = package.path .. ";./?.lua;./?/init.lua"

love = {
  math = {
    random = math.random,
    setRandomSeed = math.randomseed
  }
}

local suite = require("tests.math_suite")
local _, failed = suite.run()
if failed > 0 then
  os.exit(1)
end
