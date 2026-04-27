--[[
    Locked 2 - Shift Sprint with Flow Awareness
    UI: Linoria Lib

    Rules:
      - No hardcoded Flow speed thresholds.
      - Normal walking without sprint key is not modified.
      - Sprint modifier is percentage-based.
      - Flow can change walk speed, sprint speed, both, or neither.

    Flow detection:
      1. Mechanics.Flow:InvokeServer() hook for self-activation.
      2. KonoGodlyFlame1 ParticleEmitter on character as structural VFX fallback.

    Measurements:
      - measuredWalkSpeed: normal walk outside Flow
      - measuredRunSpeed: normal sprint outside Flow
      - measuredFlowWalkSpeed: walk inside Flow
      - measuredFlowRunSpeed: sprint inside Flow

    Target sprint:
      activeWalk + (activeRun - activeWalk) * sprintPercent / 100

    Slide protection:
      - Q prelock protects the first dash frames before Sliding=true appears.
      - Character Sliding attribute is the primary detector.
      - Short recovery lock prevents dash deceleration from polluting speed samples.
--]]

----------------------------------------------------------------
-- Cleanup previous run
----------------------------------------------------------------
if type(getgenv().Locked2ShiftSprintCleanup) == "function" then
    pcall(getgenv().Locked2ShiftSprintCleanup)
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

local player = Players.LocalPlayer

----------------------------------------------------------------
-- State
----------------------------------------------------------------
local env = getgenv()

local sprintPercent = tonumber(env.Locked2SprintPercent) or tonumber(env.SprintPercent) or 100

local storedWalkSpeed = tonumber(env.Locked2MeasuredWalkSpeed) or tonumber(env.MeasuredWalkSpeed)
local storedRunSpeed = tonumber(env.Locked2MeasuredRunSpeed) or tonumber(env.MeasuredRunSpeed)
local storedFlowWalkSpeed = tonumber(env.Locked2MeasuredFlowWalkSpeed)
local storedFlowRunSpeed = tonumber(env.Locked2MeasuredFlowRunSpeed) or tonumber(env.MeasuredFlowRunSpeed)

local measuredWalkSpeed = storedWalkSpeed or 16
local measuredRunSpeed = storedRunSpeed or 24
local measuredFlowWalkSpeed = storedFlowWalkSpeed
local measuredFlowRunSpeed = storedFlowRunSpeed

local flowAwarenessEnabled = env.Locked2FlowAwareness
if flowAwarenessEnabled == nil then
    flowAwarenessEnabled = env.FlowAwareness
end
if flowAwarenessEnabled == nil then
    flowAwarenessEnabled = true
end

local enabled = false
local sprinting = false
local inFlow = false
local flowSource = "none"
local flowHookReady = false
local scriptUnloaded = false

local slideActive = false
local slideSource = "none"
local slideLockUntil = 0
local slideInputWatchUntil = 0
local slideNextAttributeCheck = 0
local slideLastSeenAt = 0
local slidePeakSpeed = 0

local measurementGuardStatus = "ready"
local measurementRejectedCount = tonumber(env.Locked2MeasurementRejectedCount) or 0

----------------------------------------------------------------
-- Sampling config
----------------------------------------------------------------
local lastRootPos = nil
local sampleDistance = 0
local sampleDuration = 0
local samplePauseUntil = 0

local sampleInterval = 0.18
local maxSamples = 20
local minStableSamples = 5
local minSampleSpeed = 2
local maxReasonableSpeed = 350
local measurementStep = 0.1
local stableUpdateThreshold = 0.15
local sampleSource = "none"

local measurementMaxRelativeShift = 0.16
local measurementMinAbsoluteShift = 2.5
local measurementMinSprintRatio = 1.45

local slideInputPrelock = 0.35
local slideInputWatchDuration = 0.75
local slideRecoveryGrace = 0.95
local slideVelocityGrace = 1.15
local slideAttributeCheckInterval = 0.12

local samples = {
    Walk = {},
    Run = {},
    FlowWalk = {},
    FlowRun = {}
}

local initialRunAnchor = tonumber(env.Locked2RunSpeedAnchor)
if not initialRunAnchor and storedRunSpeed and storedRunSpeed >= measuredWalkSpeed * 1.6 then
    initialRunAnchor = storedRunSpeed
end

local initialFlowRunAnchor = tonumber(env.Locked2FlowRunSpeedAnchor)
if not initialFlowRunAnchor and storedFlowRunSpeed and storedFlowRunSpeed >= measuredWalkSpeed * 1.6 then
    initialFlowRunAnchor = storedFlowRunSpeed
end

local measurementAnchors = {
    Walk = tonumber(env.Locked2WalkSpeedAnchor) or storedWalkSpeed,
    Run = initialRunAnchor,
    FlowWalk = tonumber(env.Locked2FlowWalkSpeedAnchor) or storedFlowWalkSpeed,
    FlowRun = initialFlowRunAnchor
}

