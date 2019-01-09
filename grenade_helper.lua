-- Grenade Helper by ShadyRetard
local THROW_RADIUS = 20;
local WALK_SPEED = 100;
local DRAW_MARKER_DISTANCE = 100;
local GH_ACTION_COOLDOWN = 30;
local GAME_COMMAND_COOLDOWN = 20;

local maps = {}

local GH_WINDOW_ACTIVE = gui.Checkbox(gui.Reference("VISUALS", "MISC", "Assistance"), "GH_WINDOW_ACTIVE", "Grenade Helper", true);
local GH_WINDOW = gui.Window("GH_WINDOW", "Grenade Helper", 200, 200, 450, 175);
local GH_NEW_NADE_GB = gui.Groupbox(GH_WINDOW, "Add grenade throw", 15, 15, 200, 100);
local GH_ENABLE_KEYBINDS = gui.Checkbox(GH_NEW_NADE_GB, "GH_ENABLE_KEYBINDS", "Enable Add Keybinds", false);
local GH_ADD_KB = gui.Keybox(GH_NEW_NADE_GB, "GH_ADD_KB", "Add key", "");
local GH_DEL_KB = gui.Keybox(GH_NEW_NADE_GB, "GH_DEL_KB", "Remove key", "");

local GH_SETTINGS_GB = gui.Groupbox(GH_WINDOW, "Settings", 230, 15, 200, 100);
local GH_VISUALS_DISTANCE_SL = gui.Slider(GH_SETTINGS_GB, "GH_VISUALS_DISTANCE_SL", "Display Distance", 800, 1, 9999);

-- We're misusing the Editbox to store our data in a hacky way
local MY_THROW_DATA = gui.Editbox(GH_WINDOW, "GH_THROW_DATA", "");

local window_show = false;
local window_cb_pressed = true;
local should_load_data = true;
local last_action = globals.TickCount();
local throw_to_add;
local chat_add_step = 1;
local message_to_say;
local my_last_message = globals.TickCount();
local my_last_load = globals.TickCount();
local screen_w, screen_h = 0,0;

local nade_type_mapping = {
    "auto",
    "smokegrenade",
    "flashbang",
    "hegrenade",
    "molotovgrenade";
    "decoy";
}

local throw_type_mapping = {
    "stand",
    "jump",
    "run",
    "crouch",
    "right";
}

local chat_add_messages = {
    "[GH] Welcome to GH Setup. Type 'cancel' at any time to cancel. Please enter the name of the throw (e.g. CT to B site):",
    "[GH] Please enter the throw type (stand / jump / run / crouch / right):"
}

local current_map_name;

function gameEventHandler(event)
    local event_name = event:GetName();
    if (event_name == "player_say" and throw_to_add ~= nil) then
        local self_pid = client.GetLocalPlayerIndex();
        local chat_uid = event:GetInt('userid');
        local chat_pid = client.GetPlayerIndexByUserID(chat_uid);

        if (self_pid ~= chat_pid) then
            return;
        end

        my_last_message = globals.TickCount();

        local say_text = event:GetString('text');

        if (say_text == "cancel") then
            message_to_say = "[GH] Throw cancelled";
            throw_to_add = nil;
            chat_add_step = 0;
            return;
        end

        -- Don't use the bot's messages
        if (string.sub(say_text, 1, 4) == "[GH]") then
            return;
        end

        -- Enter name
        if (chat_add_step == 1) then
            throw_to_add.name = say_text;
        elseif (chat_add_step == 2) then
            if (hasValue(throw_type_mapping, say_text) == false) then
                message_to_say = "[GH] The throw type '" .. say_text .. "' is invalid, please enter one of the following values: stand / jump / run / crouch / right";
                return;
            end

            throw_to_add.type = say_text;
            message_to_say = "[GH] Your throw '" .. throw_to_add.name .. "' - " .. throw_to_add.type .. " has been added.";
            table.insert(maps[current_map_name], throw_to_add);
            throw_to_add = nil;
            local value = convertTableToDataString(maps);
            gui.SetValue("GH_THROW_DATA", value);

            chat_add_step = 0;
            return;
        else
            chat_add_step = 0;
            return;
        end

        chat_add_step = chat_add_step + 1;
        message_to_say = chat_add_messages[chat_add_step];

        return;
    end
end

