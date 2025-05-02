local Background = {}

-- Configuration
local background_color = {0.05, 0.02, 0.1, 1} -- Dark purple/black
local star_color_1 = {1, 1, 1, 1} -- White
local star_color_2 = {0.9, 0.9, 0.85, 1} -- Off-white
local pixel_size = 2 -- Halved default pixel size (for stars)
local star_density = 0.001 -- Adjusted density slightly

-- Cloud Configuration
-- cloud_pixel_size = 20 -- Previous large size
local cloud_pixel_size = 2 -- Match star pixel size
local cloud_color_1 = {0.98, 0.98, 1.0, 0.65} -- Lighter grey/white, semi-transparent
local cloud_color_2 = {0.8, 0.8, 0.88, 0.6}  -- Mid grey/blueish, semi-transparent
local cloud_color_3 = {0.6, 0.6, 0.7, 0.55} -- Darker grey/blueish, semi-transparent
local cloud_edge_color = {0.3, 0.3, 0.35, 0.7} -- Dark grey edge/shadow color
-- num_clouds = 10 -- Previous low count
local num_clouds = 30 -- Increased significantly due to smaller pixel size
local cloud_y_start_ratio = 0.75 -- Start clouds in bottom 25%
-- cloud_x_padding = 300 -- Previous padding
local cloud_x_padding = 60 -- Adjust padding relative to smaller pixel size

local stars = {}
local clouds = {}
local screen_width, screen_height

-- Drawing function with optional size override
local function draw_pixel(x, y, color, alpha_mod, size_override)
  local r, g, b, a = unpack(color)
  local current_pixel_size = size_override or pixel_size -- Use override if provided, else default
  love.graphics.setColor(r, g, b, a * (alpha_mod or 1))
  love.graphics.rectangle('fill', x * current_pixel_size, y * current_pixel_size, current_pixel_size, current_pixel_size)
end

-- Star drawing functions
local function draw_star_type1(x, y, color) -- Single dot
  draw_pixel(x, y, color)
end

local function draw_star_type2(x, y, color) -- Small plus
  draw_pixel(x, y, color) -- Center
  draw_pixel(x, y - 1, color, 0.6) -- North
  draw_pixel(x, y + 1, color, 0.6) -- South
  draw_pixel(x - 1, y, color, 0.6) -- West
  draw_pixel(x + 1, y, color, 0.6) -- East
end

local function draw_star_type3(x, y, color) -- Larger plus/cluster
  -- Center + cross
  draw_pixel(x, y, color)
  draw_pixel(x, y - 1, color, 0.7)
  draw_pixel(x, y + 1, color, 0.7)
  draw_pixel(x - 1, y, color, 0.7)
  draw_pixel(x + 1, y, color, 0.7)
  -- Inner corners
  draw_pixel(x - 1, y - 1, color, 0.4)
  draw_pixel(x + 1, y - 1, color, 0.4)
  draw_pixel(x - 1, y + 1, color, 0.4)
  draw_pixel(x + 1, y + 1, color, 0.4)
  -- Outer cross points
  draw_pixel(x, y - 2, color, 0.3)
  draw_pixel(x, y + 2, color, 0.3)
  draw_pixel(x - 2, y, color, 0.3)
  draw_pixel(x + 2, y, color, 0.3)
end

-- Helper function to generate pixel offsets within a circle
local function generate_circle_pixels(cx, cy, radius)
    local pixels = {}
    local radius_sq = radius * radius
    -- Iterate through bounding box around the circle
    for x = math.floor(cx - radius), math.ceil(cx + radius) do
        for y = math.floor(cy - radius), math.ceil(cy + radius) do
            local dx = x - cx
            local dy = y - cy
            -- Check if point is inside the circle
            if dx*dx + dy*dy <= radius_sq then
                table.insert(pixels, {x, y})
            end
        end
    end
    return pixels
end

