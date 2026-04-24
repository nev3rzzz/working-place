local chunkPaths = {
    "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/games/ultra_power_parts_v2/part01.lua.txt",
    "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/games/ultra_power_parts_v2/part02.lua.txt",
    "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/games/ultra_power_parts_v2/part03.lua.txt",
    "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/games/ultra_power_parts_v2/part04.lua.txt",
    "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/games/ultra_power_parts_v2/part05.lua.txt"
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
        error("Failed to download Ultra Power chunk: " .. tostring(statusCode))
    end

    local responseBody = response.Body or response.body or response.ResponseBody
    if type(responseBody) ~= "string" or responseBody == "" then
        error("Downloaded an empty Ultra Power chunk.")
    end

    return responseBody
end

local function mustReplace(source, oldText, newText, label)
    local startIndex, endIndex = string.find(source, oldText, 1, true)
    if not startIndex then
        error("Ultra Power patch failed: " .. tostring(label))
    end

    return source:sub(1, startIndex - 1) .. newText .. source:sub(endIndex + 1)
end

local parts = {}
for index, url in ipairs(chunkPaths) do
    parts[index] = downloadText(url)
end

local combinedSource = table.concat(parts)

combinedSource = mustReplace(
    combinedSource,
    [[        if trackedWindowAnimating then
            if trackedWindowAnimationStartedAt > 0 and os.clock() - trackedWindowAnimationStartedAt > 0.9 then
                trackedWindowAnimating = false
                trackedWindowAnimationStartedAt = 0
            else
                return false
            end
        end]],
    [[        if trackedWindowAnimating then
            trackedWindowAnimating = false
            trackedWindowAnimationStartedAt = 0

            if trackedWindowFrame then
                trackedWindowFrame.Visible = true
                if trackedWindowShownPosition ~= nil then
                    trackedWindowFrame.Position = trackedWindowShownPosition
                end
            end

            if trackedWindowScale then
                trackedWindowScale.Scale = 1
            end
        end]],
    "trackedWindowAnimating block"
)

combinedSource = mustReplace(
    combinedSource,
    [[            task.spawn(function()
                local toggled = toggleWindowVisibility()
                if not toggled then
                    notify("Minimize Bind", "The interface is busy right now. Try again in a moment.")
                end
            end)]],
    [[            task.spawn(function()
                toggleWindowVisibility()
            end)]],
    "RightAlt minimize handler"
)

local compiled, compileError = loadstring(combinedSource, "@ultra_power_impl_v2")
if not compiled then
    error(compileError)
end

return compiled()