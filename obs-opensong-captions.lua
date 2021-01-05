obs = obslua
OpenSong = require("opensong-client")

plugin_info = {
    name = "OpenSong captions",
    version = "0.2",
    url = "https://github.com/vwout/obs-opensong-captions",
    description = "Show lyrics and other text fragments from OpenSong slides in a scene as caption.",
    author = "vwout"
}

plugin_settings = {}
plugin_data = {}
plugin_data.debug = false
plugin_data.shutdown = false
plugin_data.opensong = nil
plugin_data.title = ""
plugin_data.slide_type = ""
plugin_data.linesets = {}
plugin_data.lineset_active = 0
plugin_data.captions_visible = true


local function log(fmt, ...)
    if plugin_data.debug then
        local info = debug.getinfo(2, "nl")
        local func = info.name or "?"
        local line = info.currentline
        print(string.format("%s (%d): %s", func, line, string.format(fmt, unpack(arg or {...}))))
    end
end

local function opensong_connect(settings)
    if plugin_data.opensong == nil then
        local host = obs.obs_data_get_string(settings, "opensong_address")
        local port = obs.obs_data_get_int(settings, "opensong_port")

        if host and host ~= "" and port and port > 0 then
            local uri = string.format("ws://%s:%d/ws", host, port)
            local connection, err = OpenSong.Connect(uri)
            if not connection then
                log("Connection to OpenSong failed: %s", err)
            else
                plugin_data.shutdown = false
                plugin_data.opensong = connection

                --plugin_data.title = ""
                --plugin_data.linesets = { "" }
                plugin_data.lineset_active = 1

                obs.timer_add(opensong_update_timer, 100)
            end
        end
    end
end

local function opensong_disconnect()
    plugin_data.shutdown = true
    if plugin_data.opensong ~= nil then
        plugin_data.opensong:close()
        plugin_data.opensong = nil
    end
end