function drawEventHandler()
    screen_w, screen_h = draw.GetScreenSize();
    showWindow();

    if (my_last_load ~= nil and my_last_load > globals.TickCount()) then
        my_last_load = globals.TickCount();
    end

    if (globals.TickCount() - my_last_load > 150) then
        loadData();
    end

    local active_map_name = engine.GetMapName();

    -- If we don't have an active map, stop
    if (active_map_name == nil or maps == nil) then
        return;
    end

    if (maps[active_map_name] == nil) then
        maps[active_map_name] = {};
    end

    if (current_map_name ~= active_map_name) then
        current_map_name = active_map_name;
    end

    if (maps[current_map_name] == nil) then
        return;
    end

    if (my_last_message ~= nil and my_last_message > globals.TickCount()) then
        my_last_message = globals.TickCount();
    end

    if (message_to_say ~= nil and globals.TickCount() - my_last_message > 60) then
        client.ChatTeamSay(message_to_say);
        message_to_say = nil;
    end

    showNadeThrows();
end

function moveEventHandler(cmd)
    local me = entities.GetLocalPlayer();
    if (current_map_name == nil or maps == nil or maps[current_map_name] == nil or me == nil or not me:IsAlive()) then
        throw_to_add = nil;
        chat_add_step = 1;
        message_to_say = nil;
        return;
    end

    if (throw_to_add ~= nil) then
        return;
    end


    local add_keybind = GH_ADD_KB:GetValue();
    local del_keybind = GH_DEL_KB:GetValue();
    if (GH_ENABLE_KEYBINDS:GetValue() == false or (add_keybind == 0 and del_keybind == 0)) then
        return;
    end

    if (last_action ~= nil and last_action > globals.TickCount()) then
        last_action = globals.TickCount();
    end

    if (add_keybind ~= 0 and input.IsButtonDown(add_keybind) and globals.TickCount() - last_action > GH_ACTION_COOLDOWN) then
        last_action = globals.TickCount();
        return doAdd(cmd);
    end

    local closest_throw, distance = getClosestThrow(maps[current_map_name], me, cmd);
    if (closest_throw == nil or distance > THROW_RADIUS) then
        return;
    end

    if (del_keybind ~= 0 and input.IsButtonDown(del_keybind) and globals.TickCount() - last_action > GH_ACTION_COOLDOWN) then
        last_action = globals.TickCount();
        return doDel(closest_throw);
    end
end

function showWindow()
    window_show = GH_WINDOW_ACTIVE:GetValue();

    if input.IsButtonPressed(gui.GetValue("msc_menutoggle")) then
        window_cb_pressed = not window_cb_pressed;
    end

    if (window_show and window_cb_pressed) then
        GH_WINDOW:SetActive(1);
    else
        GH_WINDOW:SetActive(0);
    end
end

function loadData()
    local throw_data = gui.GetValue("GH_THROW_DATA");
    if (throw_data ~= nil and throw_data ~= "") then
        maps = parseStringifiedTable(throw_data);
    end
end

function doAdd(cmd)
    local me = entities.GetLocalPlayer();
    if (current_map_name == nil or maps[current_map_name] == nil or me == nil or not me:IsAlive()) then
        return;
    end

    local my_x, my_y, my_z = me:GetAbsOrigin();
    local ax, ay, az = cmd:GetViewAngles();

    local nade_type = getWeaponName(me);
    if (nade_type ~= nil and nade_type ~= "smokegrenade" and nade_type ~= "flashbang" and nade_type ~= "molotovgrenade" and nade_type ~= "hegrenade" and nade_type ~= "decoy") then
        return;
    end

    local new_throw = {
        name = "",
        type = "not_set",
        nade = nade_type,
        pos = {
            x = my_x,
            y = my_y,
            z = my_z
        },
        ax = ax,
        ay = ay
    };

    throw_to_add = new_throw;
    chat_add_step = 1;
    message_to_say = chat_add_messages[chat_add_step];
end

function doDel(throw)
    if (current_map_name == nil or maps[current_map_name] == nil) then
        return;
    end

    removeFirstThrow(throw);

    local value = convertTableToDataString(maps);
    gui.SetValue("GH_THROW_DATA", value);
end

