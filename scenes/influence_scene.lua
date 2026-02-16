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
  self.runtime.update_influence(dt)
end

function InfluenceScene:draw()
  self.runtime.draw_influence()
end

function InfluenceScene:keypressed(key)
  self.runtime.keypressed_influence(key)
end

function InfluenceScene:mousepressed(x, y, button)
  self.runtime.mousepressed_influence(x, y, button)
end

function InfluenceScene:wheelmoved(dx, dy)
  self.runtime.wheelmoved_influence(dx, dy)
end

function InfluenceScene:resize(w, h)
  self.runtime.resize(w, h)
end

return InfluenceScene
