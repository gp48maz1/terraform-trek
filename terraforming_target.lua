local TerraformingTarget = {}
TerraformingTarget.__index = TerraformingTarget

function TerraformingTarget:new(o)
  o = o or {}
  setmetatable(o, self)

  -- Default properties for the planet
  o.x = love.graphics.getWidth() * 0.65 -- Position closer to center
  o.y = love.graphics.getHeight() * 0.35 -- Raised position
  o.radius = 250 -- Larger radius
  o.color = {0.5, 0.5, 0.5} -- Gray planet color
  
  -- Properties for spinning effect
  o.spin_angle = 0 -- Base start angle in radians
  o.spin_speed = -0.3 -- Radians per second (Slower and reversed)
  o.spin_dot_color = {0.1, 0.1, 0.1} -- Very dark gray dot color (was shade)
  o.spin_dot_shade_color = {0.3, 0.3, 0.3} -- Lighter dark gray for shading (was main color)
  o.num_spin_steps = 16 -- Number of discrete steps for the spin animation

  -- Define properties for multiple dots
  local num_dots = 12 -- Increase number of dots
  o.dot_initial_angles = {}
  o.dot_vertical_offsets = {}
  o.spin_dot_base_radii = {}
  o.spin_dot_aspect_ratios = {}

  local base_radii_pattern = {8, 6, 9, 7}
  local aspect_ratio_pattern = {1.2, 0.8, 1.0, 1.1}
  local max_vertical_offset = o.radius * 0.9 -- Avoid top/bottom 10%

  for i = 1, num_dots do
    -- Randomize initial angle
    o.dot_initial_angles[i] = love.math.random() * 2 * math.pi
    
    -- Randomize vertical offset within the allowed range
    o.dot_vertical_offsets[i] = (love.math.random() * 2 - 1) * max_vertical_offset
    
    -- Repeat size and shape patterns
    o.spin_dot_base_radii[i] = base_radii_pattern[((i-1) % #base_radii_pattern) + 1]
    o.spin_dot_aspect_ratios[i] = aspect_ratio_pattern[((i-1) % #aspect_ratio_pattern) + 1]
  end
  
  -- Shading control
  o.shade_scale_factor = 0.7 -- Size of the shade relative to the dot
  o.shade_offset_factor = 0.25 -- How far left the shade is offset (relative to dot radius)

  return o
end

-- Update the planet's state (e.g., spinning)
function TerraformingTarget:update(dt)
  self.spin_angle = (self.spin_angle + self.spin_speed * dt) -- Increment angle (wrapping handled below)
  -- Ensure angle stays within a reasonable range to avoid potential precision issues over time
  if math.abs(self.spin_angle) > 100 * math.pi then
     self.spin_angle = self.spin_angle % (2 * math.pi)
  end
end

-- Draw the planet
function TerraformingTarget:draw()
  local gfx = love.graphics

  -- Set the planet's color
  gfx.setColor(self.color[1], self.color[2], self.color[3])

  -- Draw the circle representing the planet
  gfx.circle("fill", self.x, self.y, self.radius)

  -- Calculate step size once
  local step_size = (2 * math.pi) / self.num_spin_steps
  -- Calculate a single stepped base angle
  local stepped_base_angle = math.floor(self.spin_angle / step_size) * step_size

  -- Set dot color once
  gfx.setColor(self.spin_dot_color[1], self.spin_dot_color[2], self.spin_dot_color[3])

  -- Draw each dot
  for i = 1, #self.dot_initial_angles do
    local initial_angle = self.dot_initial_angles[i]
    local vertical_offset = self.dot_vertical_offsets[i]
    local dot_base_radius = self.spin_dot_base_radii[i]
    local dot_aspect_ratio = self.spin_dot_aspect_ratios[i]
    local dot_radius_x = dot_base_radius * dot_aspect_ratio
    local dot_radius_y = dot_base_radius

    -- Calculate continuous angle for visibility check
    local current_dot_angle = (self.spin_angle + initial_angle)

    -- Calculate the final angle for positioning by adding the initial offset to the *stepped base angle*
    local position_angle = stepped_base_angle + initial_angle

    -- Adjust horizontal range based on vertical position
    local horizontal_radius_factor = math.sqrt(math.max(0, 1 - (vertical_offset / self.radius)^2))
    -- Effective radius now considers the horizontal radius of the ellipse
    local effective_radius = (self.radius - dot_radius_x) * horizontal_radius_factor
    
    local dot_x = self.x + math.cos(position_angle) * effective_radius
    local dot_y = self.y + vertical_offset

    -- Only draw the dot if it's on the "front" side using the angle that determines its position
    if math.sin(position_angle) > 0 then
      -- 1. Draw the main dot ellipse first
      gfx.setColor(self.spin_dot_color[1], self.spin_dot_color[2], self.spin_dot_color[3])
      gfx.ellipse("fill", dot_x, dot_y, dot_radius_x, dot_radius_y)
      
      -- 2. Calculate and draw the inner shading ellipse on top
      local shade_radius_x = dot_radius_x * self.shade_scale_factor
      local shade_radius_y = dot_radius_y * self.shade_scale_factor
      local shade_offset_x = -dot_radius_x * self.shade_offset_factor -- Offset left
      local shade_x = dot_x + shade_offset_x
      local shade_y = dot_y -- Keep vertically centered for simplicity
      
      gfx.setColor(self.spin_dot_shade_color[1], self.spin_dot_shade_color[2], self.spin_dot_shade_color[3])
      gfx.ellipse("fill", shade_x, shade_y, shade_radius_x, shade_radius_y)
    end
  end

  -- Reset color
  gfx.setColor(1, 1, 1)
end

return TerraformingTarget 