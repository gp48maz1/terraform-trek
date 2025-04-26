-- planetary_system_relationships.lua

local RelationshipsView = {}

-- Pulse state
RelationshipsView.pulse_progress = 0
RelationshipsView.pulse_speed = 0.2 -- Controls speed (lower is slower, 1.0 = 1 cycle/sec)

-- Define colors
local black_color = {0.1, 0.1, 0.1, 1}
local blue_color = {0.2, 0.2, 0.8, 1}
local gray_color = {0.2, 0.2, 0.2, 1} -- For text and general lines
local light_black_color = {0.6, 0.6, 0.6, 0.5} -- Lighter gray, semi-transparent
local light_blue_color = {0.6, 0.6, 1.0, 0.5} -- Lighter blue, semi-transparent

-- Helper function to draw a labeled box (node)
local function draw_node(label, x, y, w, h)
    local padding = 5
    love.graphics.setColor(0.8, 0.8, 0.8, 1) -- Light gray box
    love.graphics.rectangle("fill", x, y, w, h, 5, 5) -- Rounded corners
    love.graphics.setColor(0.1, 0.1, 0.1, 1) -- Dark text
    love.graphics.rectangle("line", x, y, w, h, 5, 5)
    love.graphics.printf(label, x + padding, y + padding, w - 2 * padding, "center")
end

-- Helper function to draw a labeled container box for groups
local function draw_group_box(label, x, y, w, h)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(0.7, 0.7, 0.9, 0.5) -- Light purple, semi-transparent fill
    love.graphics.rectangle("fill", x, y, w, h, 10, 10) -- Rounded corners
    love.graphics.setColor(0.4, 0.4, 0.6, 1) -- Darker purple outline
    love.graphics.rectangle("line", x, y, w, h, 10, 10)
    love.graphics.setLineWidth(1)
    
    -- Draw label above the box
    love.graphics.setColor(0.2, 0.2, 0.4, 1)
    love.graphics.printf(label, x, y - 20, w, "center")
end