----------------------------------------------------------------
-- Connections
----------------------------------------------------------------
local heartbeatConn
local inputBeganConn
local charAddedConn
local slideAttributeConn
local statusThread
local flowDetectorThread
local flowDetectorToken = 0
local flowNegativeFrames = 0
local flowRemoteGraceUntil = 0

----------------------------------------------------------------
-- UI refs
----------------------------------------------------------------
local stateLabel
local normalWalkLabel
local normalRunLabel
local flowWalkLabel
local flowRunLabel
local targetLabel
local slideLabel
local guardLabel
local flowLabel
local hookLabel

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function notify(text, duration)
    pcall(function()
        Library:Notify("[Locked 2] " .. tostring(text), duration or 3)
    end)
end

local function fmt(value)
    if value == nil then
        return "not measured"
    end

    return string.format("%.1f", value)
end

local function persistMeasurements()
    env.Locked2SprintPercent = sprintPercent
    env.SprintPercent = sprintPercent

    env.Locked2MeasuredWalkSpeed = measuredWalkSpeed
    env.Locked2MeasuredRunSpeed = measuredRunSpeed
    env.Locked2MeasuredFlowWalkSpeed = measuredFlowWalkSpeed
    env.Locked2MeasuredFlowRunSpeed = measuredFlowRunSpeed

    env.MeasuredWalkSpeed = measuredWalkSpeed
    env.MeasuredRunSpeed = measuredRunSpeed
    env.MeasuredFlowRunSpeed = measuredFlowRunSpeed

    env.Locked2WalkSpeedAnchor = measurementAnchors.Walk
    env.Locked2RunSpeedAnchor = measurementAnchors.Run
    env.Locked2FlowWalkSpeedAnchor = measurementAnchors.FlowWalk
    env.Locked2FlowRunSpeedAnchor = measurementAnchors.FlowRun
    env.Locked2MeasurementRejectedCount = measurementRejectedCount

    env.Locked2FlowAwareness = flowAwarenessEnabled
    env.FlowAwareness = flowAwarenessEnabled
end

local function safeSetLabel(label, text)
    if not label then
        return
    end

    pcall(function()
        label:SetText(text)
    end)
end

local function getCharacterParts()
    local character = player.Character
    if not character then
        return nil, nil
    end

    return character:FindFirstChild("HumanoidRootPart"), character:FindFirstChildOfClass("Humanoid")
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

local function isMoving(humanoid)
    if isMoveKeyDown() then
        return true
    end

    if humanoid and humanoid.MoveDirection.Magnitude > 0.05 then
        return true
    end

    return false
end

local function isGrounded(humanoid)
    if not humanoid then
        return true
    end

    return humanoid.FloorMaterial ~= Enum.Material.Air
end

local function isSprintHeld()
    if Options and Options.SprintKeybind and Options.SprintKeybind.GetState then
        local ok, state = pcall(function()
            return Options.SprintKeybind:GetState()
        end)

        if ok then
            return state == true
        end
    end

    return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
end

local function resetMotionTracking()
    lastRootPos = nil
    sampleDistance = 0
    sampleDuration = 0
    samplePauseUntil = os.clock() + 0.22
end

local function isSlideAttributeActive()
    local character = player.Character
    if not character then
        return false
    end

    local ok, value = pcall(function()
        return character:GetAttribute("Sliding")
    end)

    return ok and value == true
end

local function extendSlideLock(duration, source)
    local now = os.clock()
    slideLockUntil = math.max(slideLockUntil, now + duration)

    if source then
        slideSource = source
    end
end

local function beginSlideInputWatch()
    if scriptUnloaded then
        return
    end

    local now = os.clock()
    slideInputWatchUntil = math.max(slideInputWatchUntil, now + slideInputWatchDuration)
    slideNextAttributeCheck = now
    extendSlideLock(slideInputPrelock, "input")
    sampleSource = "slide-lock"
    resetMotionTracking()
end

local function setSlideActiveState(active, source)
    if scriptUnloaded then
        return
    end

    local now = os.clock()

    if active then
        if not slideActive then
            slidePeakSpeed = 0
            resetMotionTracking()
        end

        slideActive = true
        slideSource = source or "attribute"
        slideLastSeenAt = now
        slideLockUntil = math.max(slideLockUntil, now + slideRecoveryGrace)
        return
    end

    if slideActive then
        slideActive = false
        slideSource = "recovery"
        slideLockUntil = math.max(slideLockUntil, now + slideRecoveryGrace)
        resetMotionTracking()
    end
end

local function isSlideLocked()
    return slideActive or os.clock() < slideLockUntil
end

