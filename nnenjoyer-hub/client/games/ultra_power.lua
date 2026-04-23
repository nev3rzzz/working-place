return function(context)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")
    local UserInputService = game:GetService("UserInputService")
    local GuiService = game:GetService("GuiService")

    local LocalPlayer = context.LocalPlayer or Players.LocalPlayer
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
    local VirtualInputManager = nil

    pcall(function()
        VirtualInputManager = game:GetService("VirtualInputManager")
    end)

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

    local SCAN_BATCH_SIZE = 250
    local TOUCH_BATCH_SIZE = 10
    local TOOL_USE_RESET_DELAY = 0.12
    local TYCOON_CACHE_INTERVAL = 1
    local AIM_UPDATE_INTERVAL = 1 / 60
    local IDLE_AUTO_COLLECT_DELAY = 0.5
    local MOUSE_MOVE_EPSILON = 1
    local CAMERA_POSITION_EPSILON = 0.01
    local LONG_FALL_RESET_DURATION = 2
    local LONG_FALL_CHECK_INTERVAL = 0.1
    local CENTER_MASS_AIM_MODE = "UpperTorso/Torso"

    local jumpPowerValue = 50
    local walkSpeedValue = 16
    local equippedToolCount = 1
    local autoCollectCashDelay = 0.2
    local isCollecting = false

    local currentCharacter = nil
    local currentHumanoid = nil
    local currentRootPart = nil
    local currentBackpack = nil

    local autoCollectCashEnabled = false
    local autoCollectCashRunning = false
    local autoCollectCashSession = 0
    local localTycoonCache = nil
    local lastLocalTycoonRefresh = 0
    local cachedCollectorTycoon = nil
    local cachedCollectorTouchPart = nil

    local laserDoorsDisabled = false
    local hiddenLaserDoors = {}
    local laserDoorWatcher = nil

    local useAllToolsOnClickEnabled = false
    local useAllToolsConnection = nil
    local lastUseAllToolsTime = 0

    local autoResetLongFallEnabled = false
    local autoResetLongFallConnection = nil
    local longFallStartTime = nil
    local longFallCheckAccumulator = 0

    local targetPlayerDropdown = nil
    local selectedTargetPlayerName = nil
    local targetAimPartMode = "Head"
    local targetCameraDistance = 2.5
    local aimMouseAtTargetEnabled = false
    local aimMouseAtTargetConnection = nil
    local aimUpdateAccumulator = 0
    local originalCameraType = nil
    local originalCameraSubject = nil
    local lastDeadTargetCharacter = nil
    local cachedTargetPlayer = nil
    local cachedTargetCharacter = nil
    local cachedTargetHumanoid = nil
    local cachedTargetHead = nil
    local cachedTargetRootPart = nil
    local cachedTargetUpperTorso = nil
    local cachedTargetTorso = nil
    local cachedTargetLowerTorso = nil
    local cachedGuiInset = GuiService:GetGuiInset()
    local lastMouseTargetX = nil
    local lastMouseTargetY = nil

    local function notify(title, content)
        Fluent:Notify({
            Title = title,
            Content = content,
            Duration = 5
        })
    end

    local function refreshCharacterCache(character)
        currentCharacter = character or LocalPlayer.Character
        currentHumanoid = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")
        currentRootPart = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
    end

    local function refreshBackpackCache()
        currentBackpack = LocalPlayer:FindFirstChildOfClass("Backpack") or LocalPlayer:FindFirstChild("Backpack")
    end

    local function getCharacter()
        if currentCharacter and currentCharacter.Parent then
            return currentCharacter
        end

        refreshCharacterCache(LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait())
        return currentCharacter
    end

    local function getHumanoid()
        local character = getCharacter()
        if not currentHumanoid or currentHumanoid.Parent ~= character then
            currentHumanoid = character and character:FindFirstChildOfClass("Humanoid")
        end

        return currentHumanoid
    end

    local function getRootPart()
        local character = getCharacter()
        if not currentRootPart or currentRootPart.Parent ~= character then
            currentRootPart = character and character:FindFirstChild("HumanoidRootPart")
        end

        return currentRootPart
    end

    local function getBackpack()
        if currentBackpack and currentBackpack.Parent == LocalPlayer then
            return currentBackpack
        end

        currentBackpack = LocalPlayer:FindFirstChildOfClass("Backpack") or LocalPlayer:WaitForChild("Backpack", 5)
        return currentBackpack
    end

    local function resetAimCursorCache()
        lastMouseTargetX = nil
        lastMouseTargetY = nil
    end

    local function invalidateTargetCharacterCache()
        cachedTargetCharacter = nil
        cachedTargetHumanoid = nil
        cachedTargetHead = nil
        cachedTargetRootPart = nil
        cachedTargetUpperTorso = nil
        cachedTargetTorso = nil
        cachedTargetLowerTorso = nil
    end

    local function invalidateTargetCache()
        cachedTargetPlayer = nil
        invalidateTargetCharacterCache()
    end

    local function refreshTargetCharacterCache(character)
        cachedTargetCharacter = character
        cachedTargetHumanoid = character and character:FindFirstChildOfClass("Humanoid")
        cachedTargetHead = character and character:FindFirstChild("Head")
        cachedTargetRootPart = character and character:FindFirstChild("HumanoidRootPart")
        cachedTargetUpperTorso = character and character:FindFirstChild("UpperTorso")
        cachedTargetTorso = character and character:FindFirstChild("Torso")
        cachedTargetLowerTorso = character and character:FindFirstChild("LowerTorso")
    end

    refreshCharacterCache(LocalPlayer.Character)
    refreshBackpackCache()

    LocalPlayer.CharacterAdded:Connect(function(character)
        refreshCharacterCache(character)
    end)

    LocalPlayer.CharacterRemoving:Connect(function(character)
        if currentCharacter == character then
            currentCharacter = nil
            currentHumanoid = nil
            currentRootPart = nil
        end
    end)

    LocalPlayer.ChildAdded:Connect(function(child)
        if child:IsA("Backpack") then
            currentBackpack = child
        end
    end)

    LocalPlayer.ChildRemoved:Connect(function(child)
        if child == currentBackpack then
            currentBackpack = nil
        end
    end)

    local function setJumpPower(value)
        local humanoid = getHumanoid()
        if not humanoid then
            notify("JumpPower", "Humanoid was not found.")
            return
        end

        humanoid.UseJumpPower = true
        humanoid.JumpPower = value
    end

    local function checkJumpPower()
        local humanoid = getHumanoid()
        if not humanoid then
            notify("JumpPower", "Humanoid was not found.")
            return
        end

        notify(
            "JumpPower",
            "Current: " .. tostring(humanoid.JumpPower) .. " | UseJumpPower: " .. tostring(humanoid.UseJumpPower)
        )
    end

    local function setWalkSpeed(value)
        local humanoid = getHumanoid()
        if not humanoid then
            notify("WalkSpeed", "Humanoid was not found.")
            return
        end

        humanoid.WalkSpeed = value
    end

    local function checkWalkSpeed()
        local humanoid = getHumanoid()
        if not humanoid then
            notify("WalkSpeed", "Humanoid was not found.")
            return
        end

        notify("WalkSpeed", "Current: " .. tostring(humanoid.WalkSpeed))
    end

    local function resetCharacterFromLongFall()
        local humanoid = getHumanoid()
        if not humanoid or humanoid.Health <= 0 then
            return
        end

        pcall(function()
            humanoid.Health = 0
        end)
    end

    local function setAutoResetLongFallEnabled(enabled)
        autoResetLongFallEnabled = enabled == true
        longFallStartTime = nil
        longFallCheckAccumulator = 0

        if autoResetLongFallConnection then
            autoResetLongFallConnection:Disconnect()
            autoResetLongFallConnection = nil
        end

        if not autoResetLongFallEnabled then
            return
        end

        autoResetLongFallConnection = RunService.Heartbeat:Connect(function(deltaTime)
            longFallCheckAccumulator += deltaTime
            if longFallCheckAccumulator < LONG_FALL_CHECK_INTERVAL then
                return
            end

            longFallCheckAccumulator = 0

            local humanoid = getHumanoid()
            local rootPart = getRootPart()
            if not humanoid or not rootPart or humanoid.Health <= 0 then
                longFallStartTime = nil
                return
            end

            local isFreeFalling = humanoid:GetState() == Enum.HumanoidStateType.Freefall
            local downwardVelocity = rootPart.AssemblyLinearVelocity and rootPart.AssemblyLinearVelocity.Y or
                rootPart.Velocity.Y
            local isFallingDownward = downwardVelocity < -2

            if isFreeFalling and isFallingDownward then
                if not longFallStartTime then
                    longFallStartTime = os.clock()
                    return
                end

                if os.clock() - longFallStartTime >= LONG_FALL_RESET_DURATION then
                    longFallStartTime = nil
                    notify("Long Fall Reset", "Freefall exceeded 2 seconds. Resetting character.")
                    resetCharacterFromLongFall()
                end
                return
            end

            longFallStartTime = nil
        end)
    end

    local function getAllOwnedTools()
        local character = getCharacter()
        local backpack = getBackpack()
        local tools = {}
        local count = 0

        if backpack then
            for _, tool in ipairs(backpack:GetChildren()) do
                if tool:IsA("Tool") then
                    count += 1
                    tools[count] = tool
                end
            end
        end

        if character then
            for _, tool in ipairs(character:GetChildren()) do
                if tool:IsA("Tool") then
                    count += 1
                    tools[count] = tool
                end
            end
        end

        return tools, character, backpack
    end

    local function forceUnequipTools(character)
        local humanoid = getHumanoid()
        if humanoid and humanoid.Parent == character then
            pcall(function()
                humanoid:UnequipTools()
            end)
        end
    end

    local function setEquippedToolsState(showNotification)
        local tools, character, backpack = getAllOwnedTools()
        if not backpack then
            if showNotification ~= false then
                notify("Equip Tools", "Backpack was not found.")
            end
            return false, 0
        end

        local equipLimit = math.clamp(math.floor(equippedToolCount), 0, #tools)
        local equipped = 0
        local unequipped = 0

        for index = 1, #tools do
            local tool = tools[index]
            if index <= equipLimit then
                if tool.Parent ~= character then
                    tool.Parent = character
                    equipped += 1
                end
            elseif tool.Parent ~= backpack then
                tool.Parent = backpack
                unequipped += 1
            end
        end

        if equipLimit <= 0 then
            forceUnequipTools(character)
        end

        if showNotification ~= false then
            notify(
                "Equip Tools",
                "Target equipped: " .. tostring(equipLimit) .. " | Equipped now: " .. tostring(equipped) ..
                    " | Moved back: " .. tostring(unequipped)
            )
        end

        return true, equipLimit
    end

    local function equipConfiguredTools()
        return setEquippedToolsState(true)
    end

    local function activateAllEquippedTools()
        local now = os.clock()
        if now - lastUseAllToolsTime < 0.15 then
            return
        end

        lastUseAllToolsTime = now

        local character = getCharacter()
        local activated = 0

        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then
                activated += 1
                pcall(function()
                    child:Activate()
                end)
            end
        end

        if activated == 0 then
            notify("Use All Tools", "No equipped tools were found.")
        end

        return activated
    end

    local function activateAllEquippedToolsSilent()
        local now = os.clock()
        if now - lastUseAllToolsTime < 0.15 then
            return
        end

        lastUseAllToolsTime = now

        local character = getCharacter()
        local activated = 0

        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then
                activated += 1
                pcall(function()
                    child:Activate()
                end)
            end
        end

        return activated
    end

    local function setUseAllToolsOnClickEnabled(value)
        useAllToolsOnClickEnabled = value == true

        if useAllToolsConnection then
            useAllToolsConnection:Disconnect()
            useAllToolsConnection = nil
        end

        if not useAllToolsOnClickEnabled then
            return
        end

        useAllToolsConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed or not useAllToolsOnClickEnabled then
                return
            end

            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                local activated = activateAllEquippedToolsSilent()
                if activated and activated > 0 then
                    local character = getCharacter()
                    task.delay(TOOL_USE_RESET_DELAY, function()
                        local currentLiveCharacter = LocalPlayer.Character
                        if currentLiveCharacter == character then
                            forceUnequipTools(character)
                        elseif currentLiveCharacter then
                            forceUnequipTools(currentLiveCharacter)
                        end
                    end)
                end
            end
        end)
    end

    local function findLocalTycoon()
        if localTycoonCache and localTycoonCache.Parent then
            return localTycoonCache
        end

        local now = os.clock()
        if now - lastLocalTycoonRefresh < TYCOON_CACHE_INTERVAL then
            return nil
        end

        lastLocalTycoonRefresh = now
        local tycoonDirectory = Workspace:FindFirstChild("TycoonDirectory")
        if not tycoonDirectory then
            localTycoonCache = nil
            return nil
        end

        local playerName = LocalPlayer.Name
        for _, tycoon in ipairs(tycoonDirectory:GetChildren()) do
            if tycoon:IsA("Model") and string.find(tycoon.Name, playerName, 1, true) then
                localTycoonCache = tycoon
                return localTycoonCache
            end
        end

        localTycoonCache = nil
        return nil
    end

    local function getCachedCollectorTouchPart()
        local tycoon = findLocalTycoon()
        if not tycoon then
            cachedCollectorTycoon = nil
            cachedCollectorTouchPart = nil
            return nil
        end

        if cachedCollectorTycoon ~= tycoon or not cachedCollectorTouchPart or cachedCollectorTouchPart.Parent == nil then
            cachedCollectorTycoon = tycoon
            local collector = tycoon:FindFirstChild("BasicCollector")
            cachedCollectorTouchPart = collector and collector:FindFirstChild("Touch")
        end

        if cachedCollectorTouchPart and cachedCollectorTouchPart:IsA("BasePart") then
            return cachedCollectorTouchPart
        end

        return nil
    end

    local function hideLaserDoor(laserDoor)
        if not laserDoor or not laserDoor.Parent or hiddenLaserDoors[laserDoor] then
            return false
        end

        hiddenLaserDoors[laserDoor] = laserDoor.Parent
        laserDoor.Parent = nil
        return true
    end

    local function getTycoonDirectory()
        return Workspace:FindFirstChild("TycoonDirectory")
    end

    local function disableLaserDoors()
        local tycoonDirectory = getTycoonDirectory()
        if not tycoonDirectory then
            notify("Laser Doors", "TycoonDirectory was not found.")
            return
        end

        local hiddenCount = 0
        for _, descendant in ipairs(tycoonDirectory:GetDescendants()) do
            if descendant.Name == "doorLasers" then
                if hideLaserDoor(descendant) then
                    hiddenCount += 1
                end
            end
        end

        if laserDoorWatcher then
            laserDoorWatcher:Disconnect()
            laserDoorWatcher = nil
        end

        laserDoorWatcher = tycoonDirectory.DescendantAdded:Connect(function(descendant)
            if laserDoorsDisabled and descendant.Name == "doorLasers" then
                hideLaserDoor(descendant)
            end
        end)

        notify("Laser Doors", "Hidden: " .. tostring(hiddenCount))
    end

    local function restoreLaserDoors()
        if laserDoorWatcher then
            laserDoorWatcher:Disconnect()
            laserDoorWatcher = nil
        end

        local restoredCount = 0
        for laserDoor, originalParent in pairs(hiddenLaserDoors) do
            if laserDoor and originalParent then
                laserDoor.Parent = originalParent
                restoredCount += 1
            end
            hiddenLaserDoors[laserDoor] = nil
        end

        notify("Laser Doors", "Restored: " .. tostring(restoredCount))
    end

    local function setLaserDoorsDisabled(value)
        laserDoorsDisabled = value == true

        if laserDoorsDisabled then
            disableLaserDoors()
        else
            restoreLaserDoors()
        end
    end

    local function autoCollectCashLoop()
        if autoCollectCashRunning then
            return
        end

        local sessionId = autoCollectCashSession
        autoCollectCashRunning = true

        while autoCollectCashEnabled and autoCollectCashSession == sessionId do
            local rootPart = getRootPart()
            local touchPart = getCachedCollectorTouchPart()

            if rootPart and touchPart and touchPart:IsA("BasePart") then
                pcall(function()
                    firetouchinterest(rootPart, touchPart, 0)
                    task.wait(0.1)
                    firetouchinterest(rootPart, touchPart, 1)
                end)

                task.wait(autoCollectCashDelay)
            else
                task.wait(math.max(autoCollectCashDelay, IDLE_AUTO_COLLECT_DELAY))
            end
        end

        autoCollectCashRunning = false
    end

    local function setAutoCollectCashEnabled(value)
        autoCollectCashEnabled = value == true
        autoCollectCashSession += 1

        if autoCollectCashEnabled then
            task.spawn(autoCollectCashLoop)
        end
    end

    local function collectBasicPowerSpawns()
        local spawns = {}
        local count = 0
        local descendants = Workspace:GetDescendants()

        for index = 1, #descendants do
            local descendant = descendants[index]
            if descendant:IsA("Model") and descendant.Name == "BasicPowerSpawn" then
                local touchPart = descendant:FindFirstChild("touchPart")
                if touchPart and touchPart:IsA("BasePart") then
                    count += 1
                    spawns[count] = touchPart
                end
            end

            if index % SCAN_BATCH_SIZE == 0 then
                task.wait()
            end
        end

        return spawns
    end

    local function getAllTools()
        if isCollecting then
            notify("Get All Tools", "Collection is already running.")
            return
        end

        local backpack = getBackpack()
        if not backpack then
            notify("Get All Tools", "Backpack was not found.")
            return
        end

        local rootPart = getRootPart()
        if not rootPart then
            notify("Get All Tools", "HumanoidRootPart was not found.")
            return
        end

        isCollecting = true
        local success, errorMessage = xpcall(function()
            local touchParts = collectBasicPowerSpawns()
            local touched = 0
            local failed = 0

            for index = 1, #touchParts do
                local touchPart = touchParts[index]
                local touchSuccess = pcall(function()
                    firetouchinterest(rootPart, touchPart, 0)
                    task.wait(0.05)
                    firetouchinterest(rootPart, touchPart, 1)
                end)

                if touchSuccess then
                    touched += 1
                else
                    failed += 1
                end

                if index % TOUCH_BATCH_SIZE == 0 then
                    task.wait()
                end
            end

            notify(
                "Get All Tools",
                "Touched spawns: " .. tostring(touched) .. " | Failed: " .. tostring(failed)
            )
        end, debug.traceback)

        if not success then
            warn(errorMessage)
            notify("Get All Tools", "An error occurred while collecting tools.")
        end

        isCollecting = false
    end

    local function getTargetablePlayerNames()
        local options = {}

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                options[#options + 1] = player.Name
            end
        end

        table.sort(options)
        return options
    end

    local function normalizeDropdownValue(value)
        if type(value) == "table" then
            return value[1]
        end

        return value
    end

    local function resolveSelectedTargetPlayer()
        if not selectedTargetPlayerName or selectedTargetPlayerName == "" then
            invalidateTargetCache()
            return nil
        end

        if cachedTargetPlayer and cachedTargetPlayer.Parent == Players and cachedTargetPlayer.Name == selectedTargetPlayerName then
            return cachedTargetPlayer
        end

        cachedTargetPlayer = Players:FindFirstChild(selectedTargetPlayerName)
        invalidateTargetCharacterCache()
        return cachedTargetPlayer
    end

    local function refreshTargetPlayerDropdown()
        if not targetPlayerDropdown then
            return
        end

        local options = getTargetablePlayerNames()
        pcall(function()
            if targetPlayerDropdown.SetValues then
                targetPlayerDropdown:SetValues(options)
            end
        end)

        if selectedTargetPlayerName and not table.find(options, selectedTargetPlayerName) then
            selectedTargetPlayerName = nil
            invalidateTargetCache()
            lastDeadTargetCharacter = nil
            resetAimCursorCache()
        end

        if selectedTargetPlayerName then
            pcall(function()
                targetPlayerDropdown:SetValue(selectedTargetPlayerName)
            end)
        end
    end

    local function getTargetAimPosition(targetPlayer)
        local character = targetPlayer and targetPlayer.Character
        if not character then
            invalidateTargetCharacterCache()
            return nil
        end

        local shouldRefresh = character ~= cachedTargetCharacter or not cachedTargetRootPart or not cachedTargetHumanoid
        if targetAimPartMode == "Head" and not cachedTargetHead then
            shouldRefresh = true
        end

        if shouldRefresh then
            refreshTargetCharacterCache(character)
        end

        local head = cachedTargetHead
        local humanoidRootPart = cachedTargetRootPart
        local upperTorso = cachedTargetUpperTorso
        local torso = cachedTargetTorso
        local lowerTorso = cachedTargetLowerTorso

        if targetAimPartMode == "Head" then
            if head then
                return head.Position
            end

            if humanoidRootPart then
                return humanoidRootPart.Position + Vector3.new(0, 1.5, 0)
            end
        elseif targetAimPartMode == "HumanoidRootPart" then
            if humanoidRootPart then
                return humanoidRootPart.Position + Vector3.new(0, 1.5, 0)
            end

            if head then
                return head.Position
            end
        elseif targetAimPartMode == CENTER_MASS_AIM_MODE then
            if upperTorso then
                return upperTorso.Position
            end

            if torso then
                return torso.Position
            end

            if lowerTorso then
                return lowerTorso.Position
            end

            if humanoidRootPart then
                return humanoidRootPart.Position + Vector3.new(0, 1.0, 0)
            end

            if head then
                return head.Position
            end
        end

        if head then
            return head.Position
        end

        if upperTorso then
            return upperTorso.Position
        end

        if torso then
            return torso.Position
        end

        if humanoidRootPart then
            return humanoidRootPart.Position + Vector3.new(0, 1.5, 0)
        end

        local success, pivot = pcall(function()
            return character:GetPivot()
        end)

        if success and pivot then
            return pivot.Position
        end

        return nil
    end

    local function getTargetLookVector(targetPlayer)
        local character = targetPlayer and targetPlayer.Character
        if not character then
            invalidateTargetCharacterCache()
            return nil
        end

        if character ~= cachedTargetCharacter or (not cachedTargetRootPart and not cachedTargetHead) then
            refreshTargetCharacterCache(character)
        end

        local humanoidRootPart = cachedTargetRootPart
        if humanoidRootPart then
            return humanoidRootPart.CFrame.LookVector
        end

        local head = cachedTargetHead
        if head then
            return head.CFrame.LookVector
        end

        local success, pivot = pcall(function()
            return character:GetPivot()
        end)

        if success and pivot then
            return pivot.LookVector
        end

        return nil
    end

    local function moveMouseToViewportPosition(x, y)
        local targetX = x + cachedGuiInset.X
        local targetY = y + cachedGuiInset.Y

        if lastMouseTargetX and math.abs(targetX - lastMouseTargetX) < MOUSE_MOVE_EPSILON and
            math.abs(targetY - lastMouseTargetY) < MOUSE_MOVE_EPSILON then
            return true
        end

        lastMouseTargetX = targetX
        lastMouseTargetY = targetY

        if mousemoverel then
            local currentMouseLocation = UserInputService:GetMouseLocation()
            local deltaX = targetX - currentMouseLocation.X
            local deltaY = targetY - currentMouseLocation.Y

            local success = pcall(function()
                mousemoverel(deltaX, deltaY)
            end)

            if success then
                return true
            end
        end

        if mousemoveabs then
            local success = pcall(function()
                mousemoveabs(targetX, targetY)
            end)

            if success then
                return true
            end
        end

        if VirtualInputManager then
            local success = pcall(function()
                VirtualInputManager:SendMouseMoveEvent(targetX, targetY, game)
            end)

            if success then
                return true
            end
        end

        return false
    end

    local function updateCameraNearTarget(camera, targetPosition, lookVector)
        if not camera or not targetPosition or not lookVector then
            return false
        end

        local unitLookVector = lookVector.Magnitude > 0 and lookVector.Unit or Vector3.new(0, 0, -1)
        local cameraHeightOffset = math.max(0.5, targetCameraDistance * 0.2)
        local cameraOffset = (unitLookVector * -targetCameraDistance) + Vector3.new(0, cameraHeightOffset, 0)
        local cameraPosition = targetPosition + cameraOffset

        if (camera.CFrame.Position - cameraPosition).Magnitude < CAMERA_POSITION_EPSILON and
            (camera.Focus.Position - targetPosition).Magnitude < CAMERA_POSITION_EPSILON then
            return true
        end

        camera.CFrame = CFrame.lookAt(cameraPosition, targetPosition)
        camera.Focus = CFrame.new(targetPosition)
        return true
    end

    local function setAimMouseAtTargetEnabled(value)
        aimMouseAtTargetEnabled = value == true

        if aimMouseAtTargetConnection then
            aimMouseAtTargetConnection:Disconnect()
            aimMouseAtTargetConnection = nil
        end

        local camera = Workspace.CurrentCamera

        if not aimMouseAtTargetEnabled then
            aimUpdateAccumulator = 0
            resetAimCursorCache()

            if camera and originalCameraType then
                camera.CameraType = originalCameraType
            end

            if camera and originalCameraSubject then
                camera.CameraSubject = originalCameraSubject
            end

            originalCameraType = nil
            originalCameraSubject = nil
            return
        end

        if not camera then
            notify("Targeting", "CurrentCamera was not found.")
            aimMouseAtTargetEnabled = false
            return
        end

        lastDeadTargetCharacter = nil
        aimUpdateAccumulator = 0
        resetAimCursorCache()
        originalCameraType = camera.CameraType
        originalCameraSubject = camera.CameraSubject
        camera.CameraType = Enum.CameraType.Scriptable

        local function aimAtSelectedTargetTick()
            local targetPlayer = resolveSelectedTargetPlayer()
            if not targetPlayer then
                if aimMouseAtTargetEnabled then
                    notify("Targeting", "Target left the game. Auto aim disabled.")
                    setAimMouseAtTargetEnabled(false)
                end
                return
            end

            local character = targetPlayer.Character
            if character ~= cachedTargetCharacter or not cachedTargetHumanoid then
                refreshTargetCharacterCache(character)
            end

            local humanoid = cachedTargetHumanoid
            if humanoid and humanoid.Health <= 0 then
                if lastDeadTargetCharacter ~= character then
                    lastDeadTargetCharacter = character
                    notify("Targeting", targetPlayer.Name .. " died.")
                end
                return
            end

            if character ~= lastDeadTargetCharacter then
                lastDeadTargetCharacter = nil
            end

            local currentCamera = Workspace.CurrentCamera
            local targetPosition = getTargetAimPosition(targetPlayer)
            local lookVector = getTargetLookVector(targetPlayer)
            if not currentCamera or not targetPosition or not lookVector then
                return
            end

            updateCameraNearTarget(currentCamera, targetPosition, lookVector)

            local screenPoint, onScreen = currentCamera:WorldToViewportPoint(targetPosition)
            if onScreen and screenPoint.Z > 0 then
                moveMouseToViewportPosition(screenPoint.X, screenPoint.Y)
            end
        end

        aimMouseAtTargetConnection = RunService.RenderStepped:Connect(function(deltaTime)
            if aimMouseAtTargetEnabled then
                aimUpdateAccumulator += deltaTime
                if aimUpdateAccumulator < AIM_UPDATE_INTERVAL then
                    return
                end

                aimUpdateAccumulator = 0
                aimAtSelectedTargetTick()
            end
        end)
    end

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

    tabs.Main:AddButton({
        Title = "Check JumpPower",
        Description = "Show current jump settings",
        Callback = function()
            task.spawn(checkJumpPower)
        end
    })

    tabs.Main:AddSlider("UltraPowerJumpPowerSlider", {
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

    tabs.Main:AddButton({
        Title = "Check WalkSpeed",
        Description = "Show current walk speed",
        Callback = function()
            task.spawn(checkWalkSpeed)
        end
    })

    tabs.Main:AddSlider("UltraPowerWalkSpeedSlider", {
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

    tabs.Main:AddToggle("UltraPowerLongFallToggle", {
        Title = "Auto Reset On Long Fall",
        Default = false
    }):OnChanged(function(value)
        setAutoResetLongFallEnabled(value)
    end)

    tabs.Main:AddParagraph({
        Title = "Tools",
        Content = "Tool collection, equip limit, and activation controls."
    })

    tabs.Main:AddButton({
        Title = "Get All Tools",
        Description = "Collect every BasicPowerSpawn tool",
        Callback = function()
            task.spawn(getAllTools)
        end
    })

    tabs.Main:AddSlider("UltraPowerEquippedToolCountSlider", {
        Title = "Equipped Tool Count",
        Default = equippedToolCount,
        Min = 0,
        Max = 20,
        Rounding = 0
    }):OnChanged(function(value)
        equippedToolCount = value
    end)

    tabs.Main:AddButton({
        Title = "Equip First Tools",
        Description = "Equip only the first selected amount of tools",
        Callback = function()
            task.spawn(equipConfiguredTools)
        end
    })

    tabs.Main:AddButton({
        Title = "Use All Equipped Tools",
        Description = "Activate every currently equipped tool once",
        Callback = function()
            task.spawn(function()
                equipConfiguredTools()
                task.wait()
                activateAllEquippedTools()
            end)
        end
    })

    tabs.Main:AddToggle("UltraPowerUseAllToolsOnClickToggle", {
        Title = "Use All Tools On Click",
        Default = false
    }):OnChanged(function(value)
        setUseAllToolsOnClickEnabled(value)
    end)

    tabs.Targeting:AddParagraph({
        Title = "Targeting",
        Content = "These options come from the new Fluent variant. They follow the selected player with camera and cursor."
    })

    local initialTargetOptions = getTargetablePlayerNames()
    selectedTargetPlayerName = initialTargetOptions[1]

    targetPlayerDropdown = tabs.Targeting:AddDropdown("UltraPowerTargetPlayerDropdown", {
        Title = "Target Player",
        Values = initialTargetOptions,
        Multi = false,
        Default = selectedTargetPlayerName
    })

    targetPlayerDropdown:OnChanged(function(value)
        selectedTargetPlayerName = normalizeDropdownValue(value)
        invalidateTargetCache()
        lastDeadTargetCharacter = nil
        resetAimCursorCache()
    end)

    tabs.Targeting:AddButton({
        Title = "Refresh Player List",
        Description = "Refresh online players for target selection",
        Callback = function()
            refreshTargetPlayerDropdown()
        end
    })

    tabs.Targeting:AddDropdown("UltraPowerAimTargetPartDropdown", {
        Title = "Aim Target Part",
        Values = {"Head", "HumanoidRootPart", CENTER_MASS_AIM_MODE},
        Multi = false,
        Default = targetAimPartMode
    }):OnChanged(function(value)
        local selected = normalizeDropdownValue(value)
        if selected and selected ~= "" then
            targetAimPartMode = selected
        end
    end)

    tabs.Targeting:AddSlider("UltraPowerTargetCameraDistanceSlider", {
        Title = "Target Camera Distance",
        Default = targetCameraDistance,
        Min = 0.5,
        Max = 100,
        Rounding = 1
    }):OnChanged(function(value)
        targetCameraDistance = value
    end)

    tabs.Targeting:AddToggle("UltraPowerAimCursorFollowToggle", {
        Title = "Aim Cursor + Follow Camera",
        Default = false
    }):OnChanged(function(value)
        setAimMouseAtTargetEnabled(value)
    end)

    tabs.Tycoon:AddParagraph({
        Title = "Tycoon Automation",
        Content = "Functions below were carried over from your new variant and adapted for the separate Ultra Power game script."
    })

    tabs.Tycoon:AddToggle("UltraPowerRemoveLaserDoorsToggle", {
        Title = "Remove Laser Doors",
        Default = false
    }):OnChanged(function(value)
        task.spawn(function()
            setLaserDoorsDisabled(value)
        end)
    end)

    tabs.Tycoon:AddToggle("UltraPowerAutoCollectCashToggle", {
        Title = "Auto Collect Cash",
        Default = false
    }):OnChanged(function(value)
        setAutoCollectCashEnabled(value)
    end)

    tabs.Settings:AddSlider("UltraPowerAutoCollectCashDelaySlider", {
        Title = "Auto Collect Delay",
        Default = autoCollectCashDelay,
        Min = 0.05,
        Max = 30,
        Rounding = 2
    }):OnChanged(function(value)
        autoCollectCashDelay = value
    end)

    tabs.Settings:AddParagraph({
        Title = "Notes",
        Content = "I only transferred game-specific features from your variant. Auth, backend validation, route dispatching, and duplicate loader code stay in the main loader."
    })

    Players.PlayerAdded:Connect(function()
        task.defer(refreshTargetPlayerDropdown)
    end)

    Players.PlayerRemoving:Connect(function(player)
        if selectedTargetPlayerName == player.Name then
            selectedTargetPlayerName = nil
            invalidateTargetCache()
            lastDeadTargetCharacter = nil
            resetAimCursorCache()
            if aimMouseAtTargetEnabled then
                notify("Targeting", player.Name .. " left the game. Auto aim disabled.")
                setAimMouseAtTargetEnabled(false)
            end
        end

        task.defer(refreshTargetPlayerDropdown)
    end)

    window:SelectTab(1)
    notify("Ultra Power", "Authorized as " .. authTier .. ".")
end
