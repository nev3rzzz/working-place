return function(context)
    local source = game:HttpGet("https://raw.githubusercontent.com/nev3rzzz/working-place/abdb301f83ccc0e5e7ef12a0179790f0cefe4837/nnenjoyer-hub/client/games/ultra_power.lua")

    local function mustReplace(haystack, oldChunk, newChunk)
        local startIndex, endIndex = haystack:find(oldChunk, 1, true)
        if not startIndex then
            error(("Ultra Power patch failed: %s"):format(oldChunk:match("^[^\n]+") or "unknown chunk"))
        end

        return haystack:sub(1, startIndex - 1) .. newChunk .. haystack:sub(endIndex + 1)
    end

    source = mustReplace(source, [[
    minimizeKeybindControl = tabs.Settings:AddKeybind("MinimizeKeybind", {
        Title = "Minimize Bind",
        Mode = "Toggle",
        Default = "RightAlt",
        ChangedCallback = function(newBind)
            local bindName = typeof(newBind) == "EnumItem" and newBind.Name or tostring(newBind)
            notify("Minimize Bind", "Set to " .. bindName)
        end
    })

    tabs.Settings:AddParagraph({
        Title = "Notes",
        Content = "Minimize now uses Fluent's native keybind system. Auth, backend validation, route dispatching, and duplicate loader code stay in the main loader."
    })
]], [[
    tabs.Settings:AddParagraph({
        Title = "Interface",
        Content = "Minimize Bind: RightAlt"
    })
]])

    local chunk = assert(loadstring(source, "@ultra_power_fixed_right_alt"))
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
