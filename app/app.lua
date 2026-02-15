local LegacyRuntime = require("app.legacy_runtime")
local SceneManager = require("app.scene_manager")
local InputRouter = require("app.input_router")
local Services = require("app.services")

local GameplayScene = require("scenes.gameplay_scene")
local InfluenceScene = require("scenes.influence_scene")
local CardLibraryScene = require("scenes.card_library_scene")

local App = {}
App.__index = App

function App.new()
  local self = setmetatable({}, App)
  self.runtime = LegacyRuntime
  self.scene_manager = SceneManager.new()
  self.input_router = InputRouter.new(self.scene_manager)
  self.services = Services
  self.ctx = {
    viewport = nil,
    assets = {},
    input = self.input_router,
    run_state = nil,
    services = self.services,
    ui_flags = {}
  }

  self.scene_manager:register("gameplay", GameplayScene.new(self.runtime))
  self.scene_manager:register("influence", InfluenceScene.new(self.runtime))
  self.scene_manager:register("card_library", CardLibraryScene.new(self.runtime))

  return self
end

function App:sync_scene()
  self.ctx.viewport = self.runtime.get_viewport()
  local runtime_scene = self.runtime.get_active_scene()
  if self.scene_manager:get_current_id() ~= runtime_scene then
    self.scene_manager:switch(runtime_scene, self.ctx)
  end
end

function App:load()
  self.runtime.load()
  self:sync_scene()
end

function App:update(dt)
  self.scene_manager:update(dt)
  self:sync_scene()
end

function App:draw()
  self.scene_manager:draw()
end

function App:resize(w, h)
  self.scene_manager:resize(w, h)
  self:sync_scene()
end

function App:keypressed(key)
  self.input_router:keypressed(key)
  self:sync_scene()
end

function App:mousepressed(x, y, button)
  self.input_router:mousepressed(x, y, button)
  self:sync_scene()
end

function App:wheelmoved(dx, dy)
  self.input_router:wheelmoved(dx, dy)
  self:sync_scene()
end

return App
