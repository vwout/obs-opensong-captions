# obs-opensong-subtitles
A plugin for [OBS](https://obsproject.com/) to show lyrics and other fragments from [OpenSong](https://opensong.org/) slides as subtitles.

This Lua script plugin connects OBS to OpenSong.
It supports visualization of lyrics and texts from slides in a scene using a (GDI) text element.

## Installation
The plugin is a script plugin and utilizes the Lua scripting capabilities of OBS.
To use the plugin, add the file `obs-OpenSongSubtitles.lua` to OBS under *Script* in the *Tools* menu.
The other `.lua` files and the directory `websocket` in this repository are also required, but should not be added as scripts in OBS.

# Credits
This plugin uses a number of libraries:
- [luajitsocket](https://github.com/CapsAdmin/luajitsocket/), a library that implements socket support for LuaJIT, since the Lua socket library is not available in OBS.
- a modified version of [lua-resty-websocket](https://github.com/openresty/lua-resty-websocket); only the client of this library is used, without the dependency on ngx_lua, ported to use `luajitsocket`. 
