local Background = {}

-- Configuration
local background_color = {0.05, 0.02, 0.1, 1} -- Dark purple/black
local star_color_1 = {1, 1, 1, 1} -- White
local star_color_2 = {0.9, 0.9, 0.85, 1} -- Off-white
local pixel_size = 3 -- Size of one 'pixel' in screen pixels
local star_density = 0.001 -- Lower number means fewer stars

local stars = {}
local screen_width, screen_height

-- Star drawing functions
local function draw_pixel(x, y, color, alpha_mod)
  local r, g, b, a = unpack(color)
  love.graphics.setColor(r, g, b, a * (alpha_mod or 1))
  love.graphics.rectangle('fill', x * pixel_size, y * pixel_size, pixel_size, pixel_size)
end

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

-- LÖVE callbacks
function Background.load()
  screen_width, screen_height = love.graphics.getDimensions()
  local grid_width = math.floor(screen_width / pixel_size)
  local grid_height = math.floor(screen_height / pixel_size)
  local num_stars = math.floor(grid_width * grid_height * star_density)

  math.randomseed(os.time()) -- Seed random number generator

  for _ = 1, num_stars do
    local x = math.random(1, grid_width)
    local y = math.random(1, grid_height)
    local type = math.random(1, 3)
    local color = math.random(1, 2) == 1 and star_color_1 or star_color_2

    table.insert(stars, {x = x, y = y, type = type, color = color})
  end
end

function Background.draw()
  -- Draw background
  love.graphics.setColor(unpack(background_color))
  love.graphics.rectangle('fill', 0, 0, screen_width, screen_height)

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
  love.graphics.setColor(1, 1, 1, 1)
end

function Background.resize(w, h)
    -- Optional: Regenerate stars if window is resized
    -- Comment out if you want stars to stay fixed relative to top-left
    screen_width, screen_height = w, h
    stars = {} -- Clear existing stars
    Background.load() -- Reload/regenerate stars for new dimensions
end

-- Optional: Add key press to regenerate stars
function Background.keypressed(key)
    if key == 'r' then
        stars = {}
        Background.load()
    end
end

return Background