local function getSlideStatusText()
    local now = os.clock()

    if slideActive then
        return "active " .. tostring(slideSource)
    end

    if now < slideLockUntil then
        return string.format("recovery %.1fs", slideLockUntil - now)
    end

    if now < slideInputWatchUntil then
        return "watching"
    end

    return "none"
end

local function connectSlideAttribute(character)
    if slideAttributeConn then
        slideAttributeConn:Disconnect()
        slideAttributeConn = nil
    end

    slideActive = false
    slideSource = "none"
    slideLockUntil = 0
    slideInputWatchUntil = 0
    slideNextAttributeCheck = 0
    slideLastSeenAt = 0
    slidePeakSpeed = 0

    if not character then
        return
    end

    local function updateFromAttribute()
        setSlideActiveState(character:GetAttribute("Sliding") == true, "attribute")
    end

    slideAttributeConn = character:GetAttributeChangedSignal("Sliding"):Connect(updateFromAttribute)
    updateFromAttribute()
end

local function clearArray(array)
    for index = #array, 1, -1 do
        array[index] = nil
    end
end

local function clearAllSamples()
    clearArray(samples.Walk)
    clearArray(samples.Run)
    clearArray(samples.FlowWalk)
    clearArray(samples.FlowRun)
end

local function getMeasurementAnchor(key)
    return measurementAnchors[key]
end

local function setMeasurementAnchor(key, value)
    if type(value) ~= "number" or value ~= value or value <= 0 then
        return
    end

    measurementAnchors[key] = value
    measurementGuardStatus = key .. " locked " .. fmt(value)
end

local function getAnchorAllowedShift(anchor)
    return math.max(measurementMinAbsoluteShift, anchor * measurementMaxRelativeShift)
end

local function isWithinMeasurementAnchor(key, candidate)
    local anchor = getMeasurementAnchor(key)
    if not anchor then
        return true
    end

    local allowedShift = getAnchorAllowedShift(anchor)
    return math.abs(candidate - anchor) <= allowedShift
end

local function getWalkReferenceForMeasurement(key)
    if key == "FlowRun" then
        return measuredFlowWalkSpeed or measuredWalkSpeed
    end

    return measuredWalkSpeed
end

local function isBootstrapSprintCandidateSafe(key, candidate)
    if key ~= "Run" and key ~= "FlowRun" then
        return true
    end

    if getMeasurementAnchor(key) then
        return true
    end

    local walkReference = getWalkReferenceForMeasurement(key)
    if type(walkReference) ~= "number" or walkReference ~= walkReference or walkReference <= 0 then
        return true
    end

    local minimumSprint = math.max(
        walkReference + measurementMinAbsoluteShift,
        walkReference * measurementMinSprintRatio
    )

    return candidate >= minimumSprint
end

local function rejectMeasurementCandidate(key, candidate, array)
    local anchor = getMeasurementAnchor(key)
    measurementRejectedCount = measurementRejectedCount + 1

    if anchor then
        measurementGuardStatus = string.format(
            "%s rejected %.1f / %.1f",
            key,
            candidate,
            anchor
        )
    else
        measurementGuardStatus = key .. " rejected " .. fmt(candidate)
    end

    clearArray(array)
end

local function roundTo(value, step)
    return math.floor((value / step) + 0.5) * step
end

local function pushSample(array, value)
    if type(value) ~= "number" then
        return
    end

    if value ~= value then
        return
    end

    if value < minSampleSpeed or value > maxReasonableSpeed then
        return
    end

    table.insert(array, value)

    while #array > maxSamples do
        table.remove(array, 1)
    end
end

local function trimmedMean(array)
    local count = #array
    if count == 0 then
        return nil
    end

    local sorted = {}
    for index = 1, count do
        sorted[index] = array[index]
    end

    table.sort(sorted)

    local trim = math.floor(count * 0.2)
    local first = trim + 1
    local last = count - trim

    local sum = 0
    local used = 0

    for index = first, last do
        sum = sum + sorted[index]
        used = used + 1
    end

    if used <= 0 then
        return sorted[math.ceil(count / 2)]
    end

    return sum / used
end

local function applyStableMeasurement(key, current, array)
    if #array < minStableSamples then
        return current
    end

    local candidate = trimmedMean(array)
    if not candidate then
        return current
    end

    candidate = roundTo(candidate, measurementStep)

    if not isWithinMeasurementAnchor(key, candidate) then
        rejectMeasurementCandidate(key, candidate, array)
        return current
    end

    if not isBootstrapSprintCandidateSafe(key, candidate) then
        rejectMeasurementCandidate(key, candidate, array)
        return current
    end

    if not getMeasurementAnchor(key) then
        setMeasurementAnchor(key, candidate)
    end

    if current == nil then
        return candidate
    end

    if math.abs(candidate - current) >= stableUpdateThreshold then
        return candidate
    end

    return current
end

