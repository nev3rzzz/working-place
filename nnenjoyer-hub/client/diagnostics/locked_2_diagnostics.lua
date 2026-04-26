local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LogService = game:GetService("LogService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local WINDOW_TITLE = "N(n)enjoyer Diagnostics"
local WINDOW_SUBTITLE = "Locked 2"
local LOG_LIMIT = 350
local ATTR_SCAN_INTERVAL = 0.5
local SUMMARY_INTERVAL = 1

local config = {
    recordTelemetry = true,
    logConsoleMessages = true,
    speedSpikeThreshold = 38,
    correctionDeltaThreshold = 14,
    teleportDistanceThreshold = 18,
    highAccelerationThreshold = 95
}

local state = {
    character = nil,
    humanoid = nil,
    root = nil,
    lastPosition = nil,
    lastVelocitySpeed = 0,
    lastSampleClock = os.clock(),
    attrAccumulator = 0,
    summaryAccumulator = 0,
    samples = 0,
    maxDeltaSpeed = 0,
    maxVelocitySpeed = 0,
    maxCorrectionDelta = 0,
    maxAcceleration = 0,
    speedSpikeCount = 0,
    correctionCount = 0,
    teleportCount = 0,
    humanoidChangeCount = 0,
    attributeChangeCount = 0,
    consoleWarningCount = 0,
    lastAttributes = {},
    startedAt = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time())
}

local connections = {}
local logs = {}
local window = nil
local statusParagraph = nil
local summaryParagraph = nil
local riskParagraph = nil
local recordToggle = nil
local consoleToggle = nil
local muted = false

local function nowStamp()
    return os.date("!%H:%M:%S", os.time())
end

local function trimText(value, limit)
    local text = tostring(value or "")
    if #text <= limit then
        return text
    end

    return text:sub(1, limit - 3) .. "..."
end

local function notify(title, content, duration)
    if muted then
        return
    end

    Fluent:Notify({
        Title = title,
        Content = content,
        Duration = duration or 4
    })
end

local function pushLog(kind, message)
    local line = string.format("[%s] [%s] %s", nowStamp(), kind, tostring(message))
    logs[#logs + 1] = line

    if #logs > LOG_LIMIT then
        table.remove(logs, 1)
    end

    print("[Locked2Diagnostics] " .. line)
end

local function setParagraph(paragraph, title, content)
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
        elseif paragraph.Set then
            paragraph:Set({
                Title = title,
                Content = content
            })
        end
    end)
end

