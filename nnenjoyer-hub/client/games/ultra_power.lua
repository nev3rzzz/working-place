return function(context)
    local source = game:HttpGet("https://raw.githubusercontent.com/nev3rzzz/working-place/abdb301f83ccc0e5e7ef12a0179790f0cefe4837/nnenjoyer-hub/client/games/ultra_power.lua")

    local function mustReplace(haystack, oldChunk, newChunk)
        local startIndex, endIndex = haystack:find(oldChunk, 1, true)
        if not startIndex then
            error("Ultra Power patch failed: " .. oldChunk:match("^[^\n]+") or "unknown chunk")
        end

        return haystack:sub(1, startIndex - 1) .. newChunk .. haystack:sub(endIndex + 1)
    end

    source = mustReplace(source, [[
        Acrylic = false,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.RightAlt
]], [[
        Acrylic = false,
        Theme = "Dark"
]])

    source = mustReplace(source, [[
    local equipFirstToolsBind = nil
    local aimMouseToggleBind = nil
    local pendingBindAction = nil
]], [[
    local equipFirstToolsBind = nil
    local aimMouseToggleBind = nil
    local minimizeGuiBind = {
        kind = "KeyCode",
        code = "RightAlt"
    }
    local pendingBindAction = nil
]])

    source = mustReplace(source, [[
    local smoothWindowInputEndConnection = nil
    local customBindConnection = nil
]], [[
    local smoothWindowInputEndConnection = nil
    local customBindConnection = nil
    local lastMinimizeToggleTime = 0
]])

    source = mustReplace(source, [[
    local function bindToDisplayText(bind)
        if not bind then
            return "None"
        end

        return bind.code
    end

    local function createBindFromInput(input)
]], [[
    local function bindToDisplayText(bind)
        if not bind then
            return "None"
        end

        return bind.code
    end

    local function normalizeKeybindCode(value)
        if typeof(value) == "EnumItem" then
            return value.Name
        end

        if type(value) == "table" then
            if typeof(value.KeyCode) == "EnumItem" then
                return value.KeyCode.Name
            end

            if typeof(value.Value) == "EnumItem" then
                return value.Value.Name
            end

            local rawValue = value.KeyCode or value.Value or value[1]
            if rawValue ~= nil then
                return tostring(rawValue)
            end
        end

        if value == nil then
            return ""
        end

        return tostring(value)
    end

    local function createBindFromInput(input)
]])

    source = mustReplace(source, [[
    local function doesBindMatch(bind, input)
        return bind ~= nil and bind.kind == "KeyCode" and input.UserInputType == Enum.UserInputType.Keyboard and
            input.KeyCode.Name == bind.code
    end

    local function updateBindParagraphs()
]], [[
    local function doesBindMatch(bind, input)
        return bind ~= nil and bind.kind == "KeyCode" and input.UserInputType == Enum.UserInputType.Keyboard and
            input.KeyCode.Name == bind.code
    end

    local function setMinimizeBindFromFluentValue(value, shouldNotify)
        local bindCode = normalizeKeybindCode(value)
        if bindCode == "" then
            return
        end

        minimizeGuiBind = {
            kind = "KeyCode",
            code = bindCode
        }

        if shouldNotify then
            notify("Minimize Bind", "Set to " .. bindCode)
        end
    end

    local function updateBindParagraphs()
]])

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
    minimizeKeybindControl = tabs.Settings:AddKeybind("MinimizeKeybind", {
        Title = "Minimize Bind",
        Mode = "Toggle",
        Default = "RightAlt",
        ChangedCallback = function(newBind)
            setMinimizeBindFromFluentValue(newBind, true)
        end
    })

    tabs.Settings:AddParagraph({
        Title = "Notes",
        Content = "The minimize key is chosen through Fluent's keybind control and applied by the hub's live input handler, so changing the bind updates instantly without keeping RightAlt locked in."
    })
]])

    source = mustReplace(source, [[
    updateBindParagraphs()
    window:SelectTab(1)
]], [[
    updateBindParagraphs()
    setMinimizeBindFromFluentValue("RightAlt", false)
    window:SelectTab(1)
]])

    source = mustReplace(source, [[
        if gameProcessed then
            return
        end

        if doesBindMatch(equipFirstToolsBind, input) then
]], [[
        if doesBindMatch(minimizeGuiBind, input) then
            local now = os.clock()
            if now - lastMinimizeToggleTime < 0.15 then
                return
            end

            lastMinimizeToggleTime = now
            task.spawn(function()
                local toggled = toggleWindowVisibility()
                if not toggled then
                    notify("Minimize Bind", "The interface is busy right now. Try again in a moment.")
                end
            end)
            return
        end

        if gameProcessed then
            return
        end

        if doesBindMatch(equipFirstToolsBind, input) then
]])

    local chunk = assert(loadstring(source, "@ultra_power_patched"))
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