-- Helper function to combine multiple sets of pixels into a unique pattern list
local function combine_pixels_unique(pixel_lists) 
    local unique_pixels = {}
    local pattern = {}
    for _, list in ipairs(pixel_lists) do
        for _, pixel in ipairs(list) do
            local key = pixel[1] .. "," .. pixel[2] -- Create unique key
            if not unique_pixels[key] then
                unique_pixels[key] = true
                table.insert(pattern, pixel)
            end
        end
    end
    return pattern
end

-- Cloud Patterns based on overlapping circles (Scaled up for smaller pixel size)

-- Pattern 1: Wider Ellipse (Larger Radii & Spread)
local cloud_pattern_ellipse_1
do
    local circles = {}
    -- Central larger circles, offset horizontally
    table.insert(circles, generate_circle_pixels(-40, 0, 40))
    table.insert(circles, generate_circle_pixels(0, 0, 45))
    table.insert(circles, generate_circle_pixels(40, 0, 40))
    -- Smaller circles for top/bottom curves and ends
    table.insert(circles, generate_circle_pixels(-60, 5, 25))
    table.insert(circles, generate_circle_pixels(60, 5, 25))
    table.insert(circles, generate_circle_pixels(-20, -10, 30))
    table.insert(circles, generate_circle_pixels(20, -10, 30))
    table.insert(circles, generate_circle_pixels(0, -15, 25))

    cloud_pattern_ellipse_1 = combine_pixels_unique(circles)
end

-- Pattern 2: Slightly Taller Ellipse (Larger Radii & Spread)
local cloud_pattern_ellipse_2
do
    local circles = {}
    -- Central circles
    table.insert(circles, generate_circle_pixels(-25, 0, 35))
    table.insert(circles, generate_circle_pixels(25, 0, 35))
    table.insert(circles, generate_circle_pixels(0, -5, 40))
    -- Top/Bottom circles
    table.insert(circles, generate_circle_pixels(0, -20, 30))
    table.insert(circles, generate_circle_pixels(0, 15, 30))
    table.insert(circles, generate_circle_pixels(-40, 10, 25))
    table.insert(circles, generate_circle_pixels(40, 10, 25))
    table.insert(circles, generate_circle_pixels(-20, -25, 20))
    table.insert(circles, generate_circle_pixels(20, -25, 20))

    cloud_pattern_ellipse_2 = combine_pixels_unique(circles)
end

local cloud_patterns = {cloud_pattern_ellipse_1, cloud_pattern_ellipse_2}

-- Cloud drawing function removed as drawing happens onto canvas in load
-- local function draw_cloud(x, y, color, pattern) ... end

