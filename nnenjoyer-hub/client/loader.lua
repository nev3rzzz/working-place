local chunkPaths = {
    "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/loader_parts_v2/part01.lua.txt",
    "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/loader_parts_v2/part02.lua.txt"
}

local LOCKED_2_PLACE_ID = "109883052223750"
local LOCKED_2_GAME_ID = "7602095794"
local LOCKED_2_MAIN_MENU_URL = "https://raw.githubusercontent.com/nev3rzzz/working-place/refs/heads/main/locked%202/main_menu.lua"
local LOCKED_2_LEGACY_URL = "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/games/locked_2.lua"

local function downloadText(url)
    local ok, body = pcall(function()
        return game:HttpGet(url)
    end)

    if ok and type(body) == "string" and body ~= "" then
        return body
    end

    local requestFunction = (syn and syn.request) or request or http_request or (http and http.request)
    if not requestFunction then
        error("No request function is available in this executor.")
    end

    local response = requestFunction({
        Url = url,
        Method = "GET"
    })

    local statusCode = tonumber(response.StatusCode or response.Status or response.status_code)
    if statusCode and (statusCode < 200 or statusCode >= 300) then
        error("Failed to download loader chunk: " .. tostring(statusCode))
    end

    local responseBody = response.Body or response.body or response.ResponseBody
    if type(responseBody) ~= "string" or responseBody == "" then
        error("Downloaded an empty loader chunk.")
    end

    return responseBody
end

local function replacePlain(source, oldText, newText, label)
    local startIndex, endIndex = string.find(source, oldText, 1, true)
    if not startIndex then
        if label then
            error("Loader patch failed: " .. label)
        end

        return source, false
    end

    return source:sub(1, startIndex - 1) .. newText .. source:sub(endIndex + 1), true
end

local function insertLocked2Route(source)
    if string.find(source, LOCKED_2_PLACE_ID, 1, true) then
        local patched = replacePlain(source, LOCKED_2_LEGACY_URL, LOCKED_2_MAIN_MENU_URL)
        return patched
    end

    local oldText = [[    [70845479499574] = {
        name = "Bite By Night",
        url = "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/games/bite_by_night.lua"
    }
}]]

    local newText = [[    [70845479499574] = {
        name = "Bite By Night",
        url = "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/games/bite_by_night.lua"
    },
    [109883052223750] = {
        name = "Locked 2",
        url = "https://raw.githubusercontent.com/nev3rzzz/working-place/refs/heads/main/locked%202/main_menu.lua"
    }
}]]

    return replacePlain(source, oldText, newText, "GAME_LOADERS block")
end

local function insertLocked2GameIdRoute(source)
    if string.find(source, "GAME_ID_LOADERS", 1, true) then
        return source
    end

    local gameLoadersEnd = "}\n\nlocal function tryCall"
    local replacement = "}\n\nlocal GAME_ID_LOADERS = {\n    [" .. LOCKED_2_GAME_ID .. "] = GAME_LOADERS[" .. LOCKED_2_PLACE_ID .. "]\n}\n\nlocal function tryCall"
    local patched = replacePlain(source, gameLoadersEnd, replacement, "GAME_ID_LOADERS block")

    local oldRoute = "local route = GAME_LOADERS[tonumber(game.PlaceId)]"
    local newRoute = "local route = GAME_LOADERS[tonumber(game.PlaceId)] or GAME_ID_LOADERS[tonumber(game.GameId)]"
    patched = replacePlain(patched, oldRoute, newRoute, "route resolver")

    local oldUnsupported = "notify(WINDOW_TITLE, \"Unsupported game.\")"
    local newUnsupported = "notify(WINDOW_TITLE, (\"Unsupported game. PlaceId: %s | GameId: %s\"):format(tostring(game.PlaceId), tostring(game.GameId)))"
    patched = replacePlain(patched, oldUnsupported, newUnsupported) or patched

    return patched
end

local parts = {}
for index, url in ipairs(chunkPaths) do
    parts[index] = downloadText(url)
end

local combinedSource = insertLocked2GameIdRoute(insertLocked2Route(table.concat(parts)))
local compiled, compileError = loadstring(combinedSource, "@loader_impl_v2")
if not compiled then
    error(compileError)
end

return compiled()
