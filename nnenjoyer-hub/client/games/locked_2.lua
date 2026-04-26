return function(context)
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")

    local LocalPlayer = context.LocalPlayer or Players.LocalPlayer
    local Runtime = context.Runtime
    local authTier = tostring(context.Auth and context.Auth.tier or "basic")
    local authStartsDisplay = tostring(context.Auth and context.Auth.startsAt or "")
    local authExpiresDisplay = tostring(context.Auth and context.Auth.expiresAt or "")

    if authStartsDisplay == "" then
        authStartsDisplay = "Immediate"
    end

    if authExpiresDisplay == "" then
        authExpiresDisplay = "No expiry"
    end

    local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

    local sprintPercent = tonumber(getgenv().SprintPercent) or 100
    local enabled = false
    local sprinting = false

    local sprintKey = Enum.KeyCode.LeftShift
    local toggleKey = Enum.KeyCode.LeftAlt

    local measuredWalkSpeed = tonumber(getgenv().MeasuredWalkSpeed) or 16
    local measuredRunSpeed = tonumber(getgenv().MeasuredRunSpeed) or 24

    local lastRootPos = nil
    local sampleAlpha = 0.12
    local minSampleSpeed = 2

    local heartbeatConn = nil
    local inputBeganConn = nil
    local inputEndedConn = nil
    local charAddedConn = nil
    local notificationsMuted = false
    local window = nil
    local sprintToggle = nil
    local percentSlider = nil

    local function notify(title, content, duration)
        if notificationsMuted then
            return
        end

        Fluent:Notify({
            Title = title,
            Content = content,
            Duration = duration or 3
        })
    end

    local function getRootPart()
        local character = LocalPlayer.Character
        if not character then
            return nil
        end

        return character:FindFirstChild("HumanoidRootPart")
    end

    local function horizontal(vector)
        return Vector3.new(vector.X, 0, vector.Z)
    end

    local function isMoveKeyDown()
        return UserInputService:IsKeyDown(Enum.KeyCode.W)
            or UserInputService:IsKeyDown(Enum.KeyCode.A)
            or UserInputService:IsKeyDown(Enum.KeyCode.S)
            or UserInputService:IsKeyDown(Enum.KeyCode.D)
    end

    local function smoothSample(current, sample)
        return current + ((sample - current) * sampleAlpha)
    end

    local function canSampleRunSpeed()
        return not enabled or sprintPercent == 100
    end

    local function updateSpeedSamples(nativeSpeed)
        if nativeSpeed < minSampleSpeed or not isMoveKeyDown() then
            return
        end

        if sprinting then
            if canSampleRunSpeed() then
                measuredRunSpeed = smoothSample(measuredRunSpeed, nativeSpeed)
                getgenv().MeasuredRunSpeed = measuredRunSpeed
            end
        else
            measuredWalkSpeed = smoothSample(measuredWalkSpeed, nativeSpeed)
            getgenv().MeasuredWalkSpeed = measuredWalkSpeed
        end
    end

    local function getTargetRunSpeed()
        local walk = measuredWalkSpeed
        local run = math.max(measuredRunSpeed, walk)
        local runBonus = math.max(run - walk, 0)

        return walk + (runBonus * (sprintPercent / 100))
    end

    local function setEnabled(value)
        enabled = value == true
        if sprintToggle and sprintToggle.SetValue then
            pcall(function()
                sprintToggle:SetValue(enabled)
            end)
        end
    end

    local function cleanup()
        enabled = false
        sprinting = false
        lastRootPos = nil
        notificationsMuted = true

        if heartbeatConn then
            heartbeatConn:Disconnect()
            heartbeatConn = nil
        end

        if inputBeganConn then
            inputBeganConn:Disconnect()
            inputBeganConn = nil
        end

        if inputEndedConn then
            inputEndedConn:Disconnect()
            inputEndedConn = nil
        end

        if charAddedConn then
            charAddedConn:Disconnect()
            charAddedConn = nil
        end

        pcall(function()
            if window and window.Destroy then
                window:Destroy()
            end
        end)

        pcall(function()
            if Fluent and Fluent.Destroy then
                Fluent:Destroy()
            end
        end)
    end

    window = Fluent:CreateWindow({
        Title = context.WindowTitle or "N(n)enjoyer Hub",
        SubTitle = "Locked 2",
        TabWidth = 160,
        Size = UDim2.fromOffset(580, 460),
        Acrylic = false,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.RightControl
    })

    local tabs = {
        Main = window:AddTab({
            Title = "Main",
            Icon = "zap"
        }),
        Settings = window:AddTab({
            Title = "Settings",
            Icon = "settings"
        })
    }

    tabs.Main:AddParagraph({
        Title = "Shift Sprint",
        Content = "Sprint modifier with native walk/run speed measuring."
    })

    sprintToggle = tabs.Main:AddToggle("Locked2SprintToggle", {
        Title = "Enable Sprint Modifier",
        Description = "Changes only held sprint speed",
        Default = false
    })

    sprintToggle:OnChanged(function(value)
        enabled = value == true
        notify("Shift Sprint", enabled and "Sprint modifier enabled." or "Sprint modifier disabled.", 2)
    end)

    percentSlider = tabs.Main:AddSlider("Locked2SprintPercentSlider", {
        Title = "Sprint Speed %",
        Description = "100% keeps native sprint speed",
        Default = sprintPercent,
        Min = 0,
        Max = 300,
        Rounding = 0
    })

    percentSlider:OnChanged(function(value)
        sprintPercent = tonumber(value) or 100
        getgenv().SprintPercent = sprintPercent
    end)

    tabs.Main:AddButton({
        Title = "Reset Sprint %",
        Description = "Restore normal game sprint speed",
        Callback = function()
            sprintPercent = 100
            getgenv().SprintPercent = sprintPercent
            if percentSlider and percentSlider.SetValue then
                pcall(function()
                    percentSlider:SetValue(100)
                end)
            end
            notify("Shift Sprint", "Sprint modifier reset to 100%.", 2)
        end
    })

    tabs.Main:AddButton({
        Title = "Show Measured Speeds",
        Description = "Show walk, native run, and target sprint",
        Callback = function()
            notify(
                "Measured Speeds",
                string.format(
                    "Walk: %.1f | Run: %.1f | Target: %.1f",
                    measuredWalkSpeed,
                    measuredRunSpeed,
                    getTargetRunSpeed()
                ),
                5
            )
        end
    })

    tabs.Main:AddButton({
        Title = "Reset Measurements",
        Description = "Recalibrate detected walk and run speeds",
        Callback = function()
            measuredWalkSpeed = 16
            measuredRunSpeed = 24
            lastRootPos = nil
            getgenv().MeasuredWalkSpeed = measuredWalkSpeed
            getgenv().MeasuredRunSpeed = measuredRunSpeed
            notify("Shift Sprint", "Measurements reset. Walk and sprint again to recalibrate.", 4)
        end
    })

    tabs.Main:AddButton({
        Title = "Unload Script",
        Description = "Disconnect events and close this menu",
        Callback = function()
            notify("Shift Sprint", "Unloaded.", 3)
            cleanup()
        end
    })

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
        Content = "Minimize Bind: RightCtrl"
    })

    local toggleKeybind = tabs.Settings:AddKeybind("Locked2ToggleKeybind", {
        Title = "Toggle Sprint Modifier",
        Description = "Toggle the modifier on or off",
        Default = "LeftAlt",
        Mode = "Toggle"
    })

    toggleKeybind:OnChanged(function()
        local key = toggleKeybind.Value
        if key and Enum.KeyCode[key] then
            toggleKey = Enum.KeyCode[key]
        end
    end)

    local sprintKeybind = tabs.Settings:AddKeybind("Locked2SprintKeybind", {
        Title = "Sprint Key",
        Description = "Hold this key to use modified sprint",
        Default = "LeftShift",
        Mode = "Hold"
    })

    sprintKeybind:OnChanged(function()
        local key = sprintKeybind.Value
        if key and Enum.KeyCode[key] then
            sprintKey = Enum.KeyCode[key]
        end
    end)

    heartbeatConn = RunService.Heartbeat:Connect(function(deltaTime)
        if deltaTime <= 0 then
            return
        end

        local root = getRootPart()
        if not root then
            lastRootPos = nil
            return
        end

        local clampedDelta = math.min(deltaTime, 0.1)
        local currentPos = root.Position

        if not lastRootPos then
            lastRootPos = currentPos
            return
        end

        local nativeDelta = horizontal(currentPos - lastRootPos)
        local nativeSpeed = nativeDelta.Magnitude / clampedDelta

        updateSpeedSamples(nativeSpeed)

        if not enabled or not sprinting or not isMoveKeyDown() then
            lastRootPos = currentPos
            return
        end

        local correctionSpeed = getTargetRunSpeed() - nativeSpeed
        if math.abs(correctionSpeed) < 0.25 or nativeDelta.Magnitude <= 0.001 then
            lastRootPos = currentPos
            return
        end

        root.CFrame = root.CFrame + (nativeDelta.Unit * correctionSpeed * clampedDelta)
        lastRootPos = root.Position
    end)

    inputBeganConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end

        if input.KeyCode == toggleKey then
            setEnabled(not enabled)
        end

        if input.KeyCode == sprintKey then
            sprinting = true
        end
    end)

    inputEndedConn = UserInputService.InputEnded:Connect(function(input)
        if input.KeyCode == sprintKey then
            sprinting = false
        end
    end)

    charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
        lastRootPos = nil
        task.wait(0.5)
    end)

    if Runtime and Runtime.RegisterCleanup then
        Runtime:RegisterCleanup(cleanup)
    end

    window:SelectTab(1)
    notify("Shift Sprint", "Loaded. Walk and sprint a bit to calibrate measured speeds.", 5)

    return {
        shutdown = cleanup
    }
end
