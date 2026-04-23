return function(context)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")

    local LocalPlayer = context.LocalPlayer or Players.LocalPlayer
    local authTier = tostring(context.Auth and context.Auth.tier or "basic")

    local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

    local window = Fluent:CreateWindow({
        Title = context.WindowTitle,
        SubTitle = "Ultra Power",
        TabWidth = 160,
        Size = UDim2.fromOffset(560, 520),
        Acrylic = false,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.RightAlt
    })

    local tabs = {
        Main = window:AddTab({
            Title = "Main",
            Icon = "home"
        }),
        Settings = window:AddTab({
            Title = "Settings",
            Icon = "settings"
        })
    }

    local jumpPowerValue = 50
    local walkSpeedValue = 16
    local autoCollectCashEnabled = false
    local autoCollectCashDelay = 0.2
    local autoCollectCashConnection = nil
    local hiddenLaserDoors = {}
    local laserDoorsConnection = nil
    local laserDoorsEnabled = false

    local function notify(title, content)
        Fluent:Notify({
            Title = title,
            Content = content,
            Duration = 5
        })
    end

    local function getCharacter()
        return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    end

    local function getHumanoid()
        local character = getCharacter()
        return character and character:FindFirstChildOfClass("Humanoid")
    end

    local function getRootPart()
        local character = getCharacter()
        return character and character:FindFirstChild("HumanoidRootPart")
    end

    local function getBackpack()
        return LocalPlayer:FindFirstChildOfClass("Backpack") or LocalPlayer:WaitForChild("Backpack", 5)
    end

    local function findLocalTycoon()
        local tycoonDirectory = Workspace:FindFirstChild("TycoonDirectory")
        if not tycoonDirectory then
            return nil
        end

        for _, tycoon in ipairs(tycoonDirectory:GetChildren()) do
            if tycoon:IsA("Model") and string.find(tycoon.Name, LocalPlayer.Name, 1, true) then
                return tycoon
            end
        end

        return nil
    end

    local function getCollectorTouchPart()
        local tycoon = findLocalTycoon()
        if not tycoon then
            return nil
        end

        local collector = tycoon:FindFirstChild("BasicCollector")
        return collector and collector:FindFirstChild("Touch")
    end

    local function setJumpPower(value)
        local humanoid = getHumanoid()
        if not humanoid then
            notify("JumpPower", "Humanoid was not found.")
            return
        end

        humanoid.UseJumpPower = true
        humanoid.JumpPower = value
    end

    local function setWalkSpeed(value)
        local humanoid = getHumanoid()
        if not humanoid then
            notify("WalkSpeed", "Humanoid was not found.")
            return
        end

        humanoid.WalkSpeed = value
    end

    local function collectBasicPowerSpawns()
        local rootPart = getRootPart()
        if not rootPart then
            notify("Get All Tools", "HumanoidRootPart was not found.")
            return
        end

        local touched = 0
        for _, descendant in ipairs(Workspace:GetDescendants()) do
            if descendant:IsA("Model") and descendant.Name == "BasicPowerSpawn" then
                local touchPart = descendant:FindFirstChild("touchPart")
                if touchPart and touchPart:IsA("BasePart") then
                    pcall(function()
                        firetouchinterest(rootPart, touchPart, 0)
                        task.wait(0.05)
                        firetouchinterest(rootPart, touchPart, 1)
                    end)
                    touched += 1
                end
            end
        end

        notify("Get All Tools", "Touched spawns: " .. tostring(touched))
    end

    local function equipAllTools()
        local backpack = getBackpack()
        local character = getCharacter()
        if not backpack or not character then
            notify("Equip Tools", "Backpack or character was not found.")
            return
        end

        local equipped = 0
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") then
                tool.Parent = character
                equipped += 1
            end
        end

        notify("Equip Tools", "Equipped: " .. tostring(equipped))
    end

    local function hideLaserDoor(instance)
        if not instance or not instance.Parent or hiddenLaserDoors[instance] then
            return
        end

        hiddenLaserDoors[instance] = instance.Parent
        instance.Parent = nil
    end

    local function setLaserDoorsEnabled(value)
        laserDoorsEnabled = value == true

        if laserDoorsConnection then
            laserDoorsConnection:Disconnect()
            laserDoorsConnection = nil
        end

        if not laserDoorsEnabled then
            local restored = 0
            for laserDoor, originalParent in pairs(hiddenLaserDoors) do
                if laserDoor and originalParent then
                    laserDoor.Parent = originalParent
                    restored += 1
                end
                hiddenLaserDoors[laserDoor] = nil
            end

            notify("Laser Doors", "Restored: " .. tostring(restored))
            return
        end

        local tycoonDirectory = Workspace:FindFirstChild("TycoonDirectory")
        if not tycoonDirectory then
            notify("Laser Doors", "TycoonDirectory was not found.")
            return
        end

        local hidden = 0
        for _, descendant in ipairs(tycoonDirectory:GetDescendants()) do
            if descendant.Name == "doorLasers" then
                hideLaserDoor(descendant)
                hidden += 1
            end
        end

        laserDoorsConnection = tycoonDirectory.DescendantAdded:Connect(function(descendant)
            if laserDoorsEnabled and descendant.Name == "doorLasers" then
                hideLaserDoor(descendant)
            end
        end)

        notify("Laser Doors", "Hidden: " .. tostring(hidden))
    end

    local function setAutoCollectCashEnabled(value)
        autoCollectCashEnabled = value == true

        if autoCollectCashConnection then
            autoCollectCashConnection:Disconnect()
            autoCollectCashConnection = nil
        end

        if not autoCollectCashEnabled then
            return
        end

        autoCollectCashConnection = RunService.Heartbeat:Connect(function()
            if not autoCollectCashEnabled then
                return
            end

            local rootPart = getRootPart()
            local touchPart = getCollectorTouchPart()
            if rootPart and touchPart and touchPart:IsA("BasePart") then
                pcall(function()
                    firetouchinterest(rootPart, touchPart, 0)
                    task.wait(0.1)
                    firetouchinterest(rootPart, touchPart, 1)
                end)
            end

            task.wait(autoCollectCashDelay)
        end)
    end

    tabs.Main:AddParagraph({
        Title = "Session",
        Content = "Player: " .. tostring(LocalPlayer.Name) ..
            "\nTier: " .. authTier ..
            "\nPlaceId: " .. tostring(context.PlaceId)
    })

    tabs.Main:AddButton({
        Title = "Get All Tools",
        Description = "Collect tools from BasicPowerSpawn models",
        Callback = function()
            task.spawn(collectBasicPowerSpawns)
        end
    })

    tabs.Main:AddButton({
        Title = "Equip All Tools",
        Description = "Move every tool from Backpack into Character",
        Callback = function()
            task.spawn(equipAllTools)
        end
    })

    tabs.Main:AddSlider("WalkSpeedSlider", {
        Title = "WalkSpeed",
        Default = walkSpeedValue,
        Min = 0,
        Max = 300,
        Rounding = 0
    }):OnChanged(function(value)
        walkSpeedValue = value
        task.spawn(function()
            setWalkSpeed(value)
        end)
    end)

    tabs.Main:AddSlider("JumpPowerSlider", {
        Title = "JumpPower",
        Default = jumpPowerValue,
        Min = 0,
        Max = 300,
        Rounding = 0
    }):OnChanged(function(value)
        jumpPowerValue = value
        task.spawn(function()
            setJumpPower(value)
        end)
    end)

    tabs.Main:AddToggle("LaserDoorsToggle", {
        Title = "Remove Laser Doors",
        Default = false
    }):OnChanged(function(value)
        task.spawn(function()
            setLaserDoorsEnabled(value)
        end)
    end)

    tabs.Main:AddToggle("AutoCollectCashToggle", {
        Title = "Auto Collect Cash",
        Default = false
    }):OnChanged(function(value)
        task.spawn(function()
            setAutoCollectCashEnabled(value)
        end)
    end)

    tabs.Settings:AddSlider("AutoCollectCashDelaySlider", {
        Title = "Auto Collect Delay",
        Default = autoCollectCashDelay,
        Min = 0.05,
        Max = 5,
        Rounding = 2
    }):OnChanged(function(value)
        autoCollectCashDelay = value
    end)

    tabs.Settings:AddParagraph({
        Title = "Future Games",
        Content = "Add new game-specific scripts to client/games/ and then map them in client/loader.lua by PlaceId."
    })

    window:SelectTab(1)

    notify("Ultra Power", "Authorized as " .. authTier .. ".")
end
