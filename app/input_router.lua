local InputRouter = {}
InputRouter.__index = InputRouter

function InputRouter.new(scene_manager)
  return setmetatable({
    scene_manager = scene_manager
  }, InputRouter)
end

function InputRouter:keypressed(key)
  self.scene_manager:keypressed(key)
end

function InputRouter:mousepressed(x, y, button)
  self.scene_manager:mousepressed(x, y, button)
end

function InputRouter:wheelmoved(dx, dy)
  self.scene_manager:wheelmoved(dx, dy)
end

return InputRouter