-- Helper function to find the intersection point of a line segment (from center1 to center2)
-- with the boundary of a rectangle (rect_x, rect_y, rect_w, rect_h)
-- Returns the intersection point coordinates (ix, iy)
local function get_rect_line_intersection(cx1, cy1, cx2, cy2, rect_x, rect_y, rect_w, rect_h)
    local half_w = rect_w / 2
    local half_h = rect_h / 2
    local center_x = rect_x + half_w
    local center_y = rect_y + half_h

    local dx = cx2 - cx1
    local dy = cy2 - cy1

    if dx == 0 and dy == 0 then return center_x, center_y end -- Avoid division by zero if points are same

    local t_edge = math.huge
    local ix, iy = cx2, cy2 -- Default to end point if no intersection found (shouldn't happen with nodes)

    -- Check intersections with vertical edges
    if dx ~= 0 then
        local t_left = (rect_x - cx1) / dx
        local t_right = (rect_x + rect_w - cx1) / dx
        
        if t_left >= 0 and t_left <= 1 then
            local intersect_y = cy1 + t_left * dy
            if intersect_y >= rect_y and intersect_y <= rect_y + rect_h then
                if t_left < t_edge then t_edge = t_left end
            end
        end
        if t_right >= 0 and t_right <= 1 then
            local intersect_y = cy1 + t_right * dy
            if intersect_y >= rect_y and intersect_y <= rect_y + rect_h then
                 if t_right < t_edge then t_edge = t_right end
            end
        end
    end

    -- Check intersections with horizontal edges
    if dy ~= 0 then
        local t_top = (rect_y - cy1) / dy
        local t_bottom = (rect_y + rect_h - cy1) / dy

        if t_top >= 0 and t_top <= 1 then
            local intersect_x = cx1 + t_top * dx
            if intersect_x >= rect_x and intersect_x <= rect_x + rect_w then
                 if t_top < t_edge then t_edge = t_top end
            end
        end
        if t_bottom >= 0 and t_bottom <= 1 then
            local intersect_x = cx1 + t_bottom * dx
            if intersect_x >= rect_x and intersect_x <= rect_x + rect_w then
                if t_bottom < t_edge then t_edge = t_bottom end
            end
        end
    end

    -- Calculate the actual intersection point using the smallest valid t
    if t_edge ~= math.huge and t_edge > 1e-6 then -- Use a small epsilon to avoid issues at start point
       ix = cx1 + t_edge * dx
       iy = cy1 + t_edge * dy
    else
       -- Fallback if something went wrong or line starts inside rect (should connect center to center in that case?)
       -- For this use case, connecting to the actual center is probably fine as a fallback
       ix, iy = center_x, center_y 
    end
    
    return ix, iy
end


-- Helper function to draw an arrow between node boundaries
-- Handles color, single/double headed arrows, and MATERIALIZING line effect
local function draw_arrow(node1, node2, node_w, node_h, color, is_double, pulse_progress)
    local cx1, cy1 = node1.x + node_w / 2, node1.y + node_h / 2
    local cx2, cy2 = node2.x + node_w / 2, node2.y + node_h / 2

    -- Calculate FINAL start and end points on the boundaries
    local final_start_x, final_start_y = get_rect_line_intersection(cx2, cy2, cx1, cy1, node1.x, node1.y, node_w, node_h)
    local final_end_x, final_end_y = get_rect_line_intersection(cx1, cy1, cx2, cy2, node2.x, node2.y, node_w, node_h)

    -- Determine the lighter background color
    local light_color = gray_color -- Default fallback
    if color == black_color then
        light_color = light_black_color
    elseif color == blue_color then
        light_color = light_blue_color
    end

    -- 1. Draw the faint background line first
    love.graphics.setColor(unpack(light_color))
    love.graphics.setLineWidth(2)
    love.graphics.line(final_start_x, final_start_y, final_end_x, final_end_y)

    -- Calculate line vector
    local dx = final_end_x - final_start_x
    local dy = final_end_y - final_start_y

    -- Calculate CURRENT line segment points based on pulse
    local current_start_x = final_start_x
    local current_start_y = final_start_y
    local current_end_x = final_end_x
    local current_end_y = final_end_y

    if not is_double then
        -- One-way: Line grows from start to end
        current_end_x = final_start_x + dx * pulse_progress
        current_end_y = final_start_y + dy * pulse_progress
    else
        -- Two-way: Line grows start -> end (0 to 0.5), then shrinks end -> start (0.5 to 1)
        if pulse_progress < 0.5 then
            local progress = pulse_progress * 2 -- Scale 0-0.5 to 0-1
            current_end_x = final_start_x + dx * progress
            current_end_y = final_start_y + dy * progress
        else
            local progress = (pulse_progress - 0.5) * 2 -- Scale 0.5-1 to 0-1
            -- Start the line segment from the position corresponding to the return pulse
            current_start_x = final_start_x + dx * (1.0 - progress) 
            current_start_y = final_start_y + dy * (1.0 - progress)
            current_end_x = final_end_x -- Line always goes to the actual end point in this phase
            current_end_y = final_end_y
            -- Alternative: Draw from start to the receding point?
            -- current_end_x = final_start_x + dx * (1.0 - progress)
            -- current_end_y = final_start_y + dy * (1.0 - progress)
            -- Let's stick to the first interpretation (grow out, shrink back by moving start point)
        end
    end
    
    -- 2. Draw the current (materializing) line segment on top
    love.graphics.setColor(unpack(color or gray_color))
    love.graphics.setLineWidth(2)
    -- Check if start and end are practically the same to avoid drawing a zero-length line
    if math.abs(current_end_x - current_start_x) > 0.1 or math.abs(current_end_y - current_start_y) > 0.1 then
        love.graphics.line(current_start_x, current_start_y, current_end_x, current_end_y)
    end

    -- Draw FINAL arrowheads (always visible for context)
    local angle = math.atan2(final_end_y - final_start_y, final_end_x - final_start_x)
    local arrow_len = 10
    local arrow_angle = math.pi / 6 -- 30 degrees

    local ax1 = final_end_x - arrow_len * math.cos(angle - arrow_angle)
    local ay1 = final_end_y - arrow_len * math.sin(angle - arrow_angle)
    local ax2 = final_end_x - arrow_len * math.cos(angle + arrow_angle)
    local ay2 = final_end_y - arrow_len * math.sin(angle + arrow_angle)
    love.graphics.line(final_end_x, final_end_y, ax1, ay1)
    love.graphics.line(final_end_x, final_end_y, ax2, ay2)

    if is_double then
        local back_angle = math.atan2(final_start_y - final_end_y, final_start_x - final_end_x)
        local bax1 = final_start_x - arrow_len * math.cos(back_angle - arrow_angle)
        local bay1 = final_start_y - arrow_len * math.sin(back_angle - arrow_angle)
        local bax2 = final_start_x - arrow_len * math.cos(back_angle + arrow_angle)
        local bay2 = final_start_y - arrow_len * math.sin(back_angle + arrow_angle)
        love.graphics.line(final_start_x, final_start_y, bax1, bay1)
        love.graphics.line(final_start_x, final_start_y, bax2, bay2)
    end
    
    -- No pulse dot needed anymore

    love.graphics.setLineWidth(1)
    love.graphics.setColor(unpack(gray_color)) -- Reset color
end

-- Helper function to draw the key/legend box
local function draw_key_box(x, y, w, h)
    local padding = 10
    local line_h = 25
    local arrow_length = 40
    love.graphics.setColor(0.9, 0.9, 0.9, 0.8) -- Light gray background
    love.graphics.rectangle("fill", x, y, w, h, 5, 5)
    love.graphics.setColor(unpack(gray_color))
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, w, h, 5, 5)

    love.graphics.printf("Key:", x + padding, y + padding / 2, w - 2 * padding, "left")

    local current_y = y + padding + line_h
    local arrow_x_start = x + padding
    local arrow_x_end = arrow_x_start + arrow_length
    local label_x = arrow_x_end + padding

    -- Draw one-way arrow example
    love.graphics.setColor(unpack(black_color))
    love.graphics.setLineWidth(2)
    love.graphics.line(arrow_x_start, current_y, arrow_x_end, current_y)
    local angle = 0 -- Pointing right
    local arrow_len = 10
    local arrow_angle = math.pi / 6
    local ax1 = arrow_x_end - arrow_len * math.cos(angle - arrow_angle)
    local ay1 = current_y - arrow_len * math.sin(angle - arrow_angle)
    local ax2 = arrow_x_end - arrow_len * math.cos(angle + arrow_angle)
    local ay2 = current_y - arrow_len * math.sin(angle + arrow_angle)
    love.graphics.line(arrow_x_end, current_y, ax1, ay1)
    love.graphics.line(arrow_x_end, current_y, ax2, ay2)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(unpack(gray_color))
    love.graphics.print("One-Way Influence", label_x, current_y - 8)

    current_y = current_y + line_h

    -- Draw two-way arrow example
    love.graphics.setColor(unpack(blue_color))
    love.graphics.setLineWidth(2)
    love.graphics.line(arrow_x_start, current_y, arrow_x_end, current_y)
    -- Arrowhead 1 (right)
    ax1 = arrow_x_end - arrow_len * math.cos(angle - arrow_angle)
    ay1 = current_y - arrow_len * math.sin(angle - arrow_angle)
    ax2 = arrow_x_end - arrow_len * math.cos(angle + arrow_angle)
    ay2 = current_y - arrow_len * math.sin(angle + arrow_angle)
    love.graphics.line(arrow_x_end, current_y, ax1, ay1)
    love.graphics.line(arrow_x_end, current_y, ax2, ay2)
    -- Arrowhead 2 (left)
    local back_angle = math.pi
    local bax1 = arrow_x_start - arrow_len * math.cos(back_angle - arrow_angle)
    local bay1 = current_y - arrow_len * math.sin(back_angle - arrow_angle)
    local bax2 = arrow_x_start - arrow_len * math.cos(back_angle + arrow_angle)
    local bay2 = current_y - arrow_len * math.sin(back_angle + arrow_angle)
    love.graphics.line(arrow_x_start, current_y, bax1, bay1)
    love.graphics.line(arrow_x_start, current_y, bax2, bay2)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(unpack(gray_color))
    love.graphics.print("Mutual Influence", label_x, current_y - 8)
