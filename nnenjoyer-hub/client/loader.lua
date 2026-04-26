local chunkPaths = {
    "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/loader_parts_v2/part01.lua.txt",
    "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/loader_parts_v2/part02.lua.txt"
}

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

local function insertLocked2Route(source)
    if string.find(source, "109883052223750", 1, true) then
        return source
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
        url = "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/games/locked_2.lua"
    }
}]]

    local startIndex, endIndex = string.find(source, oldText, 1, true)
    if not startIndex then
        error("Loader patch failed: GAME_LOADERS block")
    end

    return source:sub(1, startIndex - 1) .. newText .. source:sub(endIndex + 1)
end

local parts = {}
for index, url in ipairs(chunkPaths) do
    parts[index] = downloadText(url)
end

local combinedSource = insertLocked2Route(table.concat(parts))
local compiled, compileError = loadstring(combinedSource, "@loader_impl_v2")
if not compiled then
    error(compileError)
end

return compiled()
