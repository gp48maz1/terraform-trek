local RunState = {}
RunState.__index = RunState

function RunState.new(config)
  local options = config or {}
  local self = setmetatable({}, RunState)

  self.meta_run = {
    seed = options.seed,
    path_index = options.path_index or 1,
    status = options.status or "active"
  }

  self.encounter_state = {
    kind = options.encounter_kind or "terraform_world",
    world_index = options.world_index or 1,
    turn = options.turn or 1
  }

  self.screen_state = {
    scene = options.scene or "gameplay",
    selected_card_index = options.selected_card_index,
    forecast_mode = options.forecast_mode or "current"
  }

  self.terraforming_state = options.terraforming_state
  return self
end

function RunState:set_scene(scene_id)
  self.screen_state.scene = scene_id
end

function RunState:get_scene()
  return self.screen_state.scene
end

return RunState