function showNadeThrows()
    local me = entities:GetLocalPlayer();

    if (me == nil) then
        return;
    end

    local weapon_name = getWeaponName(me);

    if (weapon_name ~= nil and weapon_name ~= "smokegrenade" and weapon_name ~= "flashbang" and weapon_name ~= "molotovgrenade" and weapon_name ~= "hegrenade" and weapon_name ~= "decoy") then
        return;
    end

    local throws_to_show, within_distance = getActiveThrows(maps[current_map_name], me, weapon_name);

    for i=1, #throws_to_show do
        local throw = throws_to_show[i];
        local cx, cy = client.WorldToScreen(throw.pos.x, throw.pos.y, throw.pos.z);
        local text_color_r, text_color_g, text_color_b, text_color_a = gui.GetValue('clr_grenadetracer_text');
        local line_color_r, line_color_g, line_color_b, line_color_a = gui.GetValue('clr_grenadetracer_line');
        local bounce_color_r, bounce_color_g, bounce_color_b, bounce_color_a = gui.GetValue('clr_grenadetracer_bounce');
        local final_color_r, final_color_g, final_color_b, final_color_a = gui.GetValue('clr_grenadetracer_final');

        if (within_distance) then
            local z_offset = 64;
            if (throw.type == "crouch") then
                z_offset = 46;
            end

            local t_x, t_y, t_z = getThrowPosition(throw.pos.x, throw.pos.y, throw.pos.z, throw.ax, throw.ay, z_offset);
            local draw_x, draw_y = client.WorldToScreen(t_x, t_y, t_z);
            if (draw_x ~= nil and draw_y ~= nil) then
                draw.Color(final_color_r, final_color_g, final_color_b, final_color_a);
                draw.RoundedRect(draw_x - 10, draw_y - 10, draw_x + 10, draw_y + 10);

                -- Draw a line from the center of our screen to the throw position
                draw.Color(line_color_r, line_color_g, line_color_b, line_color_a);
                draw.Line(draw_x, draw_y, screen_w / 2, screen_h / 2);

                draw.Color(text_color_r, text_color_g, text_color_b, text_color_a);
                local text_size_w, text_size_h = draw.GetTextSize(throw.name);
                draw.Text(draw_x - text_size_w / 2, draw_y - 30 - text_size_h / 2, throw.name);
                text_size_w, text_size_h = draw.GetTextSize(throw.type);
                draw.Text(draw_x - text_size_w / 2, draw_y - 20 - text_size_h / 2, throw.type);
            end
        end

        local ulx, uly = client.WorldToScreen(throw.pos.x - THROW_RADIUS / 2, throw.pos.y - THROW_RADIUS / 2, throw.pos.z);
        local blx, bly = client.WorldToScreen(throw.pos.x - THROW_RADIUS / 2, throw.pos.y + THROW_RADIUS / 2, throw.pos.z);
        local urx, ury = client.WorldToScreen(throw.pos.x + THROW_RADIUS / 2, throw.pos.y - THROW_RADIUS / 2, throw.pos.z);
        local brx, bry = client.WorldToScreen(throw.pos.x + THROW_RADIUS / 2, throw.pos.y + THROW_RADIUS / 2, throw.pos.z);

        if (cx ~= nil and cy ~= nil and ulx ~= nil and uly ~= nil and blx ~= nil and bly ~= nil and urx ~= nil and ury ~= nil and brx ~= nil and bry ~= nil) then
            local alpha = 0;
            if (throw.distance < GH_VISUALS_DISTANCE_SL:GetValue()) then
                alpha = (1 - throw.distance / GH_VISUALS_DISTANCE_SL:GetValue()) * text_color_a;
            end

            if (throw.name ~= nil) then
                local text_size_w, text_size_h = draw.GetTextSize(throw.name);
                draw.Color(text_color_r, text_color_g, text_color_b, alpha);
                draw.Text(cx - text_size_w / 2, cy - 20 - text_size_h / 2, throw.name);
            end

            -- Show radius as green when in distance, blue otherwise
            if (within_distance) then
                draw.Color(final_color_r, final_color_g, final_color_b, final_color_a);
            else
                draw.Color(bounce_color_r, bounce_color_g, bounce_color_b, alpha);
            end

            -- Top left to rest
            draw.Line(ulx, uly, blx, bly);
            draw.Line(ulx, uly, urx, ury);
            draw.Line(ulx, uly, brx, bry);

            -- Bottom right to rest
            draw.Line(brx, bry, blx, bly);
            draw.Line(brx, bry, urx, ury);

            -- Diagonal
            draw.Line(blx, bly, urx, ury);
        end
    end
end

function getThrowPosition(pos_x, pos_y, pos_z, ax, ay, z_offset)
    return pos_x - DRAW_MARKER_DISTANCE * math.cos(math.rad(ay + 180)), pos_y - DRAW_MARKER_DISTANCE * math.sin(math.rad(ay + 180)), pos_z - DRAW_MARKER_DISTANCE * math.tan(math.rad(ax)) + z_offset;
end

