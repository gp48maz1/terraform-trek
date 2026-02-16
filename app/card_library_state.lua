local CardLibraryState = {}

local CARD_LIBRARY_TOPIC_ORDER = {
  "Terraform",
  "Industry",
  "Chance",
  "Power",
  "Heat",
  "Air",
  "Water",
  "Soil",
  "Economy",
  "Draw",
  "Stabilize",
  "Stat Change"
}

local CATEGORY_SORT_ORDER = {
  Terraform = 1,
  Industry = 2,
  Chance = 3,
  Power = 4
}

local function clamp_value(value, min_value, max_value)
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
end

local function get_topics_for_card(card_data, stat_labels)
  local labels = stat_labels or {}
  local topics = {}
  local function add(topic)
    if topic and topic ~= "" then
      topics[topic] = true
    end
  end

  add(card_data.category)
  local properties = card_data.properties or {}
  local changes = properties.stat_changes
  if changes then
    add("Stat Change")
    for stat_key, _ in pairs(changes) do
      add(labels[stat_key] or stat_key)
    end
  end

  if card_data.effect_fn_name == "install_industry" then
    add("Economy")
    add("Industry")
  elseif card_data.effect_fn_name == "draw_cards" then
    add("Draw")
  elseif card_data.effect_fn_name == "stabilize_system" then
    add("Stabilize")
  end

  return topics
end

function CardLibraryState.new()
  return {
    cards = {},
    topics = { "All" },
    selected_topic = "All",
    selected_card_id = nil,
    hovered_topic = nil,
    hovered_card_id = nil,
    scroll_offset = 0,
    max_scroll = 0
  }
end

function CardLibraryState.reset_hover(state)
  state.hovered_topic = nil
  state.hovered_card_id = nil
end

function CardLibraryState.initialize(state, opts)
  local options = opts or {}
  local card_types = options.card_types or require("card_types")
  local card_class = options.card_class or require("card")
  local stat_labels = options.stat_labels or {}

  local card_ids = card_types.getAllCardIds()
  table.sort(card_ids)

  local entries = {}
  local topic_presence = {}
  for _, card_id in ipairs(card_ids) do
    local card_data = card_types.createCardData(card_id)
    local topics = get_topics_for_card(card_data, stat_labels)
    for topic, _ in pairs(topics) do
      topic_presence[topic] = true
    end
    table.insert(entries, {
      id = card_id,
      data = card_data,
      card = card_class:new(card_data),
      topics = topics
    })
  end

  table.sort(entries, function(a, b)
    local ca = CATEGORY_SORT_ORDER[a.data.category] or 99
    local cb = CATEGORY_SORT_ORDER[b.data.category] or 99
    if ca == cb then
      return string.lower(a.data.name) < string.lower(b.data.name)
    end
    return ca < cb
  end)

  local topics = { "All" }
  for _, topic in ipairs(CARD_LIBRARY_TOPIC_ORDER) do
    if topic_presence[topic] then
      table.insert(topics, topic)
      topic_presence[topic] = nil
    end
  end

  local extra_topics = {}
  for topic, _ in pairs(topic_presence) do
    table.insert(extra_topics, topic)
  end
  table.sort(extra_topics)
  for _, topic in ipairs(extra_topics) do
    table.insert(topics, topic)
  end

  state.cards = entries
  state.topics = topics
  state.selected_topic = "All"
  state.selected_card_id = entries[1] and entries[1].id or nil
  state.scroll_offset = 0
  state.max_scroll = 0
  CardLibraryState.reset_hover(state)
end

function CardLibraryState.get_filtered_entries(state)
  local filtered = {}
  local selected_topic = state.selected_topic
  for _, entry in ipairs(state.cards or {}) do
    if selected_topic == "All" or entry.topics[selected_topic] then
      table.insert(filtered, entry)
    end
  end
  return filtered
end

function CardLibraryState.ensure_selection(state, filtered)
  if #filtered == 0 then
    state.selected_card_id = nil
    return
  end

  local selected_id = state.selected_card_id
  for _, entry in ipairs(filtered) do
    if entry.id == selected_id then
      return
    end
  end
  state.selected_card_id = filtered[1].id
end

function CardLibraryState.get_selected_entry(state, filtered)
  for _, entry in ipairs(filtered) do
    if entry.id == state.selected_card_id then
      return entry
    end
  end
  return filtered[1]
end

function CardLibraryState.set_max_scroll(state, max_scroll)
  state.max_scroll = math.max(0, max_scroll or 0)
  state.scroll_offset = clamp_value(state.scroll_offset, 0, state.max_scroll)
end

function CardLibraryState.select_topic(state, topic)
  if not topic or topic == "" then
    return
  end
  state.selected_topic = topic
  state.scroll_offset = 0
end

function CardLibraryState.select_card(state, card_id)
  state.selected_card_id = card_id
end

function CardLibraryState.scroll_by(state, wheel_delta, step)
  local delta = wheel_delta or 0
  local amount = step or 44
  state.scroll_offset = clamp_value(state.scroll_offset - delta * amount, 0, state.max_scroll)
end

function CardLibraryState.cycle_topic(state, direction)
  local topics = state.topics or {}
  if #topics == 0 then
    return nil
  end

  local current_index = 1
  for i, topic in ipairs(topics) do
    if topic == state.selected_topic then
      current_index = i
      break
    end
  end

  local dir = direction or 1
  current_index = current_index + dir
  if current_index < 1 then
    current_index = #topics
  elseif current_index > #topics then
    current_index = 1
  end
  CardLibraryState.select_topic(state, topics[current_index])
  return topics[current_index]
end

return CardLibraryState