-- LÖVE callbacks
function Background.load()
  screen_width, screen_height = love.graphics.getDimensions()

  -- Calculate STAR grid dimensions based on default pixel_size
  local star_grid_width = math.floor(screen_width / pixel_size)
  local star_grid_height = math.floor(screen_height / pixel_size)

  -- Calculate CLOUD grid dimensions based on cloud_pixel_size
  local cloud_grid_width = math.floor(screen_width / cloud_pixel_size)
  local cloud_grid_height = math.floor(screen_height / cloud_pixel_size)

  -- Clear existing stars and clouds
  stars = {}
  clouds = {}

  math.randomseed(os.time()) -- Seed random number generator

  -- Generate Stars (using STAR grid dimensions and density)
  local num_stars = math.floor(star_grid_width * star_grid_height * star_density)
  for _ = 1, num_stars do
    local x = math.random(1, star_grid_width)   -- Use star grid width
    local y = math.random(1, star_grid_height)  -- Use star grid height
    local type = math.random(1, 3)
    local color = math.random(1, 2) == 1 and star_color_1 or star_color_2
    table.insert(stars, {x = x, y = y, type = type, color = color})
  end

  -- Generate Clouds (Pre-render onto Canvases)
  local cloud_y_start_grid = math.floor(cloud_grid_height * cloud_y_start_ratio)
  local padded_grid_width_min = math.floor(-cloud_x_padding / cloud_pixel_size)
  local padded_grid_width_max = cloud_grid_width + math.floor(cloud_x_padding / cloud_pixel_size)
  local cloud_colors = {cloud_color_1, cloud_color_2, cloud_color_3}

  local original_canvas = love.graphics.getCanvas() -- Store current canvas

  for _ = 1, num_clouds do
      local base_x = math.random(padded_grid_width_min, padded_grid_width_max)
      local base_y = math.random(cloud_y_start_grid, cloud_grid_height)
      local pattern_index = math.random(1, #cloud_patterns)
      local pattern = cloud_patterns[pattern_index]
      local color = cloud_colors[math.random(1, #cloud_colors)]

      -- 1. Determine pattern bounds to size canvas
      local min_px, max_px = 0, 0
      local min_py, max_py = 0, 0
      for _, offset in ipairs(pattern) do
          min_px = math.min(min_px, offset[1])
          max_px = math.max(max_px, offset[1])
          min_py = math.min(min_py, offset[2])
          max_py = math.max(max_py, offset[2])
      end
      -- Add 1 because pattern coords are offsets, width/height is max-min+1
      local pattern_width_pixels = (max_px - min_px + 1) * cloud_pixel_size
      local pattern_height_pixels = (max_py - min_py + 1) * cloud_pixel_size

      -- 2. Create Canvas (handle potential zero size)
      if pattern_width_pixels > 0 and pattern_height_pixels > 0 then
          local cloud_canvas = love.graphics.newCanvas(pattern_width_pixels, pattern_height_pixels)
          love.graphics.setCanvas(cloud_canvas)
          love.graphics.clear(0, 0, 0, 0) -- Clear with transparency

          -- 3. Draw the pattern onto the canvas
          -- Coordinates need to be relative to canvas top-left
          for _, offset in ipairs(pattern) do
              local canvas_x = offset[1] - min_px -- Adjust x relative to min pattern offset
              local canvas_y = offset[2] - min_py -- Adjust y relative to min pattern offset
              -- Draw the pixel onto the canvas
              draw_pixel(canvas_x, canvas_y, color, nil, cloud_pixel_size)
          end

          -- 4. Calculate final screen position for the canvas
          -- base_x/y is grid coord, multiply by pixel size
          -- Adjust by min offset so canvas top-left aligns correctly
          local screen_x = base_x * cloud_pixel_size + min_px * cloud_pixel_size
          local screen_y = base_y * cloud_pixel_size + min_py * cloud_pixel_size

          -- 5. Store canvas and screen position
          table.insert(clouds, {canvas = cloud_canvas, x = screen_x, y = screen_y})
      end
  end

  love.graphics.setCanvas(original_canvas) -- Restore original canvas

end

-- Split drawing functions
function Background.draw_fill()
    -- Draw background fill
    love.graphics.setColor(unpack(background_color))
    love.graphics.rectangle('fill', 0, 0, screen_width, screen_height)
end

function Background.draw_clouds()
    -- Draw pre-rendered Cloud Canvases
    love.graphics.setColor(1, 1, 1, 1) -- Ensure default white color/alpha before drawing canvases
    for _, cloud_data in ipairs(clouds) do
        love.graphics.draw(cloud_data.canvas, cloud_data.x, cloud_data.y)
    end
end

function Background.draw_stars()
    -- Draw stars
    for _, star in ipairs(stars) do
        if star.type == 1 then
            draw_star_type1(star.x, star.y, star.color)
        elseif star.type == 2 then
            draw_star_type2(star.x, star.y, star.color)
        elseif star.type == 3 then
            draw_star_type3(star.x, star.y, star.color)
        end
    end
    -- Reset color to white for other drawing operations if needed
    -- Note: Moved reset to the end of the full draw sequence
    -- love.graphics.setColor(1, 1, 1, 1)
end

-- Main draw function (calls the parts in order)
function Background.draw()
    Background.draw_fill()
    Background.draw_clouds()
    Background.draw_stars()
    -- Reset color to white for other drawing operations if needed
    love.graphics.setColor(1, 1, 1, 1)
end

function Background.resize(w, h)
    screen_width, screen_height = w, h
    -- Regenerate stars and clouds on resize
    Background.load()
end

-- Optional: Add key press to regenerate stars and clouds
function Background.keypressed(key)
    if key == 'r' then
        Background.load()
    end
end

return Background

