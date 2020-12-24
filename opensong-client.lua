local client = require("websocket.client")

local OpenSong = {}

OpenSong.default_port = 8082

function OpenSong.Connect(uri)
    local connection = {
        ws  = nil,
        uri = uri,
        slide = {}
    }

    connection.slide.identifier = nil
    connection.slide.type = nil
    connection.slide.title = nil
    connection.slide.lines = {}

    local ws, err = client:new()
    if not ws then
        return nil, "Unable to create WebSocket: " .. err or "?"
    else
        local ok, err = ws:connect(uri)
        if not ok then
            return nil, "Unable to connecto to " .. uri .. ": " .. err or "?"
        end

        local bytes, err = ws:send_text("/ws/subscribe/presentation")
        if not bytes then
            ws.close()
            return nil, "Subscribe failed: " .. err or "?"
        end

        connection.ws = ws
    end

    function connection.close()
        local ws = connection.ws
        if ws ~= nil then
            ws:close()
        end
    end

    function connection.update()
        local updated  = false

        local ws = connection.ws
        local data, typ, err = ws:recv_frame()
        if data then
            if data:sub(1, 5) == "<?xml" then
                --print(data)
                local action = data:match("action=\"(%a+)\"")
                if action == "status" then
                    local itemnumber = tonumber(data:match("<slide itemnumber=\"(%d+)\">"))
                    if itemnumber then
                        ws:send_text(string.format("/presentation/slide/%d", itemnumber))
                    end
                elseif action == "slide" then
                    local identifier = tonumber(data:match("identifier=\"(%d+)\""))
                    local slide_type = data:match("type=\"([^\"]+)\"")
                    local title = data:match("<title>([^<]+)</title>")
                    local lines = data:match("<body>([^<]+)</body>")

                    --print(slide_type)
                    --print(title)
                    --print(lines)
                    if identifier and title and lines then
                        connection.slide.identifier = identifier
                        connection.slide.type = slide_type
                        connection.slide.title = title
                        connection.slide.lines = {}
                        for str in lines:gmatch("([^\r\n]+)") do
                            str = str:match("^%s*(.-)%s*$")
                            if str ~= "" then
                                table.insert(connection.slide.lines, str)
                            end
                        end
                        updated = true
                    end
                end
            end
        end

        return updated
    end

    return connection
end

return OpenSong
