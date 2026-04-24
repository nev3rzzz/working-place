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
    local function toggleWindowVisibility()
        if not trackedWindowFrame or not trackedWindowGui or not trackedWindowFrame.Parent or not trackedWindowGui.Parent then
            local foundWindow = captureWindowReferences()
            if not foundWindow then
                return false
            end
        end

        if trackedWindowAnimating then
            return false
        end

        local shouldShow = trackedWindowGui.Enabled == false
        trackedWindowVisible = trackedWindowGui.Enabled ~= false
        return tweenWindowVisibility(shouldShow)
    end
]], [[
    local function toggleWindowVisibility()
        local function countWindowMarkerTexts(root)
            if not root then
                return 0
            end

            local wantedTexts = {
                Main = true,
                Targeting = true,
                Tycoon = true,
                Settings = true
            }

            local foundTexts = {}
            local count = 0

            for _, descendant in ipairs(root:GetDescendants()) do
                if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
                    local text = tostring(descendant.Text or "")
                    if wantedTexts[text] and not foundTexts[text] then
                        foundTexts[text] = true
                        count += 1
                    end
                end
            end

            return count
        end

        local function findLargestWindowFrame(root)
            if not root then
                return nil
            end

            local bestFrame = nil
            local bestArea = 0

            for _, descendant in ipairs(root:GetDescendants()) do
                if descendant:IsA("GuiObject") then
                    local absoluteSize = descendant.AbsoluteSize
                    local area = absoluteSize.X * absoluteSize.Y
                    if absoluteSize.X >= 360 and absoluteSize.Y >= 240 and area > bestArea then
                        bestArea = area
                        bestFrame = descendant
                    end
                end
            end

            return bestFrame
        end

        local function findWindowFallbackCandidate(root)
            if not root then
                return nil, nil
            end

            local bestGui = nil
            local bestFrame = nil
            local bestScore = -1
            local bestArea = -1
            local candidates = {}

            if root:IsA("ScreenGui") then
                table.insert(candidates, root)
            end

            for _, child in ipairs(root:GetChildren()) do
                if child:IsA("ScreenGui") and child.Name ~= "NNEnjoyerBindCapture" then
                    table.insert(candidates, child)
                end
            end

            for _, screenGui in ipairs(candidates) do
                local markerScore = countWindowMarkerTexts(screenGui)
                if markerScore > 0 then
                    local candidateFrame = findLargestWindowFrame(screenGui)
                    local candidateArea = 0
                    if candidateFrame then
                        candidateArea = candidateFrame.AbsoluteSize.X * candidateFrame.AbsoluteSize.Y
                    end

                    if markerScore > bestScore or (markerScore == bestScore and candidateArea > bestArea) then
                        bestScore = markerScore
                        bestArea = candidateArea
                        bestGui = screenGui
                        bestFrame = candidateFrame
                    end
                end
            end

            return bestGui, bestFrame
        end

        if not trackedWindowFrame or not trackedWindowGui or not trackedWindowFrame.Parent or not trackedWindowGui.Parent then
            local foundWindow = captureWindowReferences()
            if not foundWindow then
                local fallbackGui, fallbackFrame = findWindowFallbackCandidate(getGuiRoot())
                if not fallbackGui then
                    return false
                end

                trackedWindowGui = fallbackGui
                trackedWindowFrame = fallbackFrame
                trackedWindowScale = nil
                trackedWindowShownPosition = fallbackFrame and fallbackFrame.Position or nil
            end
        end

        if trackedWindowAnimating then
            trackedWindowAnimating = false
        end

        if not trackedWindowFrame or not trackedWindowScale then
            local shouldShow = trackedWindowGui.Enabled == false
            trackedWindowGui.Enabled = shouldShow
            trackedWindowVisible = shouldShow
            return true
        end

        local shouldShow = trackedWindowGui.Enabled == false
        trackedWindowVisible = trackedWindowGui.Enabled ~= false
        return tweenWindowVisibility(shouldShow)
    end
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
                    notify("Minimize Bind", "The interface could not be found right now.")
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
