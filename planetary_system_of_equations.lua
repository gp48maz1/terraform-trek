-- planetary_system_of_equations.lua

-- Define a structure (using a table) to hold the state and coefficients for a planetary system
local PlanetarySystem = {}
PlanetarySystem.__index = PlanetarySystem

-- Function to create a new planetary system instance
-- Takes initial values and coefficients as input tables
function PlanetarySystem.new(initial_values, coefficients)
    local self = setmetatable({}, PlanetarySystem)

    -- Ensure input tables exist
    initial_values = initial_values or {}
    coefficients = coefficients or {}

    -- Initial values (ensure all necessary keys are present, provide defaults if needed)
    self.S = initial_values.S or 1.0 -- Solar Strength (External Condition)
    self.M = initial_values.M or 1.0 -- Magnetosphere (External Condition)
    self.T = initial_values.T or 1.0 -- Tectonic Activity (External Condition)
    self.L = initial_values.L or 1.0 -- Lithosphere
    self.A = initial_values.A or 1.0 -- Atmosphere
    self.H = initial_values.H or 1.0 -- Hydrosphere
    self.B = initial_values.B or 1.0 -- Biosphere

    -- Coefficients (ensure all necessary keys are present, provide defaults if needed)
    self.coeffs = {
        alpha1 = coefficients.alpha1 or 0.1,
        alpha2 = coefficients.alpha2 or 0.05,
        alpha3 = coefficients.alpha3 or 0.03,
        beta1  = coefficients.beta1  or 0.02,
        beta2  = coefficients.beta2  or 0.02,
        gamma1 = coefficients.gamma1 or 0.08,
        gamma2 = coefficients.gamma2 or 0.04,
        delta1 = coefficients.delta1 or 0.01,
        delta2 = coefficients.delta2 or 0.01,
        epsilon1 = coefficients.epsilon1 or 0.07,
        zeta1  = coefficients.zeta1  or 0.02,
        eta1   = coefficients.eta1   or 0.05,
        eta2   = coefficients.eta2   or 0.05,
        eta3   = coefficients.eta3   or 0.05
    }

    return self
end

-- Update functions (defined as methods of the PlanetarySystem)
-- Calculate the rate of change for Atmosphere
function PlanetarySystem:update_A()
    local c = self.coeffs
    -- dA/dt = α1*S + α2*M + α3*L + β1*(B - A) + β2*(H - A)
    return c.alpha1 * self.S + c.alpha2 * self.M + c.alpha3 * self.L + c.beta1 * (self.B - self.A) + c.beta2 * (self.H - self.A)
end

-- Calculate the rate of change for Hydrosphere
function PlanetarySystem:update_H()
    local c = self.coeffs
    -- dH/dt = γ1*S + γ2*L + δ1*(A - H) + δ2*(B - H)
    return c.gamma1 * self.S + c.gamma2 * self.L + c.delta1 * (self.A - self.H) + c.delta2 * (self.B - self.H)
end

-- Calculate the rate of change for Lithosphere
function PlanetarySystem:update_L()
    local c = self.coeffs
    -- dL/dt = ε1*T + ζ1*(B - L)
    return c.epsilon1 * self.T + c.zeta1 * (self.B - self.L)
end

-- Calculate the rate of change for Biosphere
function PlanetarySystem:update_B()
    local c = self.coeffs
    -- dB/dt = η1*A + η2*H + η3*L
    return c.eta1 * self.A + c.eta2 * self.H + c.eta3 * self.L
end

-- Simulation step function using Euler integration
function PlanetarySystem:step(dt)
    local dA = self:update_A()
    local dH = self:update_H()
    local dL = self:update_L()
    local dB = self:update_B()

    -- Apply changes using Euler integration
    self.A = self.A + dA * dt
    self.H = self.H + dH * dt
    self.L = self.L + dL * dt
    self.B = self.B + dB * dt

    -- Note: S, M, T are treated as external conditions/constants in this model.
    -- They represent influences that are not changed by the A, H, L, B dynamics shown here.
    -- If they need to change based on other game events or time, you would update self.S, self.M, self.T elsewhere.
end

-- Function to get the current state values
function PlanetarySystem:get_state()
    return {
        S = self.S, M = self.M, T = self.T,
        L = self.L, A = self.A, H = self.H, B = self.B
    }
end

-- Return the PlanetarySystem class/table so it can be used by other modules
return PlanetarySystem

--[[ Example Usage:

-- Require the module
local System = require("planetary_system_of_equations")

-- Define unique initial values and coefficients for two different targets
local target1_initials = { L = 1.1, A = 0.9, H = 1.0, B = 1.2 } -- S, M, T default to 1.0
local target1_coeffs = { alpha1 = 0.11, beta1 = 0.025 } -- Other coeffs use defaults

local target2_initials = { L = 0.8, A = 1.2, H = 0.9, B = 0.8 }
local target2_coeffs = { gamma1 = 0.07, eta1 = 0.06, eta2 = 0.04 }

-- Create instances
local system1 = System.new(target1_initials, target1_coeffs)
local system2 = System.new(target2_initials, target2_coeffs)

-- Simulation parameters
local dt = 0.01 -- Time step
local simulation_steps = 100

-- Run simulation
print("Starting simulation...")
for i = 1, simulation_steps do
    system1:step(dt)
    system2:step(dt)

    -- Optional: Print state at certain intervals
    if i % 10 == 0 then
        local state1 = system1:get_state()
        local state2 = system2:get_state()
        print(string.format("Step %d - Target 1: A=%.2f, H=%.2f, L=%.2f, B=%.2f", i, state1.A, state1.H, state1.L, state1.B))
        print(string.format("Step %d - Target 2: A=%.2f, H=%.2f, L=%.2f, B=%.2f", i, state2.A, state2.H, state2.L, state2.B))
    end
end
print("Simulation finished.")

]]