local function calculateTargetRunSpeed(walk, run)
    run = math.max(run, walk)
    local runBonus = math.max(run - walk, 0)

    return walk + runBonus * (sprintPercent / 100)
end

local function getNormalTargetRunSpeed()
    return calculateTargetRunSpeed(measuredWalkSpeed, measuredRunSpeed)
end

local function getFlowTargetRunSpeed()
    local walk = measuredFlowWalkSpeed or measuredWalkSpeed
    local run = measuredFlowRunSpeed or measuredRunSpeed

    return calculateTargetRunSpeed(walk, run)
end

local function getTargetRunSpeed()
    if flowAwarenessEnabled and inFlow then
        return getFlowTargetRunSpeed()
    end

    return getNormalTargetRunSpeed()
end

local function getSlideImpulseBaseline()
    local baseline = math.max(
        tonumber(measuredWalkSpeed) or 0,
        tonumber(measuredRunSpeed) or 0,
        tonumber(measuredFlowWalkSpeed) or 0,
        tonumber(measuredFlowRunSpeed) or 0,
        16
    )

    return baseline
end

local function isLikelySlideImpulse(nativeSpeed)
    if os.clock() > slideInputWatchUntil then
        return false
    end

    if type(nativeSpeed) ~= "number" or nativeSpeed ~= nativeSpeed then
        return false
    end

    if nativeSpeed <= 0 or nativeSpeed > maxReasonableSpeed then
        return false
    end

    local baseline = getSlideImpulseBaseline()
    local threshold = math.max(baseline * 1.45, baseline + 12)

    return nativeSpeed >= threshold
end

local function updateSlideState(nativeSpeed)
    local now = os.clock()

    if now >= slideNextAttributeCheck then
        slideNextAttributeCheck = now + slideAttributeCheckInterval

        if isSlideAttributeActive() then
            setSlideActiveState(true, "attribute")
        elseif slideActive then
            setSlideActiveState(false, "attribute")
        end
    end

    if isLikelySlideImpulse(nativeSpeed) then
        extendSlideLock(slideVelocityGrace, "velocity")
        slideLastSeenAt = now
        slidePeakSpeed = math.max(slidePeakSpeed, nativeSpeed)
        sampleSource = "slide-lock"
    elseif isSlideLocked() and type(nativeSpeed) == "number" and nativeSpeed == nativeSpeed then
        slidePeakSpeed = math.max(slidePeakSpeed, math.max(nativeSpeed, 0))
    end

    if not isSlideLocked() and now >= slideInputWatchUntil then
        slideSource = "none"
    end

    return isSlideLocked()
end

local function getDisplayState()
    local _, humanoid = getCharacterParts()
    local moving = isMoving(humanoid)
    local state = "Idle"

    if slideActive then
        state = "Sliding"
    elseif isSlideLocked() then
        state = "Slide Recovery"
    elseif enabled and sprinting and moving then
        state = "Modifying Sprint"
    elseif sprinting and moving then
        state = "Sprinting"
    elseif moving then
        state = "Walking"
    elseif enabled and sprinting then
        state = "Enabled + Sprint Held"
    elseif enabled then
        state = "Enabled"
    elseif sprinting then
        state = "Sprint Held"
    end

    if flowAwarenessEnabled and inFlow then
        state = state .. " | Flow"
    end

    return state
end

local function refreshLabels()
    safeSetLabel(stateLabel, "State: " .. getDisplayState())
    safeSetLabel(normalWalkLabel, "Normal walk: " .. fmt(measuredWalkSpeed))
    safeSetLabel(normalRunLabel, "Normal sprint: " .. fmt(measuredRunSpeed))
    safeSetLabel(flowWalkLabel, "Flow walk: " .. fmt(measuredFlowWalkSpeed))
    safeSetLabel(flowRunLabel, "Flow sprint: " .. fmt(measuredFlowRunSpeed))
    safeSetLabel(slideLabel, "Slide: " .. getSlideStatusText())
    safeSetLabel(guardLabel, "Guard: " .. measurementGuardStatus)
    if flowAwarenessEnabled and inFlow then
        safeSetLabel(targetLabel, "Target: flow " .. fmt(getFlowTargetRunSpeed()))
    else
        safeSetLabel(targetLabel, "Target: normal " .. fmt(getNormalTargetRunSpeed()))
    end

    if not flowAwarenessEnabled then
        safeSetLabel(flowLabel, "Flow: disabled")
    elseif inFlow then
        safeSetLabel(flowLabel, "Flow: active via " .. tostring(flowSource))
    else
        safeSetLabel(flowLabel, "Flow: not detected")
    end

    safeSetLabel(hookLabel, "Remote hook: " .. (flowHookReady and "ready" or "not available"))
end