local function opensong_partition_lines(lines)
    local captions_max_lines = obs.obs_data_get_int(plugin_settings, "captions_max_lines")
    local captions_max_characters = obs.obs_data_get_int(plugin_settings, "captions_max_characters")

    plugin_data.linesets = {}

    local lineset = ""
    local linecount = 0
    for i,line in pairs(lines) do
        local append = false
        if linecount < captions_max_lines then
            if #lineset + #line < captions_max_characters then
                if #lineset > 0 then
                    lineset = lineset .. "\n"
                end
                lineset = lineset .. line
                linecount = linecount + 1
                append = true
            end
        end

        if not append then
            if #lineset > 0 then
                log("Append lineset: (%d lines, %d chars)\n***\n%s\n***", linecount, #lineset, lineset)
                table.insert(plugin_data.linesets, lineset)
            end

            if (line ~= nil) and (line ~= "") then
                local linelen = string.len(line)
                if linelen > captions_max_characters then
				    local reverse_line = line:reverse()
					if reverse_line ~= nil then
						local pos = reverse_line:find("[.,;:]", linelen - captions_max_characters)
                        if (pos ~= nil) and (pos > 1) then
                            pos = pos - 1
						    local part = line:sub(1, linelen - pos)
						    local remainder = line:sub(linelen - pos+1)
						    remainder = remainder:match("^%s*(.-)%s*$")
						    line = part

						    if #remainder > 0 then
							    table.insert(lines, i+1, remainder)
                            end
                        end
					end
                end

                lineset = line
                linecount = 1
            end
        end
    end

    if #lineset > 0 then
        log("Append lineset: (%d lines, %d chars)\n***\n%s\n***", linecount, #lineset, lineset)
        table.insert(plugin_data.linesets, lineset)
    end
end

local function backgrounds_set_enabled(captions_enabled)
    local background_song_name = obs.obs_data_get_string(plugin_settings, "background_song_source")
    local background_scripture_name = obs.obs_data_get_string(plugin_settings, "background_scripture_source")
    local background_custom_name = obs.obs_data_get_string(plugin_settings, "background_custom_source")

    local background_song_source = obs.obs_get_source_by_name(background_song_name)
    if background_song_source ~= nil then
        obs.obs_source_set_enabled(background_song_source, captions_enabled and
                                                           ((plugin_data.slide_type == "song") or
                                                            ((background_song_name == background_scripture_name) and plugin_data.slide_type == "scripture") or
                                                            ((background_song_name == background_custom_name) and plugin_data.slide_type == "custom")))
    end

    if background_scripture_name ~= background_song_name then
        local background_scripture_source = obs.obs_get_source_by_name(background_scripture_name)
        if background_scripture_source ~= nil then
            obs.obs_source_set_enabled(background_scripture_source, captions_enabled and
                                                                    ((plugin_data.slide_type == "scripture") or
                                                                     ((background_scripture_name == background_custom_name) and plugin_data.slide_type == "custom")))
        end
        obs.obs_source_release(background_scripture_source)
    end


    if (background_custom_name ~= background_song_name) and (background_custom_name ~= background_scripture_name) then
        local background_custom_source = obs.obs_get_source_by_name(background_custom_name)
        if background_custom_source ~= nil then
            obs.obs_source_set_enabled(background_custom_source, captions_enabled and
                                                                 (plugin_data.slide_type == "custom"))
        end
        obs.obs_source_release(background_custom_source)
    end

    obs.obs_source_release(background_song_source)
end

local function show_slide_captions(slide_type)
    local show_slide_song = obs.obs_data_get_bool(plugin_settings, "slide_song")
    local show_slide_scripture = obs.obs_data_get_bool(plugin_settings, "slide_scripture")
    local show_slide_custom = obs.obs_data_get_bool(plugin_settings, "slide_custom")

    local show_captions = false
    if slide_type == "song" and show_slide_song then
        show_captions = true
    elseif slide_type == "scripture" and show_slide_scripture then
        show_captions = true
    elseif slide_type == "custom" and show_slide_custom then
        show_captions = true
    end

    return show_captions
end

local function set_text_source_text(text_name, title_text)
    local text_source = obs.obs_get_source_by_name(text_name)
    if text_source ~= nil then
        local data = obs.obs_source_get_settings(text_source)
        obs.obs_data_set_string(data, "text", title_text)
        obs.obs_source_update(text_source, data)
        obs.obs_data_release(data)
        obs.obs_source_release(text_source)
    end
end

local function update_captions()
    if show_slide_captions(plugin_data.slide_type) then
        if plugin_data.lineset_active > 0 and plugin_data.lineset_active <= #plugin_data.linesets then
            local title_source_name = obs.obs_data_get_string(plugin_settings, "title_source")
            set_text_source_text(title_source_name, plugin_data.title)
            local caption_source_name = obs.obs_data_get_string(plugin_settings, "caption_source")
            set_text_source_text(caption_source_name, plugin_data.linesets[plugin_data.lineset_active])
            backgrounds_set_enabled(plugin_data.captions_visible)
        end
    end
end

function cb_show_captions_previous(pressed)
    if pressed then
        if plugin_data.opensong ~= nil then
            log("cb_show_captions_previous")
            if plugin_data.lineset_active > 1 then
                plugin_data.lineset_active = plugin_data.lineset_active - 1
            end
            update_captions()
        else
            opensong_connect(plugin_settings)
        end
    end
end

function cb_show_captions_next(pressed)
    if pressed then
        if plugin_data.opensong ~= nil then
            log("cb_show_captions_next")
            if plugin_data.lineset_active < #plugin_data.linesets then
                plugin_data.lineset_active = plugin_data.lineset_active + 1
            end
            update_captions()
        else
            opensong_connect(plugin_settings)
        end
    end
end

function cb_show_captions_toggle(pressed)
    if pressed then
        local title_source_name = obs.obs_data_get_string(plugin_settings, "title_source")
        local caption_source_name = obs.obs_data_get_string(plugin_settings, "caption_source")
        local background_song_name = obs.obs_data_get_string(plugin_settings, "background_song_source")
        local background_scripture_name = obs.obs_data_get_string(plugin_settings, "background_scripture_source")
        local background_custom_name = obs.obs_data_get_string(plugin_settings, "background_custom_source")

        local title_source = obs.obs_get_source_by_name(title_source_name)
        local caption_source = obs.obs_get_source_by_name(caption_source_name)
        local background_song_source = obs.obs_get_source_by_name(background_song_name)
        local background_scripture_source = obs.obs_get_source_by_name(background_scripture_name)
        local background_custom_source = obs.obs_get_source_by_name(background_custom_name)

        local captions_enabled = obs.obs_source_enabled(title_source) or
                                 obs.obs_source_enabled(caption_source) or
                                 obs.obs_source_enabled(background_song_source) or
                                 obs.obs_source_enabled(background_scripture_source) or
                                 obs.obs_source_enabled(background_custom_source)
        log("cb_show_captions_toggle %s title (%s) caption (%s)", captions_enabled and "Disabled" or "Enabled", title_source_name, caption_source_name)

        plugin_data.captions_visible = not captions_enabled
        if plugin_data.captions_visible then
            opensong_connect(plugin_settings)
        else
            opensong_disconnect()
            set_text_source_text(title_source_name, "")
            set_text_source_text(caption_source_name, "")
        end

        obs.obs_source_set_enabled(title_source, plugin_data.captions_visible)
        obs.obs_source_set_enabled(caption_source, plugin_data.captions_visible)
        backgrounds_set_enabled(plugin_data.captions_visible)

        obs.obs_source_release(title_source)
        obs.obs_source_release(caption_source)
        obs.obs_source_release(background_song_source)
        obs.obs_source_release(background_scripture_source)
        obs.obs_source_release(background_custom_source)
    end
end

function opensong_update_timer()
    if not plugin_data.shutdown then
        if plugin_data.opensong ~= nil then
            if plugin_data.opensong.is_connected() then
                if plugin_data.opensong:update() then
                    if plugin_data.opensong.slide then
						if show_slide_captions(plugin_data.opensong.slide.type) then
                            plugin_data.slide_type = plugin_data.opensong.slide.type
							plugin_data.title = plugin_data.opensong.slide.title
							opensong_partition_lines(plugin_data.opensong.slide.lines)
							plugin_data.lineset_active = 1
							update_captions()
						end
                    end
                end
            else
                log("Connection to OpenSong lost")
                opensong_disconnect()
            end
        else
            opensong_connect(plugin_settings)
        end
    else
        obs.remove_current_callback()
    end
end

plugin_data.hotkeys = {
    { id=nil, name="opensong_caption_previous", description="Show previous OpenSong caption lines", callback=cb_show_captions_previous },
    { id=nil, name="opensong_caption_next", description="Show next OpenSong caption lines", callback=cb_show_captions_next },
    { id=nil, name="opensong_caption_toggle", description="Toggle OpenSong caption visibility", callback=cb_show_captions_toggle },
}

function script_description()
    return "<b>" .. plugin_info.description .. "</b><br>" ..
           "Version: " .. plugin_info.version .. "<br>" ..
           "<a href=\"" .. plugin_info.url .. "\">" .. plugin_info.url .. "</a>"
end

function script_properties()
    local props = obs.obs_properties_create()

    local os_props = obs.obs_properties_create()
    obs.obs_properties_add_text(os_props, "opensong_address", "IP Address", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_int(os_props, "opensong_port", "Port", 1, 65535, 1)
    obs.obs_properties_add_group(props, "opensong", "OpenSong API Server", obs.OBS_GROUP_NORMAL, os_props)

    local type_props = obs.obs_properties_create()
    obs.obs_properties_add_bool(type_props, "slide_song", "Song")
    obs.obs_properties_add_bool(type_props, "slide_scripture", "Scripture")
    obs.obs_properties_add_bool(type_props, "slide_custom", "Custom")
    obs.obs_properties_add_group(props, "slide_types", "Show captions for slides of type:", obs.OBS_GROUP_NORMAL, type_props)

    obs.obs_properties_add_int(props, "captions_max_lines", "Maximum number of lines", 1, 25, 1)
    obs.obs_properties_add_int(props, "captions_max_characters", "Maximum number of characters", 1, 500, 1)

    local title_list = obs.obs_properties_add_list(props, "title_source", "Text Source item for titles", obs.OBS_COMBO_TYPE_EDITABLE , obs.OBS_COMBO_FORMAT_STRING)
    local caption_list = obs.obs_properties_add_list(props, "caption_source", "Text Source item for captions", obs.OBS_COMBO_TYPE_EDITABLE , obs.OBS_COMBO_FORMAT_STRING)
    local background_song_list = obs.obs_properties_add_list(props, "background_song_source", "Background source for song", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    local background_scripture_list = obs.obs_properties_add_list(props, "background_scripture_source", "Background source for scripture", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    local background_custom_list = obs.obs_properties_add_list(props, "background_custom_source", "Background source for custom", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)

    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        for _, source in ipairs(sources) do
            local source_id = obs.obs_source_get_unversioned_id(source)
            local source_name = obs.obs_source_get_name(source)
            --log("script_properties source %s => %s", source_id, source_name)

            obs.obs_property_list_add_string(background_song_list, source_name, source_name)
            obs.obs_property_list_add_string(background_scripture_list, source_name, source_name)
            obs.obs_property_list_add_string(background_custom_list, source_name, source_name)

            if source_id == "text_gdiplus" or source_id == "text_gdiplus_v2" or source_id == "text_ft2_source" then
                obs.obs_property_list_add_string(title_list, source_name, source_name)
                obs.obs_property_list_add_string(caption_list, source_name, source_name)
            end
        end
    end
    obs.source_list_release(sources)

    return props
end

function script_save(settings)
    for _,hotkey in pairs(plugin_data.hotkeys) do
        local a = obs.obs_hotkey_save(hotkey.id)
        obs.obs_data_set_array(settings, hotkey.name .. "_hotkey", a)
        obs.obs_data_array_release(a)
    end
end

function script_update(settings)
    plugin_settings = settings
    opensong_disconnect()
end

function script_defaults(settings)
    obs.obs_data_set_default_int(settings, "opensong_port", OpenSong.default_port)
    obs.obs_data_set_default_bool(settings, "slide_song", true)
    obs.obs_data_set_default_bool(settings, "slide_scripture", true)
    obs.obs_data_set_default_bool(settings, "slide_custom", false)
    obs.obs_data_set_default_int(settings, "captions_max_lines", 2)
    obs.obs_data_set_default_int(settings, "captions_max_characters", 120)
end

function script_load(settings)
    plugin_data.shutdown = false
    for _,hotkey in pairs(plugin_data.hotkeys) do
        hotkey.id = obs.obs_hotkey_register_frontend(hotkey.name, hotkey.description, hotkey.callback)
        local a = obs.obs_data_get_array(settings, hotkey.name .. "_hotkey")
        obs.obs_hotkey_load(hotkey.id, a)
        obs.obs_data_array_release(a)
    end

    local title_source_name = obs.obs_data_get_string(settings, "title_source")
    set_text_source_text(title_source_name, "")
    local caption_source_name = obs.obs_data_get_string(settings, "caption_source")
    set_text_source_text(caption_source_name, "")

    opensong_connect(settings)
end

function script_unload()
    plugin_data.shutdown = true
    opensong_disconnect()
end