function getWeaponName(me)
    local my_weapon = me:GetPropEntity("m_hActiveWeapon");
    if (my_weapon == nil) then
        return nil;
    end

    local weapon_name = my_weapon:GetClass();
    weapon_name = weapon_name:gsub("CWeapon", "");
    weapon_name = weapon_name:lower();

    if (weapon_name:sub(1, 1) == "c") then
        weapon_name = weapon_name:sub(2)
    end

    return weapon_name;
end

function getDistanceToTarget(my_x, my_y, my_z, t_x, t_y, t_z)
    local dx = my_x - t_x;
    local dy = my_y - t_y;
    local dz = my_z - t_z;
    return math.sqrt(dx^2 + dy^2 + dz^2);
end

function getActiveThrows(map, me, nade_name)
    local throws = {};
    local throws_in_distance = {};
    -- Determine if any are within range, we should only show those if that's the case
    for i=1, #map do
        local throw = map[i];
        if (throw ~= nil and throw.nade == nade_name) then
            local my_x, my_y, my_z = me:GetAbsOrigin();
            local distance = getDistanceToTarget(my_x, my_y, throw.pos.z, throw.pos.x, throw.pos.y, throw.pos.z);
            throw.distance = distance;
            if (distance < THROW_RADIUS) then
                table.insert(throws_in_distance, throw);
            else
                table.insert(throws, throw);
            end
        end
    end

    if (#throws_in_distance > 0) then
        return throws_in_distance, true;
    end

    return throws, false;
end

function getClosestThrow(map, me, cmd)
    local closest_throw;
    local closest_distance;
    local closest_distance_from_center;
    local my_x, my_y, my_z = me:GetAbsOrigin();
    for i = 1, #map do
        local throw = map[i];
        local distance = getDistanceToTarget(my_x, my_y, throw.pos.z, throw.pos.x, throw.pos.y, throw.pos.z);
        local z_offset = 64;
        if (throw.type == "crouch") then
            z_offset = 46;
        end
        local pos_x, pos_y, pos_z = getThrowPosition(throw.pos.x, throw.pos.y, throw.pos.z, throw.ax, throw.ay, z_offset);
        local draw_x, draw_y = client.WorldToScreen(pos_x, pos_y, pos_z);
        local distance_from_center;

        if (draw_x ~= nil and draw_y ~= nil) then
            distance_from_center = math.abs(screen_w / 2 - draw_x + screen_h / 2 - draw_y);
        end

        if (
            closest_distance == nil
            or (
                distance <= THROW_RADIUS
                and (
                    closest_distance_from_center == nil
                    or (closest_distance_from_center ~= nil and distance_from_center ~= nil and distance_from_center < closest_distance_from_center)
                )
            )
            or (
                (closest_distance_from_center == nil and distance < closest_distance)
            )
        ) then
            closest_throw = throw;
            closest_distance = distance;
            closest_distance_from_center = distance_from_center;
        end
    end

    return closest_throw, closest_distance;
end

function parseStringifiedTable(stringified_table)
    local new_map = {};
    for i in string.gmatch(stringified_table, "([^;]*);") do
        local matches = {};
        string.gmatch(i, "(.*),")

        for word in string.gmatch(i, "([^,]*)") do
            table.insert(matches, word);
        end

        local map_name = matches[1];
        if new_map[map_name] == nil then
            new_map[map_name] = {};
        end

        table.insert(new_map[map_name], {
            name = matches[2],
            type = matches[3],
            nade = matches[4],
            pos = {
                x = tonumber(matches[5]),
                y = tonumber(matches[6]),
                z = tonumber(matches[7])
            },
            ax = tonumber(matches[8]),
            ay = tonumber(matches[9]);
        });
    end
    return new_map;
end

function convertTableToDataString(object)
    local converted = "";
    for map_name, map in pairs(object) do
        for i, throw in ipairs(map) do
            if (throw ~= nil) then
                converted = converted..map_name.. ','..throw.name..','..throw.type..','..throw.nade..','..throw.pos.x..','..throw.pos.y..','..throw.pos.z..','..throw.ax..','..throw.ay..';'
            end
        end
    end

    return converted;
end

function hasValue(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

function removeFirstThrow(throw)
    for i, v in ipairs(maps[current_map_name]) do
        if (v.name == throw.name and v.pos.x == throw.pos.x and v.pos.y == throw.pos.y and v.pos.z == throw.pos.z) then
            return table.remove(maps[current_map_name], i);
        end
    end
end

client.AllowListener("player_say");
callbacks.Register("FireGameEvent", "GH_EVENT", gameEventHandler);
callbacks.Register("CreateMove", "GH_MOVE", moveEventHandler);
callbacks.Register("Draw", "GH_DRAW", drawEventHandler);