----------------------------------------------------------------
-- Flow detection
----------------------------------------------------------------
local function getFlowRemote()
    local root = ReplicatedStorage:FindFirstChild("REPLICATEDSTORAGE")
    local mechanics = root and root:FindFirstChild("Mechanics")
    return mechanics and mechanics:FindFirstChild("Flow") or nil
end

local function setFlowActive(source)
    if scriptUnloaded or not flowAwarenessEnabled then
        return
    end

    local wasInFlow = inFlow

    inFlow = true
    flowSource = source or flowSource or "unknown"
    flowNegativeFrames = 0

    if source == "remote" then
        flowRemoteGraceUntil = os.clock() + 4
    end

    if not wasInFlow then
        resetMotionTracking()
    end
end

local function setFlowInactive()
    if not inFlow then
        return
    end

    inFlow = false
    flowSource = "none"
    flowNegativeFrames = 0
    flowRemoteGraceUntil = 0

    resetMotionTracking()
end

local function detectFlowByParticle()
    local character = player.Character
    if not character then
        return false
    end

    local emitter = character:FindFirstChild("KonoGodlyFlame1", true)
    return emitter ~= nil and emitter:IsA("ParticleEmitter")
end

local function setupFlowRemoteHook()
    env.Locked2FlowSignal = function()
        setFlowActive("remote")
    end

    if env.Locked2FlowHookInstalled then
        return true
    end

    if typeof(getnamecallmethod) ~= "function" then
        return false
    end

    local flowRemote = getFlowRemote()
    if not flowRemote then
        return false
    end

    local function onNamecall(self)
        if self ~= flowRemote then
            return
        end

        local method = getnamecallmethod()
        if method ~= "InvokeServer" then
            return
        end

        local callback = env.Locked2FlowSignal
        if type(callback) == "function" then
            pcall(callback)
        end
    end

    local wrap = typeof(newcclosure) == "function" and newcclosure or function(fn)
        return fn
    end

    if typeof(hookmetamethod) == "function" then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", wrap(function(self, ...)
            onNamecall(self)
            return oldNamecall(self, ...)
        end))

        env.Locked2FlowHookInstalled = true
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
            onNamecall(self)
            return oldNamecall(self, ...)
        end)

        if typeof(setreadonly) == "function" then
            setreadonly(mt, true)
        end
    end)

    if ok then
        env.Locked2FlowHookInstalled = true
    end

    return ok
end

local function stopFlowDetector()
    flowDetectorToken = flowDetectorToken + 1
    flowDetectorThread = nil
end

local function startFlowDetector()
    if flowDetectorThread then
        return
    end

    flowDetectorToken = flowDetectorToken + 1
    local token = flowDetectorToken

    flowDetectorThread = task.spawn(function()
        while not scriptUnloaded and flowAwarenessEnabled and token == flowDetectorToken do
            task.wait(0.2)

            if scriptUnloaded or not flowAwarenessEnabled or token ~= flowDetectorToken then
                break
            end

            local particleSaysFlow = detectFlowByParticle()

            if particleSaysFlow then
                setFlowActive("particle")
            else
                flowNegativeFrames = flowNegativeFrames + 1

                if inFlow and flowNegativeFrames >= 3 and os.clock() > flowRemoteGraceUntil then
                    setFlowInactive()
                end
            end
        end

        if token == flowDetectorToken then
            flowDetectorThread = nil
        end
    end)
end

local function setFlowAwareness(value)
    flowAwarenessEnabled = value == true
    persistMeasurements()

    if flowAwarenessEnabled then
        flowHookReady = setupFlowRemoteHook()
        startFlowDetector()
    else
        stopFlowDetector()
        setFlowInactive()
    end

    refreshLabels()
end

----------------------------------------------------------------
-- Measurement
----------------------------------------------------------------
local function canSampleSprintSpeed()
    return not enabled or sprintPercent == 100
end

local function isValidSampleSpeed(value)
    return type(value) == "number"
        and value == value
        and value >= minSampleSpeed
        and value <= maxReasonableSpeed
end

local function getHumanoidWalkSpeed(humanoid)
    if not humanoid then
        return nil
    end

    local speed = tonumber(humanoid.WalkSpeed)
    if isValidSampleSpeed(speed) then
        return speed
    end

    return nil
end

local function getVelocitySpeed(root)
    if not root then
        return nil
    end

    local velocity = root.AssemblyLinearVelocity or root.Velocity
    if typeof(velocity) ~= "Vector3" then
        return nil
    end

    local speed = horizontal(velocity).Magnitude
    if isValidSampleSpeed(speed) then
        return speed
    end

    return nil
end

