return function(context)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")
    local UserInputService = game:GetService("UserInputService")
    local GuiService = game:GetService("GuiService")
    local TweenService = game:GetService("TweenService")
    local CoreGui = game:GetService("CoreGui")
    local ContextActionService = game:GetService("ContextActionService")

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
    local BIND_POPUP_WIDTH = 320
    local BIND_POPUP_HEIGHT = 118

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
    local equipFirstToolsBind = nil
    local aimMouseToggleBind = nil
    local minimizeWindowBind = nil
    local pendingBindAction = nil
    local bindCaptureGui = nil
    local bindCaptureFrame = nil
    local bindCaptureLabel = nil
    local equipBindParagraph = nil
    local aimBindParagraph = nil
    local minimizeBindParagraph = nil
    local aimMouseToggleControl = nil
    local trackedWindowGui = nil
    local trackedWindowFrame = nil
    local trackedWindowScale = nil
    local trackedWindowVisible = true
    local trackedWindowAnimating = false
    local trackedWindowShownPosition = nil
    local trackedWindowToggleOffset = UDim2.fromOffset(0, 18)
    local trackedWindowAnimationStartedAt = 0
    local smoothWindowConnection = nil
    local smoothWindowInputConnection = nil
    local smoothWindowInputEndConnection = nil
    local customBindConnection = nil
    local lastMinimizeToggleTime = 0
    local minimizeActionName = "NNEnjoyerMinimizeAction_" .. tostring(math.random(100000, 999999))
    local minimizeActionBoundKey = nil
    local triggerMinimizeRebind = function() end
    local characterAddedConn = nil
    local characterRemovingConn = nil
    local childAddedConn = nil
    local childRemovingConn = nil
    local playerAddedConn = nil
    local playerRemovingConn = nil
    local notificationsMuted = false

    local function notify(title, content)
        if notificationsMuted then
            return
        end

        Fluent:Notify({
            Title = title,
            Content = content,
            Duration = 5
        })
    end

    local function getGuiParent()
        local hui = nil

        pcall(function()
            if gethui then
                hui = gethui()
            end
        end)

        return hui or CoreGui
    end

    local function setParagraphContent(paragraph, title, content)
        if not paragraph then
            return
        end

        pcall(function()
            if paragraph.SetTitle then
                paragraph:SetTitle(title)
            end
        end)

        pcall(function()
            if paragraph.SetDesc then
                paragraph:SetDesc(content)
            elseif paragraph.SetContent then
                paragraph:SetContent(content)
            end
        end)
    end

    local function bindToDisplayText(bind)
        if not bind then
            return "None"
        end

        return bind.code
    end

    local function createBindFromInput(input)
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then
            return {
                kind = "KeyCode",
                code = input.KeyCode.Name
            }
        end

        return nil
    end

    local function doesBindMatch(bind, input)
        return bind ~= nil and bind.kind == "KeyCode" and input.UserInputType == Enum.UserInputType.Keyboard and
            input.KeyCode.Name == bind.code
    end

    local function updateBindParagraphs()
        setParagraphContent(equipBindParagraph, "Equip Bind", bindToDisplayText(equipFirstToolsBind))
        setParagraphContent(aimBindParagraph, "Aim Bind", bindToDisplayText(aimMouseToggleBind))
        setParagraphContent(minimizeBindParagraph, "Minimize Bind", bindToDisplayText(minimizeWindowBind))
    end

    local function getBindPopupPosition()
        local camera = Workspace.CurrentCamera
        local viewportSize = camera and camera.ViewportSize or Vector2.new(1280, 720)
        local popupX = math.floor((viewportSize.X - BIND_POPUP_WIDTH) * 0.5)
        local popupY = 84

        if trackedWindowFrame and trackedWindowFrame.Parent then
            popupX = math.clamp(
                trackedWindowFrame.AbsolutePosition.X + trackedWindowFrame.AbsoluteSize.X - (BIND_POPUP_WIDTH + 20),
                16,
                math.max(16, viewportSize.X - (BIND_POPUP_WIDTH + 16))
            )
            popupY = math.clamp(
                trackedWindowFrame.AbsolutePosition.Y + 78,
                16,
                math.max(16, viewportSize.Y - (BIND_POPUP_HEIGHT + 16))
            )
        end

        return UDim2.fromOffset(popupX, popupY)
    end

    local function destroyBindCapturePopup()
        local currentGui = bindCaptureGui
        local currentFrame = bindCaptureFrame

        bindCaptureGui = nil
        bindCaptureFrame = nil
        bindCaptureLabel = nil

        if currentFrame then
            pcall(function()
                TweenService:Create(currentFrame, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                    BackgroundTransparency = 1,
                    Position = currentFrame.Position + UDim2.fromOffset(0, 8)
                }):Play()
            end)
        end

        if currentGui then
            task.delay(0.16, function()
                pcall(function()
                    currentGui:Destroy()
                end)
            end)
        end
    end

    local function showBindCapturePopup(displayName)
        destroyBindCapturePopup()

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "NNEnjoyerBindCapture"
        screenGui.ResetOnSpawn = false
        screenGui.IgnoreGuiInset = true
        screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        screenGui.Parent = getGuiParent()

        local shadow = Instance.new("Frame")
        shadow.AnchorPoint = Vector2.new(0, 0)
        shadow.Position = getBindPopupPosition() + UDim2.fromOffset(0, 14)
        shadow.Size = UDim2.fromOffset(BIND_POPUP_WIDTH, BIND_POPUP_HEIGHT)
        shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        shadow.BackgroundTransparency = 1
        shadow.BorderSizePixel = 0
        shadow.ZIndex = 9
        shadow.Parent = screenGui

        local shadowCorner = Instance.new("UICorner")
        shadowCorner.CornerRadius = UDim.new(0, 18)
        shadowCorner.Parent = shadow

        local frame = Instance.new("Frame")
        frame.AnchorPoint = Vector2.new(0, 0)
        frame.Position = getBindPopupPosition() + UDim2.fromOffset(0, 10)
        frame.Size = UDim2.fromOffset(BIND_POPUP_WIDTH, BIND_POPUP_HEIGHT)
        frame.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
        frame.BackgroundTransparency = 1
        frame.BorderSizePixel = 0
        frame.ZIndex = 10
        frame.Parent = screenGui

        local frameCorner = Instance.new("UICorner")
        frameCorner.CornerRadius = UDim.new(0, 18)
        frameCorner.Parent = frame

        local frameStroke = Instance.new("UIStroke")
        frameStroke.Color = Color3.fromRGB(68, 115, 255)
        frameStroke.Thickness = 1.5
        frameStroke.Transparency = 0.15
        frameStroke.Parent = frame

        local accent = Instance.new("Frame")
        accent.BackgroundColor3 = Color3.fromRGB(68, 115, 255)
        accent.BackgroundTransparency = 0
        accent.BorderSizePixel = 0
        accent.Size = UDim2.new(1, 0, 0, 4)
        accent.ZIndex = 11
        accent.Parent = frame

        local accentCorner = Instance.new("UICorner")
        accentCorner.CornerRadius = UDim.new(0, 18)
        accentCorner.Parent = accent

        local badge = Instance.new("Frame")
        badge.BackgroundColor3 = Color3.fromRGB(28, 31, 37)
        badge.BackgroundTransparency = 0
        badge.BorderSizePixel = 0
        badge.Position = UDim2.fromOffset(16, 16)
        badge.Size = UDim2.fromOffset(52, 22)
        badge.ZIndex = 11
        badge.Parent = frame

        local badgeCorner = Instance.new("UICorner")
        badgeCorner.CornerRadius = UDim.new(1, 0)
        badgeCorner.Parent = badge

        local badgeText = Instance.new("TextLabel")
        badgeText.BackgroundTransparency = 1
        badgeText.Size = UDim2.fromScale(1, 1)
        badgeText.Font = Enum.Font.GothamBold
        badgeText.Text = "BIND"
        badgeText.TextColor3 = Color3.fromRGB(137, 181, 255)
        badgeText.TextSize = 11
        badgeText.ZIndex = 12
        badgeText.Parent = badge

        local titleLabel = Instance.new("TextLabel")
        titleLabel.BackgroundTransparency = 1
        titleLabel.Position = UDim2.fromOffset(16, 44)
        titleLabel.Size = UDim2.new(1, -32, 0, 24)
        titleLabel.Font = Enum.Font.GothamBold
        titleLabel.Text = displayName
        titleLabel.TextColor3 = Color3.fromRGB(242, 245, 255)
        titleLabel.TextSize = 16
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.ZIndex = 11
        titleLabel.Parent = frame

        local subtitleLabel = Instance.new("TextLabel")
        subtitleLabel.BackgroundTransparency = 1
        subtitleLabel.Position = UDim2.fromOffset(16, 68)
        subtitleLabel.Size = UDim2.new(1, -32, 0, 18)
        subtitleLabel.Font = Enum.Font.Gotham
        subtitleLabel.Text = "Press a keyboard key to assign the bind."
        subtitleLabel.TextColor3 = Color3.fromRGB(175, 181, 196)
        subtitleLabel.TextSize = 13
        subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
        subtitleLabel.ZIndex = 11
        subtitleLabel.Parent = frame

        local infoChip = Instance.new("Frame")
        infoChip.BackgroundColor3 = Color3.fromRGB(24, 27, 33)
        infoChip.BackgroundTransparency = 0
        infoChip.BorderSizePixel = 0
        infoChip.Position = UDim2.fromOffset(16, 88)
        infoChip.Size = UDim2.new(1, -32, 0, 18)
        infoChip.ZIndex = 11
        infoChip.Parent = frame

        local infoChipCorner = Instance.new("UICorner")
        infoChipCorner.CornerRadius = UDim.new(1, 0)
        infoChipCorner.Parent = infoChip

        local infoLabel = Instance.new("TextLabel")
        infoLabel.BackgroundTransparency = 1
        infoLabel.Position = UDim2.fromOffset(10, 0)
        infoLabel.Size = UDim2.new(1, -20, 1, 0)
        infoLabel.Font = Enum.Font.Gotham
        infoLabel.Text = "Backspace clears bind, Esc cancels."
        infoLabel.TextColor3 = Color3.fromRGB(120, 126, 142)
        infoLabel.TextSize = 11
        infoLabel.TextXAlignment = Enum.TextXAlignment.Left
        infoLabel.ZIndex = 12
        infoLabel.Parent = infoChip

        bindCaptureGui = screenGui
        bindCaptureFrame = frame
        bindCaptureLabel = infoLabel

        TweenService:Create(shadow, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0.45,
            Position = getBindPopupPosition() + UDim2.fromOffset(0, 6)
        }):Play()

        TweenService:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0,
            Position = getBindPopupPosition()
        }):Play()
    end

    local function assignBind(actionName, bind)
        if actionName == "equip" then
            equipFirstToolsBind = bind
        elseif actionName == "aim" then
            aimMouseToggleBind = bind
        elseif actionName == "minimize" then
            minimizeWindowBind = bind
            triggerMinimizeRebind()
        end

        updateBindParagraphs()
    end

    local function clearBind(actionName)
        if actionName == "equip" then
            equipFirstToolsBind = nil
        elseif actionName == "aim" then
            aimMouseToggleBind = nil
        elseif actionName == "minimize" then
            minimizeWindowBind = nil
            triggerMinimizeRebind()
        end

        updateBindParagraphs()
    end

    local function beginBindCapture(actionName, displayName)
        pendingBindAction = actionName
        showBindCapturePopup(displayName)
    end

    local function getGuiRoot()
        return getGuiParent() or LocalPlayer:FindFirstChildOfClass("PlayerGui")
    end

    local function findWindowTitleObject(root)
        if not root then
            return nil
        end

        for _, descendant in ipairs(root:GetDescendants()) do
            if (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) and descendant.Text == context.WindowTitle then
                return descendant
            end
        end

        return nil
    end

    local function findWindowFrameFromObject(guiObject)
        local current = guiObject

        while current and current.Parent do
            if current:IsA("GuiObject") and current.AbsoluteSize.X >= 360 and current.AbsoluteSize.Y >= 240 then
                return current
            end

            current = current.Parent
        end

        return nil
    end

    local function findWindowScreenGui(guiObject)
        local current = guiObject

        while current and current.Parent do
            if current:IsA("ScreenGui") then
                return current
            end

            current = current.Parent
        end

        return nil
    end

    local function countWindowMarkerTexts(root)
        if not root then
            return 0
        end

        local wantedTexts = {
            Movement = true,
            Tools = true,
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
            if child:IsA("ScreenGui") then
                table.insert(candidates, child)
            end
        end

        for _, screenGui in ipairs(candidates) do
            if screenGui.Name ~= "NNEnjoyerBindCapture" then
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
        end

        return bestGui, bestFrame
    end

    local function findWindowDragHandle(windowFrame, titleObject)
        local current = titleObject

        while current and current ~= windowFrame do
            if current:IsA("GuiObject") and current.AbsoluteSize.X >= math.floor(windowFrame.AbsoluteSize.X * 0.55) and
                current.AbsoluteSize.Y <= 64 then
                return current
            end

            current = current.Parent
        end

        if titleObject and titleObject.Parent and titleObject.Parent:IsA("GuiObject") then
            return titleObject.Parent
        end

        return titleObject
    end

    local function lerpUDim2(fromValue, toValue, alpha)
        return UDim2.new(
            fromValue.X.Scale + ((toValue.X.Scale - fromValue.X.Scale) * alpha),
            fromValue.X.Offset + ((toValue.X.Offset - fromValue.X.Offset) * alpha),
            fromValue.Y.Scale + ((toValue.Y.Scale - fromValue.Y.Scale) * alpha),
            fromValue.Y.Offset + ((toValue.Y.Offset - fromValue.Y.Offset) * alpha)
        )
    end

    local function captureWindowReferences()
        local root = getGuiRoot()
        if not root then
            return false
        end

        local titleObject = findWindowTitleObject(root)
        local windowFrame = nil
        local windowGui = nil

        if titleObject then
            windowFrame = findWindowFrameFromObject(titleObject)
            if windowFrame then
                windowGui = findWindowScreenGui(windowFrame)
            end
        end

        if not windowGui or not windowFrame then
            windowGui, windowFrame = findWindowFallbackCandidate(root)
        end

        if not windowGui then
            return false
        end

        local scale = nil
        if windowFrame then
            scale = windowFrame:FindFirstChild("NNEnjoyerSmoothScale")
            if not scale then
                scale = Instance.new("UIScale")
                scale.Name = "NNEnjoyerSmoothScale"
                scale.Parent = windowFrame
            end
        end

        trackedWindowGui = windowGui
        trackedWindowFrame = windowFrame
        trackedWindowScale = scale
        trackedWindowVisible = windowGui.Enabled ~= false
        trackedWindowAnimating = false
        trackedWindowShownPosition = windowFrame.Position

        return true, titleObject, windowFrame
    end

    local function tweenWindowVisibility(show)
        if not trackedWindowGui then
            return false
        end

        if not trackedWindowFrame or not trackedWindowScale then
            trackedWindowGui.Enabled = show
            trackedWindowVisible = show
            return true
        end

        if trackedWindowShownPosition == nil then
            trackedWindowShownPosition = trackedWindowFrame.Position
        end

        trackedWindowAnimating = true
        trackedWindowAnimationStartedAt = os.clock()

        if show then
            trackedWindowGui.Enabled = true
            trackedWindowFrame.Visible = true
            trackedWindowVisible = true
            trackedWindowScale.Scale = 0.92
            trackedWindowFrame.Position = trackedWindowShownPosition + UDim2.fromOffset(0, 24)

            local scaleTween = TweenService:Create(trackedWindowScale, TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                Scale = 1
            })

            local positionTween = TweenService:Create(trackedWindowFrame, TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                Position = trackedWindowShownPosition
            })

            local finished = false
            positionTween.Completed:Connect(function()
                finished = true
                trackedWindowAnimating = false
                trackedWindowAnimationStartedAt = 0
            end)

            task.delay(0.45, function()
                if not finished then
                    trackedWindowAnimating = false
                    trackedWindowAnimationStartedAt = 0
                end
            end)

            scaleTween:Play()
            positionTween:Play()
            return true
        end

        trackedWindowShownPosition = trackedWindowFrame.Position

        local scaleTween = TweenService:Create(trackedWindowScale, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            Scale = 0.93
        })

        local positionTween = TweenService:Create(trackedWindowFrame, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            Position = trackedWindowShownPosition + UDim2.fromOffset(0, 24)
        })

        local finished = false
        positionTween.Completed:Connect(function()
            finished = true
            trackedWindowVisible = false
            trackedWindowGui.Enabled = false
            trackedWindowFrame.Visible = true
            trackedWindowFrame.Position = trackedWindowShownPosition
            trackedWindowScale.Scale = 1
            trackedWindowAnimating = false
            trackedWindowAnimationStartedAt = 0
        end)

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

        scaleTween:Play()
        positionTween:Play()
        return true
    end

    local function settleWindowState()
        if not trackedWindowGui then
            return
        end

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
    end

    local function toggleWindowVisibility()
        if not trackedWindowFrame or not trackedWindowGui or not trackedWindowFrame.Parent or not trackedWindowGui.Parent then
            local foundWindow = captureWindowReferences()
            if not foundWindow then
                local fallbackGui = nil
                local fallbackFrame = nil
                fallbackGui, fallbackFrame = findWindowFallbackCandidate(getGuiRoot())
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
            settleWindowState()
        end

        local shouldShow = trackedWindowGui.Enabled == false
        trackedWindowVisible = trackedWindowGui.Enabled ~= false
        return tweenWindowVisibility(shouldShow)
    end

    local function performMinimizeToggle()
        local now = os.clock()
        if now - lastMinimizeToggleTime < 0.15 then
            return
        end

        lastMinimizeToggleTime = now
        task.spawn(function()
            toggleWindowVisibility()
        end)
    end

    local function unbindMinimizeAction()
        if minimizeActionBoundKey then
            pcall(function()
                ContextActionService:UnbindAction(minimizeActionName)
            end)
            minimizeActionBoundKey = nil
        end
    end

    local function rebindMinimizeAction()
        unbindMinimizeAction()

        if not minimizeWindowBind or minimizeWindowBind.kind ~= "KeyCode" then
            return
        end

        local keyCode = Enum.KeyCode[minimizeWindowBind.code]
        if not keyCode then
            return
        end

        local handler = function(_, inputState)
            if inputState == Enum.UserInputState.Begin then
                performMinimizeToggle()
            end
            return Enum.ContextActionResult.Sink
        end

        local success = pcall(function()
            ContextActionService:BindActionAtPriority(
                minimizeActionName,
                handler,
                false,
                Enum.ContextActionPriority.High.Value,
                keyCode
            )
        end)

        if success then
            minimizeActionBoundKey = keyCode
        end
    end

    triggerMinimizeRebind = rebindMinimizeAction

    local function setupSmoothWindow()
        task.spawn(function()
            local titleObject = nil

            for _ = 1, 40 do
                titleObject = findWindowTitleObject(getGuiRoot())
                if titleObject then
                    break
                end

                task.wait(0.1)
            end

            if not titleObject then
                local foundWindow = captureWindowReferences()
                if not foundWindow or not trackedWindowFrame then
                    return
                end

                tweenWindowVisibility(true)
                return
            end

            local foundWindow, _, windowFrame = captureWindowReferences()
            if not foundWindow or not windowFrame then
                return
            end

            local dragHandle = findWindowDragHandle(windowFrame, titleObject) or windowFrame
            tweenWindowVisibility(true)

            if smoothWindowConnection then
                smoothWindowConnection:Disconnect()
                smoothWindowConnection = nil
            end

            if smoothWindowInputConnection then
                smoothWindowInputConnection:Disconnect()
                smoothWindowInputConnection = nil
            end

            if smoothWindowInputEndConnection then
                smoothWindowInputEndConnection:Disconnect()
                smoothWindowInputEndConnection = nil
            end

            local dragging = false
            local activeDragInput = nil
            local dragStartInputPosition = nil
            local dragStartWindowPosition = nil
            local targetWindowPosition = windowFrame.Position

              smoothWindowConnection = RunService.RenderStepped:Connect(function(deltaTime)
                  if dragging then
                      local alpha = 1 - math.exp(-deltaTime * 18)
                      windowFrame.Position = lerpUDim2(windowFrame.Position, targetWindowPosition, alpha)
                      trackedWindowShownPosition = windowFrame.Position
                  end
              end)

            dragHandle.InputBegan:Connect(function(input)
                if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
                    return
                end

                local relativeY = input.Position.Y - windowFrame.AbsolutePosition.Y
                if relativeY > 48 then
                    return
                end

                dragging = true
                activeDragInput = input
                dragStartInputPosition = input.Position
                dragStartWindowPosition = windowFrame.Position
                targetWindowPosition = windowFrame.Position
            end)

            smoothWindowInputConnection = UserInputService.InputChanged:Connect(function(input)
                if not dragging or input ~= activeDragInput or not dragStartInputPosition or not dragStartWindowPosition then
                    return
                end

                local delta = input.Position - dragStartInputPosition
                targetWindowPosition = UDim2.new(
                    dragStartWindowPosition.X.Scale,
                    dragStartWindowPosition.X.Offset + delta.X,
                    dragStartWindowPosition.Y.Scale,
                    dragStartWindowPosition.Y.Offset + delta.Y
                )
            end)

            smoothWindowInputEndConnection = UserInputService.InputEnded:Connect(function(input)
                if input == activeDragInput then
                    dragging = false
                    activeDragInput = nil
                    dragStartInputPosition = nil
                    dragStartWindowPosition = nil
                    trackedWindowShownPosition = windowFrame.Position
                end
            end)
        end)
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

    characterAddedConn = LocalPlayer.CharacterAdded:Connect(function(character)
        refreshCharacterCache(character)
    end)

    characterRemovingConn = LocalPlayer.CharacterRemoving:Connect(function(character)
        if currentCharacter == character then
            currentCharacter = nil
            currentHumanoid = nil
            currentRootPart = nil
        end
    end)

    childAddedConn = LocalPlayer.ChildAdded:Connect(function(child)
        if child:IsA("Backpack") then
            currentBackpack = child
        end
    end)

    childRemovingConn = LocalPlayer.ChildRemoved:Connect(function(child)
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
            if aimMouseToggleControl and aimMouseToggleControl.SetValue then
                pcall(function()
                    aimMouseToggleControl:SetValue(false)
                end)
            end
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
                    if aimMouseToggleControl and aimMouseToggleControl.SetValue then
                        pcall(function()
                            aimMouseToggleControl:SetValue(false)
                        end)
                    else
                        setAimMouseAtTargetEnabled(false)
                    end
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

    tabs.Movement:AddParagraph({
        Title = "Movement",
        Content = "Character movement and recovery controls."
    })

    tabs.Movement:AddButton({
        Title = "Check JumpPower",
        Description = "Show current jump settings",
        Callback = function()
            task.spawn(checkJumpPower)
        end
    })

    tabs.Movement:AddSlider("UltraPowerJumpPowerSlider", {
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

    tabs.Movement:AddButton({
        Title = "Check WalkSpeed",
        Description = "Show current walk speed",
        Callback = function()
            task.spawn(checkWalkSpeed)
        end
    })

    tabs.Movement:AddSlider("UltraPowerWalkSpeedSlider", {
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

    tabs.Movement:AddToggle("UltraPowerLongFallToggle", {
        Title = "Auto Reset On Long Fall",
        Default = false
    }):OnChanged(function(value)
        setAutoResetLongFallEnabled(value)
    end)

    tabs.Tools:AddParagraph({
        Title = "Tools",
        Content = "Tool collection, equip limit, and activation controls."
    })

    tabs.Tools:AddButton({
        Title = "Get All Tools",
        Description = "Collect every BasicPowerSpawn tool",
        Callback = function()
            task.spawn(getAllTools)
        end
    })

    tabs.Tools:AddSlider("UltraPowerEquippedToolCountSlider", {
        Title = "Equipped Tool Count",
        Default = equippedToolCount,
        Min = 0,
        Max = 20,
        Rounding = 0
    }):OnChanged(function(value)
        equippedToolCount = value
    end)

    tabs.Tools:AddButton({
        Title = "Equip First Tools",
        Description = "Equip only the first selected amount of tools",
        Callback = function()
            task.spawn(equipConfiguredTools)
        end
    })

    equipBindParagraph = tabs.Tools:AddParagraph({
        Title = "Equip Bind",
        Content = "None"
    })

    tabs.Tools:AddButton({
        Title = "Set Equip Bind",
        Description = "Open a small popup to set the Equip First Tools bind",
        Callback = function()
            beginBindCapture("equip", "Set Equip First Tools Bind")
        end
    })

    tabs.Tools:AddButton({
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

    tabs.Tools:AddToggle("UltraPowerUseAllToolsOnClickToggle", {
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

    aimMouseToggleControl = tabs.Targeting:AddToggle("UltraPowerAimCursorFollowToggle", {
        Title = "Aim Cursor + Follow Camera",
        Default = false
    })

    aimMouseToggleControl:OnChanged(function(value)
        setAimMouseAtTargetEnabled(value)
    end)

    aimBindParagraph = tabs.Targeting:AddParagraph({
        Title = "Aim Bind",
        Content = "None"
    })

    tabs.Targeting:AddButton({
        Title = "Set Aim Bind",
        Description = "Open a small popup to set the targeting bind",
        Callback = function()
            beginBindCapture("aim", "Set Aim Cursor + Follow Camera Bind")
        end
    })

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

    tabs.Tycoon:AddSlider("UltraPowerAutoCollectCashDelaySlider", {
        Title = "Auto Collect Delay",
        Default = autoCollectCashDelay,
        Min = 0.05,
        Max = 30,
        Rounding = 2
    }):OnChanged(function(value)
        autoCollectCashDelay = value
    end)

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
        Content = "Configure the bind that hides/shows the window below."
    })

    minimizeBindParagraph = tabs.Settings:AddParagraph({
        Title = "Minimize Bind",
        Content = "None"
    })

    tabs.Settings:AddButton({
        Title = "Set Minimize Bind",
        Description = "Open a small popup to set the window minimize bind",
        Callback = function()
            beginBindCapture("minimize", "Set Minimize Window Bind")
        end
    })

    playerAddedConn = Players.PlayerAdded:Connect(function()
        task.defer(refreshTargetPlayerDropdown)
    end)

    playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
        if selectedTargetPlayerName == player.Name then
            selectedTargetPlayerName = nil
            invalidateTargetCache()
            lastDeadTargetCharacter = nil
            resetAimCursorCache()
            if aimMouseAtTargetEnabled then
                notify("Targeting", player.Name .. " left the game. Auto aim disabled.")
                if aimMouseToggleControl and aimMouseToggleControl.SetValue then
                    pcall(function()
                        aimMouseToggleControl:SetValue(false)
                    end)
                else
                    setAimMouseAtTargetEnabled(false)
                end
            end
        end

        task.defer(refreshTargetPlayerDropdown)
    end)

    local function shutdown()
        notificationsMuted = true
        pendingBindAction = nil
        destroyBindCapturePopup()
        unbindMinimizeAction()
        setUseAllToolsOnClickEnabled(false)
        setLaserDoorsDisabled(false)
        setAutoCollectCashEnabled(false)
        setAutoResetLongFallEnabled(false)
        setAimMouseAtTargetEnabled(false)

        if customBindConnection then
            customBindConnection:Disconnect()
            customBindConnection = nil
        end

        if characterAddedConn then
            characterAddedConn:Disconnect()
            characterAddedConn = nil
        end

        if characterRemovingConn then
            characterRemovingConn:Disconnect()
            characterRemovingConn = nil
        end

        if childAddedConn then
            childAddedConn:Disconnect()
            childAddedConn = nil
        end

        if childRemovingConn then
            childRemovingConn:Disconnect()
            childRemovingConn = nil
        end

        if playerAddedConn then
            playerAddedConn:Disconnect()
            playerAddedConn = nil
        end

        if playerRemovingConn then
            playerRemovingConn:Disconnect()
            playerRemovingConn = nil
        end

        if smoothWindowConnection then
            smoothWindowConnection:Disconnect()
            smoothWindowConnection = nil
        end

        if smoothWindowInputConnection then
            smoothWindowInputConnection:Disconnect()
            smoothWindowInputConnection = nil
        end

        if smoothWindowInputEndConnection then
            smoothWindowInputEndConnection:Disconnect()
            smoothWindowInputEndConnection = nil
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

    if Runtime and Runtime.RegisterCleanup then
        Runtime:RegisterCleanup(shutdown)
    end

    updateBindParagraphs()
    window:SelectTab(1)
    setupSmoothWindow()

    customBindConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if pendingBindAction then
            if input.UserInputType ~= Enum.UserInputType.Keyboard then
                return
            end

            if input.KeyCode == Enum.KeyCode.Escape then
                pendingBindAction = nil
                destroyBindCapturePopup()
                notify("Bind Capture", "Cancelled.")
                return
            end

            if input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
                clearBind(pendingBindAction)
                pendingBindAction = nil
                destroyBindCapturePopup()
                notify("Bind Capture", "Bind cleared.")
                return
            end

            local bind = createBindFromInput(input)
            if not bind then
                return
            end

            local actionName = pendingBindAction
            pendingBindAction = nil
            assignBind(actionName, bind)
            destroyBindCapturePopup()
            notify("Bind Capture", "Bound to " .. bind.code)
            return
        end

        if gameProcessed then
            return
        end

        if doesBindMatch(equipFirstToolsBind, input) then
            task.spawn(equipConfiguredTools)
            return
        end

        if doesBindMatch(aimMouseToggleBind, input) then
            local nextValue = not aimMouseAtTargetEnabled
            if aimMouseToggleControl and aimMouseToggleControl.SetValue then
                pcall(function()
                    aimMouseToggleControl:SetValue(nextValue)
                end)
            else
                setAimMouseAtTargetEnabled(nextValue)
            end
        end
    end)

    notify("Ultra Power", "Authorized as " .. authTier .. ".")
    return {
        shutdown = shutdown
    }
end
