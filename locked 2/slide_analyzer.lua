--[[
    Locked 2 - Slide / Dash Analyzer
    UI: Linoria Lib

    Purpose:
      - Capture what happens around the Q slide/dash mechanic.
      - Log local physics changes, Humanoid state, animation tracks, constraints/movers.
      - Passively record client -> server RemoteEvent/RemoteFunction calls during captures.
      - Scan likely local script/module candidates by name/path without relying on hardcoded speeds.

    Notes:
      - This is an analyzer. It does not change WalkSpeed, CFrame, remotes, or physics.
      - Logs are written to workspace/Locked2_SlideAnalyzer.log when writefile/appendfile exist.
--]]

----------------------------------------------------------------
-- Cleanup previous run
----------------------------------------------------------------
if type(getgenv().Locked2SlideAnalyzerCleanup) == "function" then
    pcall(getgenv().Locked2SlideAnalyzerCleanup)
end

----------------------------------------------------------------
-- Linoria Lib bootstrap
----------------------------------------------------------------
local repo = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"

local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

Library.NotifyOnError = true

local Toggles = getgenv().Toggles
local Options = getgenv().Options

----------------------------------------------------------------
-- Services
----------------------------------------------------------------
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local env = getgenv()

----------------------------------------------------------------
-- State
----------------------------------------------------------------
local scriptUnloaded = false
local captureActive = false
local captureId = 0
local captureStartedAt = 0
local captureReason = "manual"
local captureDuration = tonumber(env.Locked2SlideCaptureDuration) or 6
local captureKey = Enum.KeyCode.Q
local sampleInterval = 0.05
local lastSampleAt = 0

local logFileName = "Locked2_SlideAnalyzer.log"
local canWriteFile = type(writefile) == "function"
local canAppendFile = type(appendfile) == "function"

local remoteHookReady = false
local remoteSignalName = "Locked2SlideAnalyzerRemoteSignal"

local maxSpeed = 0
local maxYVelocity = 0
local totalDistance = 0
local startPosition = nil
local lastPosition = nil
local lowSpeedAfterBurstTime = 0
local possibleLockDetected = false

local remoteCounts = {}
local animationCounts = {}
local candidateScripts = {}
local candidateRemotes = {}
local recentLines = {}
local recentLimit = 80
local diskBuffer = {}
local diskBufferLimit = 12000
local remoteLogLimit = 120
local remoteLogCount = 0

----------------------------------------------------------------
-- Connections
----------------------------------------------------------------
local heartbeatConn
local inputBeganConn
local charAddedConn
local animationConn
local statusThread

----------------------------------------------------------------
-- UI refs
----------------------------------------------------------------
local captureStatusLabel
local metricsLabel
local lastRemoteLabel
local lastAnimationLabel
local fileStatusLabel
local scriptCandidatesLabel
local remoteCandidatesLabel

----------------------------------------------------------------
-- Basic helpers
----------------------------------------------------------------
local function now()
    return os.clock()
end

local function wallTime()
    return os.date("%H:%M:%S")
end

local function notify(text, duration)
    pcall(function()
        Library:Notify("[Slide Analyzer] " .. tostring(text), duration or 3)
    end)
end

local function safeSetLabel(label, text)
    if not label then
        return
    end

    pcall(function()
        label:SetText(text)
    end)
end

local function getPath(instance)
    if typeof(instance) ~= "Instance" then
        return tostring(instance)
    end

    local parts = {}
    local current = instance

    while current and current ~= game do
        table.insert(parts, 1, current.Name)
        current = current.Parent
    end

    return table.concat(parts, ".")
end

local function shortNumber(value)
    if type(value) ~= "number" then
        return tostring(value)
    end

    return string.format("%.2f", value)
end

local function shortVector3(value)
    return string.format(
        "(%.2f, %.2f, %.2f)",
        value.X,
        value.Y,
        value.Z
    )
end