local function horizontal(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

local function getKeyStateText()
    local keys = {}
    local watchedKeys = {
        W = Enum.KeyCode.W,
        A = Enum.KeyCode.A,
        S = Enum.KeyCode.S,
        D = Enum.KeyCode.D,
        LeftShift = Enum.KeyCode.LeftShift,
        RightShift = Enum.KeyCode.RightShift,
        LeftAlt = Enum.KeyCode.LeftAlt,
        RightCtrl = Enum.KeyCode.RightControl
    }

    for name, keyCode in pairs(watchedKeys) do
        if UserInputService:IsKeyDown(keyCode) then
            keys[#keys + 1] = name
        end
    end

    table.sort(keys)
    return #keys > 0 and table.concat(keys, "+") or "none"
end

local function getRiskText()
    local risk = "low"
    local reasons = {}

    if state.teleportCount > 0 then
        risk = "high"
        reasons[#reasons + 1] = "large root position jumps"
    end

    if state.correctionCount >= 3 then
        risk = "high"
        reasons[#reasons + 1] = "position delta differs from physics velocity"
    elseif state.correctionCount > 0 and risk ~= "high" then
        risk = "medium"
        reasons[#reasons + 1] = "some position correction-like movement"
    end

    if state.speedSpikeCount >= 5 then
        risk = risk == "high" and "high" or "medium"
        reasons[#reasons + 1] = "repeated high horizontal speed"
    end

    if state.humanoidChangeCount > 0 then
        risk = risk == "high" and "high" or "medium"
        reasons[#reasons + 1] = "Humanoid movement properties changed"
    end

    if #reasons == 0 then
        reasons[#reasons + 1] = "no suspicious local movement patterns yet"
    end

    return string.format("Risk: %s\nReasons: %s", risk, table.concat(reasons, ", "))
end

local function getSummaryText()
    local root = state.root
    local humanoid = state.humanoid
    local velocitySpeed = root and horizontal(root.AssemblyLinearVelocity or root.Velocity).Magnitude or 0

    return table.concat({
        "PlaceId: " .. tostring(game.PlaceId),
        "Keys: " .. getKeyStateText(),
        string.format("Current physics speed: %.1f", velocitySpeed),
        string.format("Max delta speed: %.1f", state.maxDeltaSpeed),
        string.format("Max physics speed: %.1f", state.maxVelocitySpeed),
        string.format("Max correction delta: %.1f", state.maxCorrectionDelta),
        string.format("Max acceleration: %.1f", state.maxAcceleration),
        "Speed spikes: " .. tostring(state.speedSpikeCount),
        "Correction-like events: " .. tostring(state.correctionCount),
        "Large position jumps: " .. tostring(state.teleportCount),
        "Humanoid changes: " .. tostring(state.humanoidChangeCount),
        "Attribute changes: " .. tostring(state.attributeChangeCount),
        "Console warnings/errors: " .. tostring(state.consoleWarningCount),
        "Humanoid WalkSpeed: " .. tostring(humanoid and humanoid.WalkSpeed or "n/a"),
        "Humanoid state: " .. tostring(humanoid and humanoid:GetState() or "n/a")
    }, "\n")
end

local function buildExportText()
    local header = {
        "N(n)enjoyer Locked 2 Diagnostics",
        "Started: " .. state.startedAt,
        "Exported: " .. os.date("!%Y-%m-%dT%H:%M:%SZ", os.time()),
        "UserId: " .. tostring(LocalPlayer.UserId),
        "Username: " .. tostring(LocalPlayer.Name),
        "PlaceId: " .. tostring(game.PlaceId),
        "JobId: " .. tostring(game.JobId),
        "",
        getRiskText(),
        "",
        getSummaryText(),
        "",
        "Logs:"
    }

    return table.concat(header, "\n") .. "\n" .. table.concat(logs, "\n")
end

local function exportLog()
    local text = buildExportText()
    local copied = false

    if setclipboard then
        pcall(function()
            setclipboard(text)
            copied = true
        end)
    end

    if writefile then
        pcall(function()
            if makefolder and (not isfolder or not isfolder("NenjoyerHub")) then
                makefolder("NenjoyerHub")
            end
            if makefolder and (not isfolder or not isfolder("NenjoyerHub/Diagnostics")) then
                makefolder("NenjoyerHub/Diagnostics")
            end

            local fileName = "NenjoyerHub/Diagnostics/locked2_" .. tostring(os.time()) .. ".txt"
            writefile(fileName, text)
            pushLog("export", "wrote " .. fileName)
        end)
    end

    notify("Diagnostics", copied and "Report copied to clipboard." or "Report printed/export attempted.", 4)
    print(text)
end

local function snapshotAttributes(instance)
    if not instance then
        return {}
    end

    local ok, attributes = pcall(function()
        return instance:GetAttributes()
    end)

    return ok and attributes or {}
end

local function diffAttributes(label, instance)
    local key = label
    local previous = state.lastAttributes[key] or {}
    local current = snapshotAttributes(instance)

    for name, value in pairs(current) do
        if previous[name] ~= value then
            state.attributeChangeCount += 1
            pushLog("attr", string.format("%s.%s: %s -> %s", label, name, tostring(previous[name]), tostring(value)))
        end
    end

    for name, value in pairs(previous) do
        if current[name] == nil then
            state.attributeChangeCount += 1
            pushLog("attr", string.format("%s.%s removed (was %s)", label, name, tostring(value)))
        end
    end

    state.lastAttributes[key] = current
end

local function disconnectCharacterConnections()
    for name, connection in pairs(connections) do
        if string.sub(name, 1, 5) == "char:" and connection then
            connection:Disconnect()
            connections[name] = nil
        end
    end
end

local function watchHumanoidProperty(propertyName)
    local humanoid = state.humanoid
    if not humanoid then
        return
    end

    local connectionName = "char:humanoid:" .. propertyName
    connections[connectionName] = humanoid:GetPropertyChangedSignal(propertyName):Connect(function()
        state.humanoidChangeCount += 1
        pushLog("humanoid", propertyName .. " -> " .. tostring(humanoid[propertyName]))
    end)
end

local function watchCharacter(character)
    disconnectCharacterConnections()

    state.character = character
    state.humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
    state.root = character and character:FindFirstChild("HumanoidRootPart") or nil
    state.lastPosition = state.root and state.root.Position or nil
    state.lastVelocitySpeed = 0
    state.lastAttributes = {}

    pushLog("character", "attached character " .. tostring(character and character.Name or "nil"))

    if character then
        connections["char:childAdded"] = character.ChildAdded:Connect(function(child)
            if child.Name == "HumanoidRootPart" or child:IsA("Humanoid") then
                task.defer(function()
                    watchCharacter(character)
                end)
            else
                pushLog("child", "added " .. child.ClassName .. " " .. child.Name)
            end
        end)

        connections["char:childRemoved"] = character.ChildRemoved:Connect(function(child)
            pushLog("child", "removed " .. child.ClassName .. " " .. child.Name)
        end)
    end

    if state.humanoid then
        for _, propertyName in ipairs({
            "WalkSpeed",
            "JumpPower",
            "JumpHeight",
            "UseJumpPower",
            "AutoRotate",
            "PlatformStand"
        }) do
            watchHumanoidProperty(propertyName)
        end

        connections["char:humanoidState"] = state.humanoid.StateChanged:Connect(function(oldState, newState)
            pushLog("state", tostring(oldState) .. " -> " .. tostring(newState))
        end)
    end

    if state.root then
        connections["char:rootAnchored"] = state.root:GetPropertyChangedSignal("Anchored"):Connect(function()
            pushLog("root", "Anchored -> " .. tostring(state.root.Anchored))
        end)
    end

    diffAttributes("character", state.character)
    diffAttributes("humanoid", state.humanoid)
    diffAttributes("root", state.root)
end

local function sampleMovement(deltaTime)
    if not config.recordTelemetry then
        return
    end

    local root = state.root
    if not root or not root.Parent then
        local character = LocalPlayer.Character
        if character ~= state.character then
            watchCharacter(character)
        end
        return
    end

    local position = root.Position
    local velocitySpeed = horizontal(root.AssemblyLinearVelocity or root.Velocity).Magnitude
    state.maxVelocitySpeed = math.max(state.maxVelocitySpeed, velocitySpeed)

    if not state.lastPosition then
        state.lastPosition = position
        state.lastVelocitySpeed = velocitySpeed
        return
    end

    local clampedDelta = math.max(math.min(deltaTime, 0.1), 1 / 240)
    local deltaPosition = horizontal(position - state.lastPosition)
    local deltaSpeed = deltaPosition.Magnitude / clampedDelta
    local correctionDelta = math.abs(deltaSpeed - velocitySpeed)
    local acceleration = math.abs(velocitySpeed - state.lastVelocitySpeed) / clampedDelta

    state.samples += 1
    state.maxDeltaSpeed = math.max(state.maxDeltaSpeed, deltaSpeed)
    state.maxCorrectionDelta = math.max(state.maxCorrectionDelta, correctionDelta)
    state.maxAcceleration = math.max(state.maxAcceleration, acceleration)

    if deltaSpeed >= config.speedSpikeThreshold then
        state.speedSpikeCount += 1
        pushLog(
            "speed",
            string.format("delta %.1f velocity %.1f keys %s", deltaSpeed, velocitySpeed, getKeyStateText())
        )
    end

    if correctionDelta >= config.correctionDeltaThreshold and deltaSpeed > 4 then
        state.correctionCount += 1
        pushLog(
            "correction",
            string.format("delta %.1f velocity %.1f diff %.1f", deltaSpeed, velocitySpeed, correctionDelta)
        )
    end

    if deltaPosition.Magnitude >= config.teleportDistanceThreshold then
        state.teleportCount += 1
        pushLog(
            "jump",
            string.format("root moved %.1f studs in %.3fs", deltaPosition.Magnitude, clampedDelta)
        )
    end

    if acceleration >= config.highAccelerationThreshold and velocitySpeed > 4 then
        pushLog(
            "accel",
            string.format("accel %.1f velocity %.1f keys %s", acceleration, velocitySpeed, getKeyStateText())
        )
    end

    state.lastPosition = position
    state.lastVelocitySpeed = velocitySpeed
end

window = Fluent:CreateWindow({
    Title = WINDOW_TITLE,
    SubTitle = WINDOW_SUBTITLE,
    TabWidth = 160,
    Size = UDim2.fromOffset(640, 520),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl
})

local tabs = {
    Live = window:AddTab({
        Title = "Live",
        Icon = "activity"
    }),
    Log = window:AddTab({
        Title = "Log",
        Icon = "file-text"
    }),
    Settings = window:AddTab({
        Title = "Settings",
        Icon = "settings"
    })
}

statusParagraph = tabs.Live:AddParagraph({
    Title = "Status",
    Content = "Diagnostics starting..."
})

summaryParagraph = tabs.Live:AddParagraph({
    Title = "Movement Summary",
    Content = "Waiting for samples..."
})

riskParagraph = tabs.Live:AddParagraph({
    Title = "Risk Readout",
    Content = getRiskText()
})

tabs.Log:AddButton({
    Title = "Export Report",
    Description = "Copy and write the diagnostic report when possible",
    Callback = exportLog
})

tabs.Log:AddButton({
    Title = "Clear Log",
    Description = "Clear in-memory diagnostic events",
    Callback = function()
        logs = {}
        pushLog("system", "log cleared")
        notify("Diagnostics", "Log cleared.", 2)
    end
})

recordToggle = tabs.Settings:AddToggle("Locked2DiagRecordTelemetry", {
    Title = "Record Telemetry",
    Description = "Collect movement and property signals",
    Default = config.recordTelemetry
})

recordToggle:OnChanged(function(value)
    config.recordTelemetry = value == true
    pushLog("setting", "recordTelemetry -> " .. tostring(config.recordTelemetry))
end)

consoleToggle = tabs.Settings:AddToggle("Locked2DiagConsoleMessages", {
    Title = "Console Messages",
    Description = "Capture local warnings and errors",
    Default = config.logConsoleMessages
})

consoleToggle:OnChanged(function(value)
    config.logConsoleMessages = value == true
    pushLog("setting", "logConsoleMessages -> " .. tostring(config.logConsoleMessages))
end)

tabs.Settings:AddSlider("Locked2DiagSpeedSpikeThreshold", {
    Title = "Speed Spike Threshold",
    Default = config.speedSpikeThreshold,
    Min = 10,
    Max = 120,
    Rounding = 0
}):OnChanged(function(value)
    config.speedSpikeThreshold = tonumber(value) or config.speedSpikeThreshold
end)

tabs.Settings:AddSlider("Locked2DiagCorrectionThreshold", {
    Title = "Correction Delta Threshold",
    Default = config.correctionDeltaThreshold,
    Min = 4,
    Max = 60,
    Rounding = 0
}):OnChanged(function(value)
    config.correctionDeltaThreshold = tonumber(value) or config.correctionDeltaThreshold
end)

tabs.Settings:AddParagraph({
    Title = "Mode",
    Content = "Read-only diagnostics. Minimize Bind: RightCtrl"
})

connections.playerCharacterAdded = LocalPlayer.CharacterAdded:Connect(function(character)
    task.defer(function()
        task.wait(0.25)
        watchCharacter(character)
    end)
end)

connections.logMessage = LogService.MessageOut:Connect(function(message, messageType)
    if not config.logConsoleMessages then
        return
    end

    local messageTypeText = tostring(messageType)
    if string.find(messageTypeText, "Warning", 1, true) or string.find(messageTypeText, "Error", 1, true) then
        state.consoleWarningCount += 1
        pushLog("console", messageTypeText .. ": " .. trimText(message, 220))
    end
end)

connections.heartbeat = RunService.Heartbeat:Connect(function(deltaTime)
    sampleMovement(deltaTime)

    state.attrAccumulator += deltaTime
    state.summaryAccumulator += deltaTime

    if state.attrAccumulator >= ATTR_SCAN_INTERVAL then
        state.attrAccumulator = 0
        diffAttributes("character", state.character)
        diffAttributes("humanoid", state.humanoid)
        diffAttributes("root", state.root)
    end

    if state.summaryAccumulator >= SUMMARY_INTERVAL then
        state.summaryAccumulator = 0
        setParagraph(statusParagraph, "Status", "Recording: " .. tostring(config.recordTelemetry) .. "\nSamples: " .. tostring(state.samples))
        setParagraph(summaryParagraph, "Movement Summary", getSummaryText())
        setParagraph(riskParagraph, "Risk Readout", getRiskText())
    end
end)

local function shutdown()
    muted = true
    for name, connection in pairs(connections) do
        if connection then
            connection:Disconnect()
        end
        connections[name] = nil
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

getgenv().Locked2Diagnostics = {
    export = exportLog,
    shutdown = shutdown,
    logs = logs,
    state = state
}

watchCharacter(LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait())
window:SelectTab(1)
pushLog("system", "diagnostics loaded")
notify("Diagnostics", "Locked 2 diagnostics loaded.", 4)

return getgenv().Locked2Diagnostics
