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
    local window = Fluent:CreateWindow({
        Title = context.WindowTitle,
        SubTitle = "Ultra Power",
        TabWidth = 160,
        Size = UDim2.fromOffset(620, 540),
        Acrylic = false,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.RightAlt
    })

    local tabs = {
        Main = window:AddTab({
            Title = "Main",
            Icon = "home"
        }),
        Targeting = window:AddTab({
            Title = "Targeting",
            Icon = "crosshair"
        }),
        Tycoon = window:AddTab({
            Title = "Tycoon",
            Icon = "factory"
        }),
        Settings = window:AddTab({
            Title = "Settings",
            Icon = "settings"
        })
    }
]], [[
    local window = Fluent:CreateWindow({
        Title = context.WindowTitle,
        SubTitle = "Ultra Power",
        TabWidth = 160,
        Size = UDim2.fromOffset(620, 540),
        Acrylic = false,
        Theme = "Dark"
    })

    local tabs = {
        Movement = window:AddTab({
            Title = "Movement",
            Icon = "zap"
        }),
        Tools = window:AddTab({
            Title = "Tools",
            Icon = "wrench"
        }),
        Targeting = window:AddTab({
            Title = "Targeting",
            Icon = "crosshair"
        }),
        Tycoon = window:AddTab({
            Title = "Tycoon",
            Icon = "factory"
        }),
        Settings = window:AddTab({
            Title = "Settings",
            Icon = "settings"
        })
    }
]])

    source = mustReplace(source, [[
        local wantedTexts = {
            Main = true,
            Targeting = true,
            Tycoon = true,
            Settings = true
        }
]], [[
        local wantedTexts = {
            Movement = true,
            Tools = true,
            Targeting = true,
            Tycoon = true,
            Settings = true
        }
]])

    source = mustReplace(source, [[
    local smoothWindowConnection = nil
    local smoothWindowInputConnection = nil
    local smoothWindowInputEndConnection = nil
    local customBindConnection = nil
]], [[
    local smoothWindowConnection = nil
    local smoothWindowInputConnection = nil
    local smoothWindowInputEndConnection = nil
    local customBindConnection = nil
    local lastMinimizeToggleTime = 0
]])

    source = mustReplace(source, [[
            trackedWindowVisible = true
            trackedWindowScale.Scale = 0.96
            trackedWindowFrame.Position = trackedWindowShownPosition + trackedWindowToggleOffset

            local scaleTween = TweenService:Create(trackedWindowScale, TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                Scale = 1
            })

            local positionTween = TweenService:Create(trackedWindowFrame, TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                Position = trackedWindowShownPosition
            })
]], [[
            trackedWindowVisible = true
            trackedWindowScale.Scale = 0.92
            trackedWindowFrame.Position = trackedWindowShownPosition + UDim2.fromOffset(0, 24)

            local scaleTween = TweenService:Create(trackedWindowScale, TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                Scale = 1
            })

            local positionTween = TweenService:Create(trackedWindowFrame, TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                Position = trackedWindowShownPosition
            })
]])

    source = mustReplace(source, [[
            task.delay(0.35, function()
                if not finished then
                    trackedWindowAnimating = false
                    trackedWindowAnimationStartedAt = 0
                end
            end)
]], [[
            task.delay(0.45, function()
                if not finished then
                    trackedWindowAnimating = false
                    trackedWindowAnimationStartedAt = 0
                end
            end)
]])

    source = mustReplace(source, [[
        local scaleTween = TweenService:Create(trackedWindowScale, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            Scale = 0.96
        })

        local positionTween = TweenService:Create(trackedWindowFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            Position = trackedWindowShownPosition + trackedWindowToggleOffset
        })
]], [[
        local scaleTween = TweenService:Create(trackedWindowScale, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            Scale = 0.93
        })

        local positionTween = TweenService:Create(trackedWindowFrame, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            Position = trackedWindowShownPosition + UDim2.fromOffset(0, 24)
        })
]])

    source = mustReplace(source, [[
        task.delay(0.3, function()
            if not finished then
                trackedWindowVisible = false
                trackedWindowGui.Enabled = false
                trackedWindowFrame.Visible = true
                trackedWindowFrame.Position = trackedWindowShownPosition
                trackedWindowScale.Scale = 1
                trackedWindowAnimating = false
                trackedWindowAnimationStartedAt = 0
            end
        end)
]], [[
        task.delay(0.4, function()
            if not finished then
                trackedWindowVisible = false
                trackedWindowGui.Enabled = false
                trackedWindowFrame.Visible = true
                trackedWindowFrame.Position = trackedWindowShownPosition
                trackedWindowScale.Scale = 1
                trackedWindowAnimating = false
                trackedWindowAnimationStartedAt = 0
            end
        end)
]])

    source = mustReplace(source, [[
            if trackedWindowAnimationStartedAt > 0 and os.clock() - trackedWindowAnimationStartedAt > 0.8 then
                trackedWindowAnimating = false
                trackedWindowAnimationStartedAt = 0
            else
                return false
            end
]], [[
            if trackedWindowAnimationStartedAt > 0 and os.clock() - trackedWindowAnimationStartedAt > 0.9 then
                trackedWindowAnimating = false
                trackedWindowAnimationStartedAt = 0
            else
                return false
            end
]])

    source = mustReplace(source, [[
            smoothWindowConnection = RunService.RenderStepped:Connect(function()
                if dragging then
                    windowFrame.Position = lerpUDim2(windowFrame.Position, targetWindowPosition, 0.28)
                    trackedWindowShownPosition = windowFrame.Position
                end
            end)
]], [[
            smoothWindowConnection = RunService.RenderStepped:Connect(function(deltaTime)
                if dragging then
                    local alpha = 1 - math.exp(-deltaTime * 18)
                    windowFrame.Position = lerpUDim2(windowFrame.Position, targetWindowPosition, alpha)
                    trackedWindowShownPosition = windowFrame.Position
                end
            end)
]])

    source = mustReplace(source, [[
    tabs.Main:AddParagraph({
        Title = "Session",
        Content = "Player: " .. tostring(LocalPlayer.Name) ..
            "\nTier: " .. authTier ..
            "\nStarts: " .. authStartsDisplay ..
            "\nExpires: " .. authExpiresDisplay ..
            "\nPlaceId: " .. tostring(context.PlaceId)
    })

    tabs.Main:AddParagraph({
        Title = "Movement",
        Content = "Character movement and recovery controls."
    })
]], [[
    tabs.Movement:AddParagraph({
        Title = "Movement",
        Content = "Character movement and recovery controls."
    })
]])

    source = mustReplace(source, [[tabs.Main:AddButton({
        Title = "Check JumpPower"]], [[tabs.Movement:AddButton({
        Title = "Check JumpPower"]])
    source = mustReplace(source, [[tabs.Main:AddSlider("UltraPowerJumpPowerSlider", {]], [[tabs.Movement:AddSlider("UltraPowerJumpPowerSlider", {]])
    source = mustReplace(source, [[tabs.Main:AddButton({
        Title = "Check WalkSpeed"]], [[tabs.Movement:AddButton({
        Title = "Check WalkSpeed"]])
    source = mustReplace(source, [[tabs.Main:AddSlider("UltraPowerWalkSpeedSlider", {]], [[tabs.Movement:AddSlider("UltraPowerWalkSpeedSlider", {]])
    source = mustReplace(source, [[tabs.Main:AddToggle("UltraPowerLongFallToggle", {]], [[tabs.Movement:AddToggle("UltraPowerLongFallToggle", {]])

    source = mustReplace(source, [[
    tabs.Main:AddParagraph({
        Title = "Tools",
        Content = "Tool collection, equip limit, and activation controls."
    })
]], [[
    tabs.Tools:AddParagraph({
        Title = "Tools",
        Content = "Tool collection, equip limit, and activation controls."
    })
]])

    source = mustReplace(source, [[tabs.Main:AddButton({
        Title = "Get All Tools"]], [[tabs.Tools:AddButton({
        Title = "Get All Tools"]])
    source = mustReplace(source, [[tabs.Main:AddSlider("UltraPowerEquippedToolCountSlider", {]], [[tabs.Tools:AddSlider("UltraPowerEquippedToolCountSlider", {]])
    source = mustReplace(source, [[tabs.Main:AddButton({
        Title = "Equip First Tools"]], [[tabs.Tools:AddButton({
        Title = "Equip First Tools"]])
    source = mustReplace(source, [[equipBindParagraph = tabs.Main:AddParagraph({]], [[equipBindParagraph = tabs.Tools:AddParagraph({]])
    source = mustReplace(source, [[tabs.Main:AddButton({
        Title = "Set Equip Bind"]], [[tabs.Tools:AddButton({
        Title = "Set Equip Bind"]])
    source = mustReplace(source, [[tabs.Main:AddButton({
        Title = "Use All Equipped Tools"]], [[tabs.Tools:AddButton({
        Title = "Use All Equipped Tools"]])
    source = mustReplace(source, [[tabs.Main:AddToggle("UltraPowerUseAllToolsOnClickToggle", {]], [[tabs.Tools:AddToggle("UltraPowerUseAllToolsOnClickToggle", {]])

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
        Title = "Session",
        Content = "Player: " .. tostring(LocalPlayer.Name) ..
            "\nTier: " .. authTier ..
            "\nStarts: " .. authStartsDisplay ..
            "\nExpires: " .. authExpiresDisplay ..
            "\nPlaceId: " .. tostring(context.PlaceId)
    })

    tabs.Settings:AddParagraph({
        Title = "Interface",
        Content = "Minimize Bind: RightAlt"
    })
]])

    source = mustReplace(source, [[
        if gameProcessed then
            return
        end

        if doesBindMatch(equipFirstToolsBind, input) then
]], [[
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.RightAlt then
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

    local chunk = assert(loadstring(source, "@ultra_power_restructured"))
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