local function chooseMovementSample(positionSpeed, velocitySpeed, humanoidSpeed)
    local positionValid = isValidSampleSpeed(positionSpeed)
    local velocityValid = isValidSampleSpeed(velocitySpeed)
    local humanoidValid = isValidSampleSpeed(humanoidSpeed)

    -- When our CFrame modifier is active, position/velocity include our own
    -- correction. Humanoid.WalkSpeed remains the game's native baseline.
    if sprinting and enabled and sprintPercent ~= 100 and humanoidValid then
        sampleSource = "humanoid"
        return humanoidSpeed
    end

    local physicalSpeed = nil

    if positionValid and velocityValid then
        local delta = math.abs(positionSpeed - velocitySpeed)
        local tolerance = math.max(1.5, math.max(positionSpeed, velocitySpeed) * 0.18)

        if delta <= tolerance then
            physicalSpeed = (positionSpeed + velocitySpeed) * 0.5
            sampleSource = "pos+vel"
        else
            -- Prefer velocity when position delta catches a tiny frame spike.
            physicalSpeed = velocitySpeed
            sampleSource = "velocity"
        end
    elseif velocityValid then
        physicalSpeed = velocitySpeed
        sampleSource = "velocity"
    elseif positionValid then
        physicalSpeed = positionSpeed
        sampleSource = "position"
    end

    if humanoidValid then
        if not physicalSpeed then
            sampleSource = "humanoid"
            return humanoidSpeed
        end

        local delta = math.abs(physicalSpeed - humanoidSpeed)
        local tolerance = math.max(1.5, humanoidSpeed * 0.12)

        if delta <= tolerance then
            sampleSource = sampleSource .. "+humanoid"
            return (physicalSpeed + humanoidSpeed) * 0.5
        end
    end

    return physicalSpeed
end

local function updateSpeedSamples(positionSpeed, velocitySpeed, humanoid)
    if os.clock() < samplePauseUntil then
        return
    end

    if not isMoving(humanoid) then
        return
    end

    if not isGrounded(humanoid) then
        return
    end

    local humanoidSpeed = getHumanoidWalkSpeed(humanoid)
    local sampleSpeed = chooseMovementSample(positionSpeed, velocitySpeed, humanoidSpeed)

    if not isValidSampleSpeed(sampleSpeed) then
        return
    end

    if sprinting and not canSampleSprintSpeed() then
        if not humanoidSpeed then
            return
        end

        sampleSpeed = humanoidSpeed
        sampleSource = "humanoid"
    end

    if sprinting then
        if flowAwarenessEnabled and inFlow then
            pushSample(samples.FlowRun, sampleSpeed)
            measuredFlowRunSpeed = applyStableMeasurement("FlowRun", measuredFlowRunSpeed, samples.FlowRun)
        else
            pushSample(samples.Run, sampleSpeed)
            measuredRunSpeed = applyStableMeasurement("Run", measuredRunSpeed, samples.Run)
        end
    else
        if flowAwarenessEnabled and inFlow then
            pushSample(samples.FlowWalk, sampleSpeed)
            measuredFlowWalkSpeed = applyStableMeasurement("FlowWalk", measuredFlowWalkSpeed, samples.FlowWalk)
        else
            pushSample(samples.Walk, sampleSpeed)
            measuredWalkSpeed = applyStableMeasurement("Walk", measuredWalkSpeed, samples.Walk)
        end
    end

    persistMeasurements()
end

local function resetAllMeasurements()
    measuredWalkSpeed = 16
    measuredRunSpeed = 24
    measuredFlowWalkSpeed = nil
    measuredFlowRunSpeed = nil
    measurementAnchors.Walk = nil
    measurementAnchors.Run = nil
    measurementAnchors.FlowWalk = nil
    measurementAnchors.FlowRun = nil
    measurementGuardStatus = "reset"
    measurementRejectedCount = 0

    clearAllSamples()
    resetMotionTracking()
    persistMeasurements()
    refreshLabels()

    notify("Measurements reset. Walk, sprint, then use Flow to recalibrate.", 4)
end

local function resetFlowMeasurements()
    measuredFlowWalkSpeed = nil
    measuredFlowRunSpeed = nil
    measurementAnchors.FlowWalk = nil
    measurementAnchors.FlowRun = nil
    measurementGuardStatus = "flow reset"

    clearArray(samples.FlowWalk)
    clearArray(samples.FlowRun)
    resetMotionTracking()
    persistMeasurements()
    refreshLabels()

    notify("Flow measurements reset. Enter Flow and move to recalibrate.", 4)
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
local Window = Library:CreateWindow({
    Title = "Locked 2 | Shift Sprint",
    Center = true,
    AutoShow = true,
    Size = UDim2.fromOffset(600, 455),
    TabPadding = 8,
    MenuFadeTime = 0.2
})

local Tabs = {
    Main = Window:AddTab("Main"),
    Settings = Window:AddTab("Settings"),
    ["UI Settings"] = Window:AddTab("UI Settings")
}

