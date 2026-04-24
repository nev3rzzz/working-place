return function(context)
    local requestFunction = (syn and syn.request) or request or http_request or (http and http.request)
    local partUrls = {
        "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/games/bite_by_night_parts_v2/part01.lua.txt",
        "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/games/bite_by_night_parts_v2/part02.lua.txt",
        "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/games/bite_by_night_parts_v2/part03.lua.txt",
        "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/games/bite_by_night_parts_v2/part04.lua.txt"
    }

    local function downloadText(url)
        local ok, body = pcall(function()
            return game:HttpGet(url)
        end)

        if ok and type(body) == "string" and body ~= "" then
            return body
        end

        if not requestFunction then
            return nil
        end

        local okResponse, response = pcall(function()
            return requestFunction({
                Url = url,
                Method = "GET"
            })
        end)

        if not okResponse or not response then
            return nil
        end

        local statusCode = tonumber(response.StatusCode or response.Status or response.status_code)
        if statusCode and (statusCode < 200 or statusCode >= 300) then
            return nil
        end

        local responseBody = response.Body or response.body or response.ResponseBody
        if type(responseBody) == "string" and responseBody ~= "" then
            return responseBody
        end

        return nil
    end

    local parts = table.create(#partUrls)
    for index, url in ipairs(partUrls) do
        local source = downloadText(url)
        if type(source) ~= "string" or source == "" then
            error(("Failed to download Bite By Night v2 chunk %d."):format(index))
        end

        parts[index] = source
    end

    local chunk = assert(loadstring(table.concat(parts), "@bite_by_night_impl_v2"))
    local exported = chunk()

    if type(exported) == "function" then
        return exported(context)
    end

    if type(exported) == "table" then
        if type(exported.run) == "function" then
            return exported.run(context)
        end

        if type(exported.Start) == "function" then
            return exported.Start(context)
        end
    end

    return exported
end
