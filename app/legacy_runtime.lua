local RuntimeContext = require("app.runtime_context")
local RuntimeGameplay = require("app.runtime_gameplay")
local RuntimeInfluence = require("app.runtime_influence")
local RuntimeCardLibrary = require("app.runtime_card_library")

local Runtime = {}

local ctx = RuntimeContext.new()
local gameplay = RuntimeGameplay.new(ctx)
local influence = RuntimeInfluence.new(ctx)
local card_library = RuntimeCardLibrary.new(ctx)

function Runtime.load()
  ctx:load()
end

function Runtime.resize(w, h)
  ctx:resize(w, h)
end

function Runtime.update(dt)
  local active_scene = Runtime.get_active_scene()
  if active_scene == "card_library" then
    Runtime.update_card_library(dt)
  elseif active_scene == "influence" then
    Runtime.update_influence(dt)
  else
    Runtime.update_gameplay(dt)
  end
end

function Runtime.draw()
  local active_scene = Runtime.get_active_scene()
  if active_scene == "card_library" then
    Runtime.draw_card_library()
  elseif active_scene == "influence" then
    Runtime.draw_influence()
  else
    Runtime.draw_gameplay()
  end
end

function Runtime.keypressed(key)
  local active_scene = Runtime.get_active_scene()
  if active_scene == "card_library" then
    Runtime.keypressed_card_library(key)
  elseif active_scene == "influence" then
    Runtime.keypressed_influence(key)
  else
    Runtime.keypressed_gameplay(key)
  end
end

function Runtime.mousepressed(x, y, button)
  local active_scene = Runtime.get_active_scene()
  if active_scene == "card_library" then
    Runtime.mousepressed_card_library(x, y, button)
  elseif active_scene == "influence" then
    Runtime.mousepressed_influence(x, y, button)
  else
    Runtime.mousepressed_gameplay(x, y, button)
  end
end

function Runtime.wheelmoved(dx, dy)
  local active_scene = Runtime.get_active_scene()
  if active_scene == "card_library" then
    Runtime.wheelmoved_card_library(dx, dy)
  elseif active_scene == "influence" then
    Runtime.wheelmoved_influence(dx, dy)
  else
    Runtime.wheelmoved_gameplay(dx, dy)
  end
end

function Runtime.update_gameplay(dt)
  gameplay:update(dt)
end

function Runtime.update_influence(dt)
  influence:update(dt)
end

function Runtime.update_card_library(dt)
  card_library:update(dt)
end

function Runtime.draw_gameplay()
  gameplay:draw()
end

function Runtime.draw_influence()
  influence:draw()
end

function Runtime.draw_card_library()
  card_library:draw()
end

function Runtime.keypressed_gameplay(key)
  gameplay:keypressed(key)
end

function Runtime.keypressed_influence(key)
  influence:keypressed(key)
end

function Runtime.keypressed_card_library(key)
  card_library:keypressed(key)
end

function Runtime.mousepressed_gameplay(x, y, button)
  gameplay:mousepressed(x, y, button)
end

function Runtime.mousepressed_influence(x, y, button)
  influence:mousepressed(x, y, button)
end

function Runtime.mousepressed_card_library(x, y, button)
  card_library:mousepressed(x, y, button)
end

function Runtime.wheelmoved_gameplay(dx, dy)
  gameplay:wheelmoved(dx, dy)
end

function Runtime.wheelmoved_influence(dx, dy)
  influence:wheelmoved(dx, dy)
end

function Runtime.wheelmoved_card_library(dx, dy)
  card_library:wheelmoved(dx, dy)
end

function Runtime.get_active_scene()
  return ctx:get_active_scene()
end

function Runtime.set_active_scene(scene_name)
  ctx:set_active_scene(scene_name)
end

function Runtime.get_viewport()
  return ctx:get_viewport()
end

return Runtime