local SprintBox = Tabs.Main:AddLeftGroupbox("Sprint")
local UtilityBox = Tabs.Main:AddLeftGroupbox("Utility")
local FlowBox = Tabs.Main:AddRightGroupbox("Flow")
local MeasurementsBox = Tabs.Main:AddRightGroupbox("Measurements")

SprintBox:AddToggle("SprintEnabled", {
    Text = "Enable Modifier",
    Default = false,
    Tooltip = "Changes only sprint speed while the sprint key is held."
})

SprintBox:AddSlider("SprintPercent", {
    Text = "Sprint Speed %",
    Default = sprintPercent,
    Min = 0,
    Max = 300,
    Rounding = 0,
    Suffix = "%",
    HideMax = true,
    Compact = false,
    Tooltip = "100% = native sprint. Lower = slower sprint. Higher = faster sprint."
})

SprintBox:AddButton({
    Text = "Reset Sprint % to 100",
    Func = function()
        Options.SprintPercent:SetValue(100)
        notify("Sprint percent reset to 100.", 2)
    end,
    Tooltip = "Restores native sprint baseline."
})

UtilityBox:AddButton({
    Text = "Unload Script",
    Func = function()
        Library:Unload()
    end,
    Tooltip = "Disconnects events and unloads the UI."
})

FlowBox:AddToggle("FlowAwareness", {
    Text = "Flow Awareness",
    Default = flowAwarenessEnabled,
    Tooltip = "Detects Flow and uses separate measured walk/sprint baselines."
})

flowLabel = FlowBox:AddLabel("Flow: not detected")
hookLabel = FlowBox:AddLabel("Remote hook: checking")

FlowBox:AddButton({
    Text = "Reset Flow Measurements",
    Func = function()
        resetFlowMeasurements()
    end,
    Tooltip = "Clears Flow walk and Flow sprint baselines."
})

MeasurementsBox:AddButton({
    Text = "Show Detected Speeds",
    Func = function()
        notify(
            "Walk: " .. fmt(measuredWalkSpeed)
                .. " | Run: " .. fmt(measuredRunSpeed)
                .. " | Flow Walk: " .. fmt(measuredFlowWalkSpeed)
                .. " | Flow Run: " .. fmt(measuredFlowRunSpeed)
                .. " | Target: " .. fmt(getTargetRunSpeed())
                .. " | Flow Target: " .. fmt(getFlowTargetRunSpeed())
                .. " | Slide: " .. getSlideStatusText()
                .. " | Slide Peak: " .. fmt(slidePeakSpeed > 0 and slidePeakSpeed or nil)
                .. " | Guard: " .. measurementGuardStatus
                .. " | Rejected: " .. tostring(measurementRejectedCount)
                .. " | Sample: " .. tostring(sampleSource),
            6
        )
    end,
    Tooltip = "Shows current measured baselines."
})

MeasurementsBox:AddButton({
    Text = "Reset All Measurements",
    Func = function()
        resetAllMeasurements()
    end,
    Tooltip = "Resets normal and Flow measurements."
})

MeasurementsBox:AddDivider()

stateLabel = MeasurementsBox:AddLabel("State: Idle")
normalWalkLabel = MeasurementsBox:AddLabel("Normal walk: " .. fmt(measuredWalkSpeed))
normalRunLabel = MeasurementsBox:AddLabel("Normal sprint: " .. fmt(measuredRunSpeed))
flowWalkLabel = MeasurementsBox:AddLabel("Flow walk: " .. fmt(measuredFlowWalkSpeed))
flowRunLabel = MeasurementsBox:AddLabel("Flow sprint: " .. fmt(measuredFlowRunSpeed))
slideLabel = MeasurementsBox:AddLabel("Slide: none")
guardLabel = MeasurementsBox:AddLabel("Guard: ready")
targetLabel = MeasurementsBox:AddLabel("Target sprint: " .. fmt(getTargetRunSpeed()))

local KeysBox = Tabs.Settings:AddLeftGroupbox("Keybinds")

KeysBox:AddLabel("Toggle modifier"):AddKeyPicker("ToggleKeybind", {
    Default = "LeftAlt",
    SyncToggleState = false,
    Mode = "Toggle",
    Text = "Toggle sprint modifier",
    NoUI = false,
    Callback = function()
        if Toggles and Toggles.SprintEnabled then
            Toggles.SprintEnabled:SetValue(not Toggles.SprintEnabled.Value)
        end
    end
})

KeysBox:AddLabel("Sprint key"):AddKeyPicker("SprintKeybind", {
    Default = "LeftShift",
    SyncToggleState = false,
    Mode = "Hold",
    Text = "Hold to sprint",
    NoUI = false
})

local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")

MenuGroup:AddButton({
    Text = "Unload",
    Func = function()
        Library:Unload()
    end,
    Tooltip = "Unload the interface and script."
})

MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
    Default = "End",
    NoUI = true,
    Text = "Menu keybind"
})

Library.ToggleKeybind = Options.MenuKeybind

----------------------------------------------------------------
-- UI callbacks
----------------------------------------------------------------
Toggles.SprintEnabled:OnChanged(function()
    enabled = Toggles.SprintEnabled.Value == true
    refreshLabels()
    notify(enabled and "Sprint modifier enabled." or "Sprint modifier disabled.", 2)
end)

Options.SprintPercent:OnChanged(function()
    sprintPercent = tonumber(Options.SprintPercent.Value) or 100
    persistMeasurements()
    refreshLabels()
end)

Toggles.FlowAwareness:OnChanged(function()
    setFlowAwareness(Toggles.FlowAwareness.Value == true)
    notify(flowAwarenessEnabled and "Flow awareness enabled." or "Flow awareness disabled.", 2)
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
SaveManager:SetFolder("Locked2/ShiftSprint")

SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])

SaveManager:LoadAutoloadConfig()

----------------------------------------------------------------
-- Input
----------------------------------------------------------------
inputBeganConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end

    if input.KeyCode == Enum.KeyCode.Q then
        beginSlideInputWatch()
        refreshLabels()
    end
end)

----------------------------------------------------------------
-- Core movement loop
----------------------------------------------------------------
heartbeatConn = RunService.Heartbeat:Connect(function(dt)
    if scriptUnloaded or dt <= 0 then
        return
    end

    local held = isSprintHeld()
    if held ~= sprinting then
        sprinting = held
        resetMotionTracking()
        refreshLabels()
    end

    local root, humanoid = getCharacterParts()

    if not root then
        resetMotionTracking()
        return
    end

    if humanoid and humanoid.Health <= 0 then
        resetMotionTracking()
        return
    end

    dt = math.min(dt, 0.1)

    local currentPos = root.Position

    if not lastRootPos then
        lastRootPos = currentPos
        return
    end

    local nativeDelta = horizontal(currentPos - lastRootPos)
    local nativeSpeed = nativeDelta.Magnitude / dt

    if updateSlideState(nativeSpeed) then
        sampleDistance = 0
        sampleDuration = 0
        sampleSource = "slide-lock"
        lastRootPos = currentPos
        return
    end

    if nativeSpeed <= maxReasonableSpeed then
        sampleDistance = sampleDistance + nativeDelta.Magnitude
        sampleDuration = sampleDuration + dt
    end

    if sampleDuration >= sampleInterval then
        local positionSampleSpeed = sampleDistance / sampleDuration
        local velocitySampleSpeed = getVelocitySpeed(root)

        sampleDistance = 0
        sampleDuration = 0

        updateSpeedSamples(positionSampleSpeed, velocitySampleSpeed, humanoid)
    end

    if not enabled or not sprinting or not isMoving(humanoid) then
        lastRootPos = currentPos
        return
    end

    local targetSpeed = getTargetRunSpeed()
    local correctionSpeed = targetSpeed - nativeSpeed

    if math.abs(correctionSpeed) < 0.25 then
        lastRootPos = currentPos
        return
    end

    if nativeDelta.Magnitude <= 0.001 then
        lastRootPos = currentPos
        return
    end

    local direction = nativeDelta.Unit
    root.CFrame = root.CFrame + direction * correctionSpeed * dt

    lastRootPos = root.Position
end)

----------------------------------------------------------------
-- Character respawn
----------------------------------------------------------------
charAddedConn = player.CharacterAdded:Connect(function(character)
    sprinting = false
    setFlowInactive()
    connectSlideAttribute(character)
    resetMotionTracking()
    task.wait(0.5)
end)

----------------------------------------------------------------
-- Status updater
----------------------------------------------------------------
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
    enabled = false
    sprinting = false

    stopFlowDetector()
    setFlowInactive()
    slideActive = false
    slideSource = "none"
    slideLockUntil = 0
    slideInputWatchUntil = 0
    slideNextAttributeCheck = 0
    resetMotionTracking()

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

    if slideAttributeConn then
        slideAttributeConn:Disconnect()
        slideAttributeConn = nil
    end

    if env.Locked2FlowSignal then
        env.Locked2FlowSignal = nil
    end
end

getgenv().Locked2ShiftSprintCleanup = function()
    cleanup()

    pcall(function()
        Library:Unload()
    end)
end

Library:OnUnload(function()
    cleanup()
    Library.Unloaded = true
end)

----------------------------------------------------------------
-- Bootstrap
----------------------------------------------------------------
flowHookReady = setupFlowRemoteHook()

if flowAwarenessEnabled then
    startFlowDetector()
end

connectSlideAttribute(player.Character)

persistMeasurements()
refreshLabels()

notify("Loaded. Walk/sprint to calibrate. Slide state is protected from measurement.", 5)