end

-- Main draw function for this view
function RelationshipsView.draw()
    local width = love.graphics.getWidth()
    local height = love.graphics.getHeight()

    love.graphics.clear(0.95, 0.95, 0.98, 1) -- Light background
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.printf("Planetary System Relationships", 0, 20, width, "center")

    -- Define node properties
    local node_w, node_h = 140, 40
    local group_padding = 30 -- Padding around nodes within groups
    local node_spacing_y = 60 -- Vertical space between nodes in a group

    -- Define Group areas
    local group_conditions_x = width * 0.1
    local group_conditions_y = height * 0.2
    local group_conditions_h = node_h * 3 + node_spacing_y * 2 + group_padding * 2
    local group_conditions_w = node_w + group_padding * 2

    local group_physical_x = width * 0.5 - (node_w + group_padding * 2)/2 -- Center physical group area approx
    local group_physical_y = height * 0.2
    local group_physical_h = node_h * 3 + node_spacing_y * 2 + group_padding * 2
    local group_physical_w = node_w + group_padding * 2
    
    local group_life_x = width * 0.8 - (node_w + group_padding * 2) / 2
    local group_life_y = height * 0.5 - (node_h + group_padding * 2) / 2
    local group_life_w = node_w + group_padding * 2
    local group_life_h = node_h + group_padding * 2
    
    -- Define node positions relative to their groups
    local nodes = {
        -- Planetary Conditions Group
        Solar_Strength = {x = group_conditions_x + group_padding, y = group_conditions_y + group_padding + (node_h + node_spacing_y) * 2, label = "Solar Strength"}, -- Moved down
        Magnetosphere  = {x = group_conditions_x + group_padding, y = group_conditions_y + group_padding + node_h + node_spacing_y, label = "Magnetosphere"}, -- Stays in middle
        Tectonics      = {x = group_conditions_x + group_padding, y = group_conditions_y + group_padding, label = "Tectonic Activity"}, -- Moved up
        
        -- Physical Systems Group
        Lithosphere    = {x = group_physical_x + group_padding, y = group_physical_y + group_padding, label = "Lithosphere"},
        Atmosphere     = {x = group_physical_x + group_padding, y = group_physical_y + group_padding + node_h + node_spacing_y, label = "Atmosphere"},
        Hydrosphere    = {x = group_physical_x + group_padding, y = group_physical_y + group_padding + (node_h + node_spacing_y) * 2, label = "Hydrosphere"},
        
        -- Biosphere (Separate)
        Biosphere      = {x = group_life_x + group_padding, y = group_life_y + group_padding, label = "Biosphere"}
    }

    -- Draw Group Boxes first (so they are behind nodes/arrows)
    draw_group_box("Planetary Conditions", group_conditions_x, group_conditions_y, group_conditions_w, group_conditions_h)
    draw_group_box("Physical Systems", group_physical_x, group_physical_y, group_physical_w, group_physical_h)
    draw_group_box("Life", group_life_x, group_life_y, group_life_w, group_life_h)

    -- Draw nodes
    for _, node in pairs(nodes) do
        draw_node(node.label, node.x, node.y, node_w, node_h)
    end

    -- Define connections based on the Mermaid chart
    -- Pass node tables, dimensions, COLOR, is_double, and PULSE_PROGRESS flag to arrow function
    
    -- One-way (Black)
    draw_arrow(nodes.Solar_Strength, nodes.Atmosphere, node_w, node_h, black_color, false, RelationshipsView.pulse_progress)
    draw_arrow(nodes.Solar_Strength, nodes.Hydrosphere, node_w, node_h, black_color, false, RelationshipsView.pulse_progress)
    draw_arrow(nodes.Magnetosphere, nodes.Atmosphere, node_w, node_h, black_color, false, RelationshipsView.pulse_progress)
    draw_arrow(nodes.Tectonics, nodes.Lithosphere, node_w, node_h, black_color, false, RelationshipsView.pulse_progress)
    draw_arrow(nodes.Lithosphere, nodes.Atmosphere, node_w, node_h, black_color, false, RelationshipsView.pulse_progress)

    -- Bidirectional / Mutual (Blue)
    draw_arrow(nodes.Lithosphere, nodes.Biosphere, node_w, node_h, blue_color, true, RelationshipsView.pulse_progress)
    draw_arrow(nodes.Atmosphere, nodes.Biosphere, node_w, node_h, blue_color, true, RelationshipsView.pulse_progress)
    draw_arrow(nodes.Atmosphere, nodes.Hydrosphere, node_w, node_h, blue_color, true, RelationshipsView.pulse_progress)
    draw_arrow(nodes.Hydrosphere, nodes.Biosphere, node_w, node_h, blue_color, true, RelationshipsView.pulse_progress)
    
    -- Draw the Key Box (drawn last to be on top)
    local key_w = 200
    local key_h = 80
    local key_x = width - key_w - 20 -- Position bottom right
    local key_y = height - key_h - 40 -- Adjust up slightly from bottom edge
    draw_key_box(key_x, key_y, key_w, key_h)
end

-- Update function for the pulse animation
function RelationshipsView:update(dt)
    -- Increment progress, wrapping around using modulo
    self.pulse_progress = (self.pulse_progress + dt * self.pulse_speed) % 1
end

return RelationshipsView