local function horizontal(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

local function getCharacterParts()
    local character = player.Character
    if not character then
        return nil, nil, nil
    end

    return character, character:FindFirstChild("HumanoidRootPart"), character:FindFirstChildOfClass("Humanoid")
end

local function getKeyFromOption(optionName, fallback)
    local option = Options and Options[optionName]
    local value = option and option.Value

    if typeof(value) == "EnumItem" and value.EnumType == Enum.KeyCode then
        return value
    end

    if type(value) == "string" and Enum.KeyCode[value] then
        return Enum.KeyCode[value]
    end

    return fallback
end

local function compactText(text, maxLength)
    text = tostring(text or "")
    maxLength = maxLength or 160

    text = text:gsub("[\r\n]+", " ")

    if #text > maxLength then
        return text:sub(1, maxLength - 3) .. "..."
    end

    return text
end

----------------------------------------------------------------
-- Logging
----------------------------------------------------------------
local function pushRecent(line)
    table.insert(recentLines, line)

    while #recentLines > recentLimit do
        table.remove(recentLines, 1)
    end
end

local function rawDiskWrite(text)
    if canAppendFile then
        appendfile(logFileName, text)
        return true
    end

    if canWriteFile then
        local old = ""
        if type(readfile) == "function" and type(isfile) == "function" and isfile(logFileName) then
            pcall(function()
                old = readfile(logFileName)
            end)
        end

        writefile(logFileName, old .. text)
        return true
    end

    return false
end

local function flushLog(force)
    if #diskBuffer == 0 then
        return
    end

    local size = 0
    for _, line in ipairs(diskBuffer) do
        size += #line
    end

    if not force and size < diskBufferLimit then
        return
    end

    local chunk = table.concat(diskBuffer)
    diskBuffer = {}

    pcall(function()
        rawDiskWrite(chunk)
    end)
end

local function log(line)
    local text = "[" .. wallTime() .. "] " .. tostring(line)
    pushRecent(text)
    table.insert(diskBuffer, text .. "\n")
    flushLog(false)
end

local function logSection(title)
    log("")
    log("----------------------------------------------------------------")
    log(title)
    log("----------------------------------------------------------------")
end

local function clearLog()
    recentLines = {}

    if canWriteFile then
        pcall(function()
            writefile(logFileName, "")
        end)
    end

    diskBuffer = {}
    log("Log cleared")
end

----------------------------------------------------------------
-- Value serialization
----------------------------------------------------------------
local function summarizeValue(value, depth, seen)
    depth = depth or 0
    seen = seen or {}

    if depth > 2 then
        return "..."
    end

    local valueType = typeof(value)

    if valueType == "Instance" then
        return "[" .. value.ClassName .. "] " .. getPath(value)
    end

    if valueType == "Vector3" then
        return shortVector3(value)
    end

    if valueType == "Vector2" then
        return string.format("(%.2f, %.2f)", value.X, value.Y)
    end

    if valueType == "CFrame" then
        return "CFrame pos=" .. shortVector3(value.Position)
    end

    if valueType == "EnumItem" then
        return tostring(value)
    end

    if valueType == "Color3" then
        return string.format("Color3(%.2f, %.2f, %.2f)", value.R, value.G, value.B)
    end

    if type(value) == "table" then
        if seen[value] then
            return "{cycle}"
        end

        seen[value] = true

        local parts = {}
        local count = 0

        for key, subValue in pairs(value) do
            count += 1
            if count > 8 then
                table.insert(parts, "...")
                break
            end

            table.insert(parts, tostring(key) .. "=" .. summarizeValue(subValue, depth + 1, seen))
        end

        return "{" .. table.concat(parts, ", ") .. "}"
    end

    if type(value) == "string" then
        return '"' .. compactText(value, 120) .. '"'
    end

    return tostring(value)
end

local function summarizeArgs(...)
    local args = { ... }
    local out = {}

    for index, value in ipairs(args) do
        if index > 10 then
            table.insert(out, "...")
            break
        end

        table.insert(out, "#" .. tostring(index) .. "=" .. summarizeValue(value))
    end

    return table.concat(out, ", ")
end

----------------------------------------------------------------
-- Snapshots
----------------------------------------------------------------
local function collectAttributes(instance)
    if not instance then
        return "(none)"
    end

    local ok, attrs = pcall(function()
        return instance:GetAttributes()
    end)

    if not ok or not attrs then
        return "(unavailable)"
    end

    local parts = {}

    for key, value in pairs(attrs) do
        table.insert(parts, tostring(key) .. "=" .. summarizeValue(value))
    end

    table.sort(parts)

    if #parts == 0 then
        return "(none)"
    end

    return table.concat(parts, ", ")
end

local function collectMovers(character)
    if not character then
        return "(no character)"
    end

    local moverClasses = {
        BodyVelocity = true,
        BodyPosition = true,
        BodyGyro = true,
        BodyAngularVelocity = true,
        LinearVelocity = true,
        AngularVelocity = true,
        VectorForce = true,
        AlignPosition = true,
        AlignOrientation = true,
        Attachment = false,
        BallSocketConstraint = true,
        HingeConstraint = true,
        WeldConstraint = true
    }

    local results = {}

    for _, descendant in ipairs(character:GetDescendants()) do
        if moverClasses[descendant.ClassName] then
            table.insert(results, descendant.ClassName .. ":" .. getPath(descendant))
        end
    end

    if #results == 0 then
        return "(none)"
    end

    table.sort(results)
    return table.concat(results, " | ")
end

local function collectPartStats(character)
    if not character then
        return "(no character)"
    end

    local totalParts = 0
    local nonCollide = 0
    local massless = 0
    local anchored = 0

    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            totalParts += 1

            if descendant.CanCollide == false then
                nonCollide += 1
            end

            if descendant.Massless then
                massless += 1
            end

            if descendant.Anchored then
                anchored += 1
            end
        end
    end

    return "parts=" .. totalParts
        .. " nonCollide=" .. nonCollide
        .. " massless=" .. massless
        .. " anchored=" .. anchored
end

local function logSnapshot(label)
    local character, root, humanoid = getCharacterParts()

    logSection("SNAPSHOT: " .. label)

    if not character or not root or not humanoid then
        log("Character/root/humanoid missing")
        return
    end

    local velocity = root.AssemblyLinearVelocity or root.Velocity
    local angularVelocity = root.AssemblyAngularVelocity or Vector3.new(0, 0, 0)
    local state = humanoid:GetState()

    log("Character: " .. getPath(character))
    log("Humanoid state: " .. tostring(state))
    log("WalkSpeed=" .. shortNumber(humanoid.WalkSpeed)
        .. " JumpPower=" .. shortNumber(humanoid.JumpPower)
        .. " JumpHeight=" .. shortNumber(humanoid.JumpHeight)
        .. " HipHeight=" .. shortNumber(humanoid.HipHeight))
    log("AutoRotate=" .. tostring(humanoid.AutoRotate)
        .. " PlatformStand=" .. tostring(humanoid.PlatformStand)
        .. " Sit=" .. tostring(humanoid.Sit))
    log("MoveDirection=" .. shortVector3(humanoid.MoveDirection))
    log("Position=" .. shortVector3(root.Position))
    log("Velocity=" .. shortVector3(velocity)
        .. " horizontalMag=" .. shortNumber(horizontal(velocity).Magnitude)
        .. " angular=" .. shortVector3(angularVelocity))
    log("Character attributes: " .. collectAttributes(character))
    log("Humanoid attributes: " .. collectAttributes(humanoid))
    log("Movers/constraints: " .. collectMovers(character))
    log("Part stats: " .. collectPartStats(character))
end

----------------------------------------------------------------
-- Script candidate scan
----------------------------------------------------------------
local function isCandidateScript(instance)
    if not (instance:IsA("LocalScript") or instance:IsA("ModuleScript")) then
        return false
    end

    local lower = (instance.Name .. " " .. getPath(instance)):lower()
    local needles = {
        "slide",
        "dash",
        "movement",
        "move",
        "controller",
        "input",
        "stamina",
        "mechanic",
        "ability",
        "run",
        "sprint",
        "q"
    }

    for _, needle in ipairs(needles) do
        if string.find(lower, needle, 1, true) then
            return true
        end
    end

    return false
end

local function scanScriptCandidates()
    candidateScripts = {}
    local scanned = 0
    local scanLimit = 2500

    local containers = {}

    local playerScripts = player:FindFirstChildOfClass("PlayerScripts")
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    local character = player.Character

    if playerScripts then
        table.insert(containers, playerScripts)
    end

    if playerGui then
        table.insert(containers, playerGui)
    end

    if character then
        table.insert(containers, character)
    end

    -- ReplicatedStorage can be huge in this game, so scan only its direct
    -- scripts/modules plus the most likely first-level folders.
    table.insert(containers, ReplicatedStorage)

    for _, container in ipairs(containers) do
        for _, descendant in ipairs(container:GetDescendants()) do
            scanned += 1
            if scanned > scanLimit then
                log("Scan stopped at limit: " .. tostring(scanLimit) .. " descendants")
                break
            end

            if isCandidateScript(descendant) then
                table.insert(candidateScripts, "[" .. descendant.ClassName .. "] " .. getPath(descendant))
            end
        end

        if scanned > scanLimit then
            break
        end
    end

    table.sort(candidateScripts)

    logSection("SCRIPT CANDIDATES")

    if #candidateScripts == 0 then
        log("No obvious slide/dash/movement script candidates found by name/path.")
    else
        for index, path in ipairs(candidateScripts) do
            log(tostring(index) .. ". " .. path)
        end
    end
end

local function isCandidateRemote(instance)
    if not (instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction")) then
        return false
    end

    local lower = (instance.Name .. " " .. getPath(instance)):lower()
    local needles = {
        "slide",
        "dash",
        "dive",
        "jump",
        "movement",
        "move",
        "stamina",
        "mechanic",
        "network",
        "match",
        "position"
    }

    for _, needle in ipairs(needles) do
        if string.find(lower, needle, 1, true) then
            return true
        end
    end

    return false
end

local function scanRemoteCandidates()
    candidateRemotes = {}

    local scanned = 0
    local scanLimit = 2500

    logSection("REMOTE CANDIDATES")

    for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
        scanned += 1
        if scanned > scanLimit then
            log("Remote scan stopped at limit: " .. tostring(scanLimit) .. " descendants")
            break
        end

        if isCandidateRemote(descendant) then
            table.insert(candidateRemotes, "[" .. descendant.ClassName .. "] " .. getPath(descendant))
        end
    end

    table.sort(candidateRemotes)

    if #candidateRemotes == 0 then
        log("No obvious slide/dash/movement remotes found by name/path.")
    else
        for index, path in ipairs(candidateRemotes) do
            log(tostring(index) .. ". " .. path)
        end
    end
end

----------------------------------------------------------------
-- Animation logging
----------------------------------------------------------------
local function disconnectAnimationWatcher()
    if animationConn then
        animationConn:Disconnect()
        animationConn = nil
    end
end

local function setupAnimationWatcher()
    disconnectAnimationWatcher()

    local _, _, humanoid = getCharacterParts()
    if not humanoid then
        return
    end

    animationConn = humanoid.AnimationPlayed:Connect(function(track)
        if scriptUnloaded then
            return
        end

        local animation = track.Animation
        local animationId = animation and animation.AnimationId or "(none)"
        local name = track.Name or (animation and animation.Name) or "(unnamed)"

        animationCounts[name] = (animationCounts[name] or 0) + 1

        safeSetLabel(lastAnimationLabel, "Last anim: " .. compactText(name, 28))

        if captureActive or (Toggles and Toggles.LogAnimations and Toggles.LogAnimations.Value) then
            log("[ANIM] " .. name
                .. " id=" .. tostring(animationId)
                .. " priority=" .. tostring(track.Priority)
                .. " speed=" .. shortNumber(track.Speed)
                .. " length=" .. shortNumber(track.Length))
        end
    end)
end

----------------------------------------------------------------
-- Remote hook
----------------------------------------------------------------
local function shouldLogRemote()
    if captureActive then
        return true
    end

    return Toggles and Toggles.RecordAllRemotes and Toggles.RecordAllRemotes.Value == true
end

env.Locked2SlideAnalyzerShouldLogRemotes = function()
    return not scriptUnloaded and shouldLogRemote()
end

local function recordRemoteCall(remote, method, argsText, callingScript)
    if scriptUnloaded or not shouldLogRemote() then
        return
    end

    remoteLogCount += 1
    if remoteLogCount > remoteLogLimit then
        if remoteLogCount == remoteLogLimit + 1 then
            log("[REMOTE] log limit reached; suppressing more remote lines for this capture")
        end
        return
    end

    local remotePath = getPath(remote)
    local key = method .. " " .. remotePath

    remoteCounts[key] = (remoteCounts[key] or 0) + 1

    local callerText = ""
    if callingScript then
        callerText = " caller=" .. getPath(callingScript)
    end

    local line = "[REMOTE] " .. method .. " " .. remotePath .. "(" .. argsText .. ")" .. callerText

    log(line)
    safeSetLabel(lastRemoteLabel, "Last remote: " .. compactText(remote.Name, 32))
end

local function setupRemoteHook()
    env[remoteSignalName] = function(remote, method, argsText, callingScript)
        recordRemoteCall(remote, method, argsText, callingScript)
    end

    if env.Locked2SlideAnalyzerRemoteHookInstalled then
        return true
    end

    if typeof(getnamecallmethod) ~= "function" then
        return false
    end

    local function onNamecall(self, ...)
        if typeof(self) ~= "Instance" then
            return
        end

        if not (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
            return
        end

        local method = getnamecallmethod()
        if method ~= "FireServer" and method ~= "InvokeServer" then
            return
        end

        local shouldLog = env.Locked2SlideAnalyzerShouldLogRemotes
        if type(shouldLog) == "function" then
            local ok, result = pcall(shouldLog)
            if not ok or not result then
                return
            end
        else
            return
        end

        local callingScript = nil
        if type(getcallingscript) == "function" then
            pcall(function()
                callingScript = getcallingscript()
            end)
        end

        local argsText = summarizeArgs(...)
        local signal = env[remoteSignalName]

        if type(signal) == "function" then
            pcall(signal, self, method, argsText, callingScript)
        end
    end

    local wrap = typeof(newcclosure) == "function" and newcclosure or function(fn)
        return fn
    end

    if typeof(hookmetamethod) == "function" then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", wrap(function(self, ...)
            onNamecall(self, ...)
            return oldNamecall(self, ...)
        end))

        env.Locked2SlideAnalyzerRemoteHookInstalled = true
        return true
    end

    if typeof(getrawmetatable) ~= "function" then
        return false
    end

    local ok = pcall(function()
        local mt = getrawmetatable(game)
        local oldNamecall = mt.__namecall

        if typeof(setreadonly) == "function" then
            setreadonly(mt, false)
        end

        mt.__namecall = wrap(function(self, ...)
            onNamecall(self, ...)
            return oldNamecall(self, ...)
        end)

        if typeof(setreadonly) == "function" then
            setreadonly(mt, true)
        end
    end)

    if ok then
        env.Locked2SlideAnalyzerRemoteHookInstalled = true
    end

    return ok
end

----------------------------------------------------------------
-- Capture and metrics
----------------------------------------------------------------
local function resetMetrics()
    maxSpeed = 0
    maxYVelocity = 0
    totalDistance = 0
    startPosition = nil
    lastPosition = nil
    lowSpeedAfterBurstTime = 0
    possibleLockDetected = false
    lastSampleAt = 0
end

local function beginCapture(reason)
    if captureActive then
        log("[CAPTURE] Restarting active capture")
    end

    captureId += 1
    captureActive = true
    captureStartedAt = now()
    captureReason = reason or "manual"

    remoteCounts = {}
    animationCounts = {}
    remoteLogCount = 0
    resetMetrics()

    logSection("CAPTURE #" .. tostring(captureId) .. " START: " .. tostring(captureReason))
    logSnapshot("before slide")
    notify("Capture started: " .. tostring(captureReason), 2)
end

local function orderedCounts(counts)
    local rows = {}

    for key, count in pairs(counts) do
        table.insert(rows, {
            key = key,
            count = count
        })
    end

    table.sort(rows, function(a, b)
        if a.count == b.count then
            return a.key < b.key
        end

        return a.count > b.count
    end)

    return rows
end

local function finishCapture(reason)
    if not captureActive then
        return
    end

    local duration = now() - captureStartedAt

    logSnapshot("after slide")
    logSection("CAPTURE #" .. tostring(captureId) .. " SUMMARY: " .. tostring(reason or "finished"))
    log("Duration=" .. shortNumber(duration)
        .. " totalDistance=" .. shortNumber(totalDistance)
        .. " maxHorizontalSpeed=" .. shortNumber(maxSpeed)
        .. " maxYVelocity=" .. shortNumber(maxYVelocity)
        .. " possibleArrivalLock=" .. tostring(possibleLockDetected))

    log("Remote calls:")
    local remoteRows = orderedCounts(remoteCounts)
    if #remoteRows == 0 then
        log("  (none captured)")
    else
        for index, row in ipairs(remoteRows) do
            if index > 30 then
                log("  ...")
                break
            end
            log("  " .. tostring(row.count) .. "x " .. row.key)
        end
    end

    log("Animations:")
    local animationRows = orderedCounts(animationCounts)
    if #animationRows == 0 then
        log("  (none captured)")
    else
        for index, row in ipairs(animationRows) do
            if index > 20 then
                log("  ...")
                break
            end
            log("  " .. tostring(row.count) .. "x " .. row.key)
        end
    end

    captureActive = false
    flushLog(true)
    notify("Capture finished. Max speed: " .. shortNumber(maxSpeed), 3)
end

local function sampleSlide(dt)
    if not captureActive then
        return
    end

    if now() - captureStartedAt >= captureDuration then
        finishCapture("duration elapsed")
        return
    end

    lastSampleAt += dt
    if lastSampleAt < sampleInterval then
        return
    end
    lastSampleAt = 0

    local character, root, humanoid = getCharacterParts()
    if not character or not root or not humanoid then
        return
    end

    local position = root.Position
    local velocity = root.AssemblyLinearVelocity or root.Velocity
    local horizontalSpeed = horizontal(velocity).Magnitude
    local slidingAttribute = character:GetAttribute("Sliding")
    local characterAttributes = collectAttributes(character)

    if not startPosition then
        startPosition = position
    end

    if lastPosition then
        totalDistance += horizontal(position - lastPosition).Magnitude
    end

    lastPosition = position
    maxSpeed = math.max(maxSpeed, horizontalSpeed)
    maxYVelocity = math.max(maxYVelocity, math.abs(velocity.Y))

    if maxSpeed > 18 and horizontalSpeed < 1.5 then
        lowSpeedAfterBurstTime += sampleInterval
        if lowSpeedAfterBurstTime >= 0.55 then
            possibleLockDetected = true
        end
    else
        lowSpeedAfterBurstTime = 0
    end

    local elapsed = now() - captureStartedAt

    log("[SAMPLE] t=" .. shortNumber(elapsed)
        .. " state=" .. tostring(humanoid:GetState())
        .. " ws=" .. shortNumber(humanoid.WalkSpeed)
        .. " speed=" .. shortNumber(horizontalSpeed)
        .. " vel=" .. shortVector3(velocity)
        .. " pos=" .. shortVector3(position)
        .. " moveDir=" .. shortVector3(humanoid.MoveDirection)
        .. " sliding=" .. tostring(slidingAttribute)
        .. " attrs={" .. characterAttributes .. "}"
        .. " platformStand=" .. tostring(humanoid.PlatformStand)
        .. " autoRotate=" .. tostring(humanoid.AutoRotate))
end

----------------------------------------------------------------
-- UI refresh
----------------------------------------------------------------
local function refreshLabels()
    local status = captureActive
        and ("capturing #" .. tostring(captureId) .. " (" .. shortNumber(now() - captureStartedAt) .. "s)")
        or "idle"

    safeSetLabel(captureStatusLabel, "Capture: " .. status)
    safeSetLabel(metricsLabel, "Max speed: " .. shortNumber(maxSpeed)
        .. " | Dist: " .. shortNumber(totalDistance)
        .. " | Lock: " .. tostring(possibleLockDetected))
    safeSetLabel(fileStatusLabel, "Disk log: " .. ((canAppendFile or canWriteFile) and logFileName or "unavailable"))
    safeSetLabel(scriptCandidatesLabel, "Candidates: " .. tostring(#candidateScripts))
    safeSetLabel(remoteCandidatesLabel, "Remote candidates: " .. tostring(#candidateRemotes))
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
local Window = Library:CreateWindow({
    Title = "Locked 2 | Slide Analyzer",
    Center = true,
    AutoShow = true,
    Size = UDim2.fromOffset(620, 455),
    TabPadding = 8,
    MenuFadeTime = 0.2
})

local Tabs = {
    Main = Window:AddTab("Main"),
    Logs = Window:AddTab("Logs"),
    Settings = Window:AddTab("Settings"),
    ["UI Settings"] = Window:AddTab("UI Settings")
}

local CaptureBox = Tabs.Main:AddLeftGroupbox("Capture")
local StatusBox = Tabs.Main:AddRightGroupbox("Status")
local ScanBox = Tabs.Main:AddLeftGroupbox("Scan")
local LogBox = Tabs.Logs:AddLeftGroupbox("Log")
local KeyBox = Tabs.Settings:AddLeftGroupbox("Keybinds")

CaptureBox:AddToggle("AutoCaptureQ", {
    Text = "Auto-capture Q",
    Default = true,
    Tooltip = "Starts a capture automatically when the slide key is pressed."
})

CaptureBox:AddLabel("Remote hook removed")

CaptureBox:AddToggle("LogAnimations", {
    Text = "Log animations",
    Default = true,
    Tooltip = "Logs Humanoid animation tracks during captures."
})

CaptureBox:AddSlider("CaptureDuration", {
    Text = "Capture seconds",
    Default = captureDuration,
    Min = 2,
    Max = 12,
    Rounding = 1,
    HideMax = true,
    Compact = false,
    Tooltip = "How long an automatic capture should run after Q."
})

CaptureBox:AddButton({
    Text = "Start Capture",
    Func = function()
        beginCapture("manual")
    end
})

CaptureBox:AddButton({
    Text = "Stop Capture",
    Func = function()
        finishCapture("manual stop")
    end
})

ScanBox:AddButton({
    Text = "Scan Script Candidates",
    Func = function()
        scanScriptCandidates()
        refreshLabels()
        notify("Script candidate scan finished.", 3)
    end
})

ScanBox:AddButton({
    Text = "Scan Remote Candidates",
    Func = function()
        scanRemoteCandidates()
        refreshLabels()
        notify("Remote candidate scan finished.", 3)
    end
})

ScanBox:AddButton({
    Text = "Snapshot Now",
    Func = function()
        logSnapshot("manual")
        notify("Snapshot logged.", 2)
    end
})

StatusBox:AddButton({
    Text = "Show Summary",
    Func = function()
        notify(
            "Max: " .. shortNumber(maxSpeed)
                .. " | Dist: " .. shortNumber(totalDistance)
                .. " | Remotes: " .. tostring(#orderedCounts(remoteCounts))
                .. " | Anims: " .. tostring(#orderedCounts(animationCounts)),
            5
        )
    end
})

captureStatusLabel = StatusBox:AddLabel("Capture: idle")
metricsLabel = StatusBox:AddLabel("Max speed: 0.00 | Dist: 0.00")
lastRemoteLabel = StatusBox:AddLabel("Remote hook: disabled")
lastAnimationLabel = StatusBox:AddLabel("Last anim: none")
fileStatusLabel = StatusBox:AddLabel("Disk log: checking")
scriptCandidatesLabel = StatusBox:AddLabel("Candidates: 0")
remoteCandidatesLabel = StatusBox:AddLabel("Remote candidates: 0")

LogBox:AddButton({
    Text = "Clear Log",
    Func = function()
        clearLog()
        notify("Log cleared.", 2)
    end
})

LogBox:AddButton({
    Text = "Print Last Lines",
    Func = function()
        logSection("LAST LINES REQUESTED")
        for _, line in ipairs(recentLines) do
            print(line)
        end
        notify("Printed recent lines to console.", 2)
    end
})

LogBox:AddButton({
    Text = "Unload",
    Func = function()
        Library:Unload()
    end
})

KeyBox:AddLabel("Slide key"):AddKeyPicker("SlideCaptureKey", {
    Default = "Q",
    SyncToggleState = false,
    Mode = "Hold",
    Text = "Slide capture key",
    NoUI = false
})

local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")

MenuGroup:AddButton({
    Text = "Unload",
    Func = function()
        Library:Unload()
    end
})

MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
    Default = "RightControl",
    NoUI = true,
    Text = "Menu keybind"
})

Library.ToggleKeybind = Options.MenuKeybind

----------------------------------------------------------------
-- UI callbacks
----------------------------------------------------------------
Options.CaptureDuration:OnChanged(function()
    captureDuration = tonumber(Options.CaptureDuration.Value) or 6
    env.Locked2SlideCaptureDuration = captureDuration
end)

----------------------------------------------------------------
-- Save & Theme managers
----------------------------------------------------------------
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({
    "MenuKeybind"
})

ThemeManager:SetFolder("Locked2")
SaveManager:SetFolder("Locked2/SlideAnalyzer")

SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])

SaveManager:LoadAutoloadConfig()

----------------------------------------------------------------
-- Runtime
----------------------------------------------------------------
logSection("NEW SLIDE ANALYZER SESSION")
log("Player=" .. player.Name .. " UserId=" .. tostring(player.UserId))
log("PlaceId=" .. tostring(game.PlaceId) .. " JobId=" .. tostring(game.JobId))
log("writefile=" .. tostring(canWriteFile) .. " appendfile=" .. tostring(canAppendFile))
log("Remote hook is disabled because it crashes this client. Use remote candidate scan instead.")

setupAnimationWatcher()
log("Auto script scan is disabled in safe mode. Use the Scan button if needed.")

heartbeatConn = RunService.Heartbeat:Connect(function(dt)
    if scriptUnloaded then
        return
    end

    sampleSlide(dt)
end)

inputBeganConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if scriptUnloaded or gameProcessed then
        return
    end

    captureKey = getKeyFromOption("SlideCaptureKey", Enum.KeyCode.Q)

    if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == captureKey then
        log("[INPUT] Slide key pressed: " .. captureKey.Name)

        if Toggles and Toggles.AutoCaptureQ and Toggles.AutoCaptureQ.Value then
            beginCapture("slide key " .. captureKey.Name)
        end
    end
end)

charAddedConn = player.CharacterAdded:Connect(function()
    task.wait(0.5)
    setupAnimationWatcher()
    logSnapshot("character added")
end)

statusThread = task.spawn(function()
    while not scriptUnloaded and not Library.Unloaded do
        task.wait(0.25)
        refreshLabels()
    end
end)

----------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------
local function cleanup()
    if scriptUnloaded then
        return
    end

    scriptUnloaded = true
    captureActive = false

    if heartbeatConn then
        heartbeatConn:Disconnect()
        heartbeatConn = nil
    end

    if inputBeganConn then
        inputBeganConn:Disconnect()
        inputBeganConn = nil
    end

    if charAddedConn then
        charAddedConn:Disconnect()
        charAddedConn = nil
    end

    disconnectAnimationWatcher()

    if env[remoteSignalName] then
        env[remoteSignalName] = nil
    end

    if env.Locked2SlideAnalyzerShouldLogRemotes then
        env.Locked2SlideAnalyzerShouldLogRemotes = nil
    end

    log("Analyzer unloaded")
    flushLog(true)
end

env.Locked2SlideAnalyzerCleanup = function()
    cleanup()

    pcall(function()
        Library:Unload()
    end)
end

Library:OnUnload(function()
    cleanup()
    Library.Unloaded = true
end)

refreshLabels()
notify("Loaded. Press Q to capture slide behavior.", 5)
