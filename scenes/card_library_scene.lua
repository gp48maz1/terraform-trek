local CardLibraryScene = {}
CardLibraryScene.__index = CardLibraryScene

function CardLibraryScene.new(runtime)
  return setmetatable({ runtime = runtime }, CardLibraryScene)
end

function CardLibraryScene:enter(_ctx, _payload)
  self.runtime.set_active_scene("card_library")
end

function CardLibraryScene:exit()
end

function CardLibraryScene:update(dt)
  self.runtime.update_card_library(dt)
end

function CardLibraryScene:draw()
  self.runtime.draw_card_library()
end

function CardLibraryScene:keypressed(key)
  self.runtime.keypressed_card_library(key)
end

function CardLibraryScene:mousepressed(x, y, button)
  self.runtime.mousepressed_card_library(x, y, button)
end

function CardLibraryScene:wheelmoved(dx, dy)
  self.runtime.wheelmoved_card_library(dx, dy)
end

function CardLibraryScene:resize(w, h)
  self.runtime.resize(w, h)
end

return CardLibraryScene
