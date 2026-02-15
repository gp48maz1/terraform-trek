local App = require("app.app")

local app = App.new()

function love.load()
  app:load()
end

function love.resize(w, h)
  app:resize(w, h)
end

function love.update(dt)
  app:update(dt)
end

function love.draw()
  app:draw()
end

function love.keypressed(key)
  app:keypressed(key)
end

function love.mousepressed(x, y, button)
  app:mousepressed(x, y, button)
end

function love.wheelmoved(dx, dy)
  app:wheelmoved(dx, dy)
end
