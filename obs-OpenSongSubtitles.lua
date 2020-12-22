obs = obslua

plugin_info = {
    name = "OpenSong lyric subtitles",
    version = "0.1",
    url = "https://github.com/vwout/obs-opensong-subtitles",
    description = "Show lyrics and other fragments from OpenSong slides in a scene",
    author = "vwout"
}

plugin_settings = {}
plugin_data = {}
plugin_data.debug = true

local function log(fmt, ...)
    if plugin_data.debug then
        local info = debug.getinfo(2, "nl")
        local func = info.name or "?"
        local line = info.currentline
        print(string.format("%s (%d): %s", func, line, string.format(fmt, unpack(arg or {...}))))
    end
end

function opensong_show_lyrics_previous(pressed)
    if pressed then
        log("opensong_show_lyrics_previous")
    end
end

function opensong_show_lyrics_next(pressed)
    if pressed then
        log("opensong_show_lyrics_next")
    end
end

function opensong_show_lyrics_toggle(pressed)
    if pressed then
        local title_name = obs.obs_data_get_string(plugin_settings, "title_source")
        local lyric_name = obs.obs_data_get_string(plugin_settings, "lyric_source")
        local background_name = obs.obs_data_get_string(plugin_settings, "background_source")

        local title_source = obs.obs_get_source_by_name(title_name)
        local lyric_source = obs.obs_get_source_by_name(lyric_name)
        local background_source = obs.obs_get_source_by_name(background_name)

        local lyrics_enabled = obs.obs_source_enabled(title_source) or obs.obs_source_enabled(lyric_source) obs.obs_source_enabled(background_source)
        log("opensong_show_lyrics_toggle %s title (%s) lyric (%s) background (%s)", lyrics_enabled and "Disabled" or "Enabled", title_name, lyric_name, background_name)

        obs.obs_source_set_enabled(title_source, not lyrics_enabled)
        obs.obs_source_set_enabled(lyric_source, not lyrics_enabled)
        obs.obs_source_set_enabled(background_source, not lyrics_enabled)
    end
end

plugin_data.hotkeys = {
    { id=nil, name="opensong_lyric_previous", description="Show previous OpenSong lyric lines", callback=opensong_show_lyrics_previous },
    { id=nil, name="opensong_lyric_next", description="Show next OpenSong lyric lines", callback=opensong_show_lyrics_next },
    { id=nil, name="opensong_lyric_toggle", description="Toggle OpenSong lyric visibility", callback=opensong_show_lyrics_toggle },
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

    local title_list = obs.obs_properties_add_list(props, "title_source", "Text Source item for titles", obs.OBS_COMBO_TYPE_EDITABLE , obs.OBS_COMBO_FORMAT_STRING)
    local lyric_list = obs.obs_properties_add_list(props, "lyric_source", "Text Source item for lyrics", obs.OBS_COMBO_TYPE_EDITABLE , obs.OBS_COMBO_FORMAT_STRING)
    local background_list = obs.obs_properties_add_list(props, "background_source", "Background for lyrics block", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)

    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        for _, source in ipairs(sources) do
            local source_id = obs.obs_source_get_id(source)
            local source_name = obs.obs_source_get_name(source)
            --log("script_properties source %s => %s", source_id, source_name)

            obs.obs_property_list_add_string(background_list, source_name, source_name)

            if source_id == "text_gdiplus" or source_id == "text_gdiplus_v2" or source_id == "text_ft2_source" then
                obs.obs_property_list_add_string(title_list, source_name, source_name)
                obs.obs_property_list_add_string(lyric_list, source_name, source_name)
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
end

function script_load(settings)
    for _,hotkey in pairs(plugin_data.hotkeys) do
        hotkey.id = obs.obs_hotkey_register_frontend(hotkey.name, hotkey.description, hotkey.callback)
        local a = obs.obs_data_get_array(settings, hotkey.name .. "_hotkey")
        obs.obs_hotkey_load(hotkey.id, a)
        obs.obs_data_array_release(a)
    end

    local port = obs.obs_data_get_int(settings, "opensong_port")
    if port == nil or port == 0 then
        obs.obs_data_set_int(settings, "opensong_port", 8082)
    end
end