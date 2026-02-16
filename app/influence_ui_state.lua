local InfluenceUIState = {}
InfluenceUIState.__index = InfluenceUIState

local EDGE_FILTER_MODES = { "focused_both", "focused_incoming", "focused_outgoing", "all" }
local EDGE_FILTER_LABELS = {
  focused_both = "In + Out",
  focused_incoming = "Incoming",
  focused_outgoing = "Outgoing",
  all = "All Edges"
}

function InfluenceUIState.new()
  local self = setmetatable({}, InfluenceUIState)
  self:reset_for_new_campaign()
  return self
end

function InfluenceUIState:reset_hover_state()
  self.hovered_influence_stat = nil
  self.hovered_forecast_option_index = nil
  self.hovered_edge_filter_button = false
  self.hovered_forecast_mode = nil
  self.hovered_graph_explain_button = false
  self.hovered_turn_explain_button = false
  self.hovered_objectives_explain_button = false
  self.hovered_help_button = false
end

function InfluenceUIState:reset_for_new_campaign()
  self.focused_stat = "heat"
  self.selected_forecast_card_index = nil
  self.forecast_mode = "current" -- current | do_nothing | selected
  self.edge_filter_mode = "focused_both" -- focused_both | focused_incoming | focused_outgoing | all
  self.show_graph_explain = false
  self.show_turn_explain = false
  self.show_objectives_explain = false
  self.show_help_tooltip = false
  self:reset_hover_state()
end

function InfluenceUIState:set_current_mode()
  self.selected_forecast_card_index = nil
  self.forecast_mode = "current"
end

function InfluenceUIState:set_do_nothing_mode(clear_selection)
  if clear_selection then
    self.selected_forecast_card_index = nil
  end
  self.forecast_mode = "do_nothing"
end

function InfluenceUIState:set_selected_mode(card_index)
  if card_index then
    self.selected_forecast_card_index = card_index
  end
  if self.selected_forecast_card_index then
    self.forecast_mode = "selected"
  else
    self.forecast_mode = "do_nothing"
  end
end

function InfluenceUIState:set_selected_or_do_nothing_mode()
  if self.selected_forecast_card_index then
    self.forecast_mode = "selected"
  else
    self.forecast_mode = "do_nothing"
  end
end

function InfluenceUIState:sanitize_selection(hand_count)
  if self.selected_forecast_card_index and self.selected_forecast_card_index > hand_count then
    self.selected_forecast_card_index = nil
    if self.forecast_mode == "selected" then
      self.forecast_mode = "current"
    end
  end
end

function InfluenceUIState:cycle_edge_filter_mode()
  for i, mode in ipairs(EDGE_FILTER_MODES) do
    if self.edge_filter_mode == mode then
      self.edge_filter_mode = EDGE_FILTER_MODES[(i % #EDGE_FILTER_MODES) + 1]
      return
    end
  end
  self.edge_filter_mode = EDGE_FILTER_MODES[1]
end

function InfluenceUIState:get_edge_filter_label()
  return EDGE_FILTER_LABELS[self.edge_filter_mode] or EDGE_FILTER_LABELS.focused_both
end

function InfluenceUIState:edge_is_visible(edge)
  if self.edge_filter_mode == "all" then
    return true
  end
  if self.edge_filter_mode == "focused_incoming" then
    return edge.target == self.focused_stat
  end
  if self.edge_filter_mode == "focused_outgoing" then
    return edge.source == self.focused_stat
  end
  return edge.source == self.focused_stat or edge.target == self.focused_stat
end

function InfluenceUIState:toggle_graph_explain()
  self.show_graph_explain = not self.show_graph_explain
  if self.show_graph_explain then
    self.show_turn_explain = false
  end
end

function InfluenceUIState:toggle_turn_explain()
  self.show_turn_explain = not self.show_turn_explain
  if self.show_turn_explain then
    self.show_graph_explain = false
  end
end

function InfluenceUIState:toggle_objectives_explain()
  self.show_objectives_explain = not self.show_objectives_explain
end

function InfluenceUIState:toggle_help_tooltip()
  self.show_help_tooltip = not self.show_help_tooltip
end

return InfluenceUIState
