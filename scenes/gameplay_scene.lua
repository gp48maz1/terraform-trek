local GameplayScene = {}
GameplayScene.__index = GameplayScene

function GameplayScene.new(runtime)
  return setmetatable({ runtime = runtime }, GameplayScene)
end

function GameplayScene:enter(_ctx, _payload)
  self.runtime.set_active_scene("gameplay")
end

function GameplayScene:exit()
end

function GameplayScene:update(dt)
  self.runtime.update_gameplay(dt)
end

function GameplayScene:draw()
  self.runtime.draw_gameplay()
end

function GameplayScene:keypressed(key)
  self.runtime.keypressed_gameplay(key)
end

function GameplayScene:mousepressed(x, y, button)
  self.runtime.mousepressed_gameplay(x, y, button)
end

function GameplayScene:wheelmoved(dx, dy)
  self.runtime.wheelmoved_gameplay(dx, dy)
end

function GameplayScene:resize(w, h)
  self.runtime.resize(w, h)
end

return GameplayScene
