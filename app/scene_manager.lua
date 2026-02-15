local SceneManager = {}
SceneManager.__index = SceneManager

function SceneManager.new()
  return setmetatable({
    scenes = {},
    current_id = nil,
    current_scene = nil
  }, SceneManager)
end

function SceneManager:register(scene_id, scene)
  self.scenes[scene_id] = scene
end

function SceneManager:get_current_id()
  return self.current_id
end

function SceneManager:switch(scene_id, ctx, payload)
  if self.current_scene and self.current_scene.exit then
    self.current_scene:exit()
  end

  self.current_id = scene_id
  self.current_scene = self.scenes[scene_id]

  if self.current_scene and self.current_scene.enter then
    self.current_scene:enter(ctx, payload)
  end
end

function SceneManager:update(dt)
  if self.current_scene and self.current_scene.update then
    self.current_scene:update(dt)
  end
end

function SceneManager:draw()
  if self.current_scene and self.current_scene.draw then
    self.current_scene:draw()
  end
end

function SceneManager:keypressed(key)
  if self.current_scene and self.current_scene.keypressed then
    self.current_scene:keypressed(key)
  end
end

function SceneManager:mousepressed(x, y, button)
  if self.current_scene and self.current_scene.mousepressed then
    self.current_scene:mousepressed(x, y, button)
  end
end

function SceneManager:wheelmoved(dx, dy)
  if self.current_scene and self.current_scene.wheelmoved then
    self.current_scene:wheelmoved(dx, dy)
  end
end

function SceneManager:resize(w, h)
  if self.current_scene and self.current_scene.resize then
    self.current_scene:resize(w, h)
  end
end

return SceneManager
