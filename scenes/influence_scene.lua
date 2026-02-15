local InfluenceScene = {}
InfluenceScene.__index = InfluenceScene

function InfluenceScene.new(runtime)
  return setmetatable({ runtime = runtime }, InfluenceScene)
end

function InfluenceScene:enter(_ctx, _payload)
  self.runtime.set_active_scene("influence")
end

function InfluenceScene:exit()
end

function InfluenceScene:update(dt)
  self.runtime.update(dt)
end

function InfluenceScene:draw()
  self.runtime.draw()
end

function InfluenceScene:keypressed(key)
  self.runtime.keypressed(key)
end

function InfluenceScene:mousepressed(x, y, button)
  self.runtime.mousepressed(x, y, button)
end

function InfluenceScene:wheelmoved(dx, dy)
  self.runtime.wheelmoved(dx, dy)
end

function InfluenceScene:resize(w, h)
  self.runtime.resize(w, h)
end

return InfluenceScene
