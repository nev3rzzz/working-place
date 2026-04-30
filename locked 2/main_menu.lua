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
local slideWatchStartSpeed = 0
local latestNativeSpeed = 0
local teleportGuardUntil = 0
local teleportGuardStatus = "ready"

local measurementGuardStatus = "ready"
local measurementRejectedCount = tonumber(env.Locked2MeasurementRejectedCount) or 0
local staminaSprintAvailable = false
local staminaGuardStatus = "waiting"
local baselineGuardStatus = "waiting for sprint sample"

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
local staminaSprintMargin = 2.5
local staminaSprintBonusRatio = 0.35
local staminaGraceDuration = 0.28
local staminaGraceUntil = 0
local staminaAnimationStartGrace = 0.35
local staminaAnimationDropGrace = 0.08
local sprintHeldStartedAt = 0
local sprintAnimationLastRunAt = 0

local runAnimationIds = {
    ["rbxassetid://119815085344016"] = true
}

local walkAnimationIds = {
    ["rbxassetid://93741384217371"] = true
}

local slideInputWatchDuration = 0.75
local slideRecoveryGrace = 0.95
local slideVelocityGrace = 1.15
local slideAttributeCheckInterval = 0.12
local slideVelocityMinDelta = 18
local slideVelocityMinRatio = 1.25
local teleportDistanceThreshold = 35
local teleportSpeedThreshold = 260
local teleportPauseDuration = 1.25

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
local staminaLabel
local baselineLabel
local teleportLabel
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

local function isTeleportGuardActive()
    return os.clock() < teleportGuardUntil
end

local function enterTeleportGuard(distance, speed)
    local now = os.clock()

    teleportGuardUntil = math.max(teleportGuardUntil, now + teleportPauseDuration)
    teleportGuardStatus = string.format("pause %.0f st / %.0f st/s", distance or 0, speed or 0)
    sampleSource = "teleport"
    staminaSprintAvailable = false
    staminaGuardStatus = "teleport"

    resetMotionTracking()
    samplePauseUntil = math.max(samplePauseUntil, teleportGuardUntil)
end

local function isLikelyTeleportDelta(delta, speed)
    if typeof(delta) ~= "Vector3" then
        return false
    end

    if type(speed) ~= "number" or speed ~= speed then
        return false
    end

    return delta.Magnitude >= teleportDistanceThreshold or speed >= teleportSpeedThreshold
end

local function getTeleportStatusText()
    local now = os.clock()

    if now < teleportGuardUntil then
        return string.format("pause %.1fs", teleportGuardUntil - now)
    end

    if teleportGuardStatus ~= "ready" then
        teleportGuardStatus = "ready"
    end

    return teleportGuardStatus
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

local function getCurrentRootHorizontalSpeed()
    local root = getCharacterParts()
    if not root then
        return latestNativeSpeed or 0
    end

    local velocity = root.AssemblyLinearVelocity or root.Velocity
    if typeof(velocity) ~= "Vector3" then
        return latestNativeSpeed or 0
    end

    local speed = horizontal(velocity).Magnitude
    if type(speed) ~= "number" or speed ~= speed then
        return latestNativeSpeed or 0
    end

    return speed
end

local function beginSlideInputWatch()
    if scriptUnloaded then
        return
    end

    -- Q only hints that the player tried to slide. Cooldown presses must not
    -- create slide-lock; the real detector is the character Sliding attribute.
    local now = os.clock()
    slideNextAttributeCheck = 0
    samplePauseUntil = math.max(samplePauseUntil, now + 0.25)
    sampleSource = "q-pressed"
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
    slideWatchStartSpeed = 0

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

local function getActiveWalkSpeed()
    if flowAwarenessEnabled and inFlow and measuredFlowWalkSpeed and measuredFlowWalkSpeed > 0 then
        return measuredFlowWalkSpeed
    end

    return measuredWalkSpeed
end

local function getActiveRunSpeed()
    if flowAwarenessEnabled and inFlow and measuredFlowRunSpeed and measuredFlowRunSpeed > 0 then
        return measuredFlowRunSpeed
    end

    return measuredRunSpeed
end

local function hasNormalRunBaseline()
    return measurementAnchors.Run ~= nil
        and measuredRunSpeed ~= nil
        and measuredRunSpeed > measuredWalkSpeed
end

local function hasFlowRunBaseline()
    return measurementAnchors.FlowRun ~= nil
        and measuredFlowRunSpeed ~= nil
        and measuredFlowRunSpeed > (measuredFlowWalkSpeed or measuredWalkSpeed)
end

local function canModifySprintSpeed()
    if flowAwarenessEnabled and inFlow then
        if hasFlowRunBaseline() then
            baselineGuardStatus = "flow baseline ready"
            return true
        end

        if hasNormalRunBaseline() then
            baselineGuardStatus = "flow fallback: normal baseline"
            return true
        end

        baselineGuardStatus = "waiting for sprint baseline"
        return false
    end

    if hasNormalRunBaseline() then
        baselineGuardStatus = "normal baseline ready"
        return true
    end

    baselineGuardStatus = "waiting for sprint baseline"
    return false
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
    local startSpeed = math.max(slideWatchStartSpeed or 0, 0)
    local jumpThreshold = math.max(
        threshold,
        startSpeed + slideVelocityMinDelta,
        startSpeed * slideVelocityMinRatio
    )

    return nativeSpeed >= jumpThreshold
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

    if isSlideLocked() and type(nativeSpeed) == "number" and nativeSpeed == nativeSpeed then
        slidePeakSpeed = math.max(slidePeakSpeed, math.max(nativeSpeed, 0))
    end

    if not isSlideLocked() then
        slideSource = "none"
        slideWatchStartSpeed = 0
        slideInputWatchUntil = 0
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
    elseif isTeleportGuardActive() then
        state = "Teleport Guard"
    elseif enabled and sprinting and moving and staminaSprintAvailable and canModifySprintSpeed() then
        state = "Modifying Sprint"
    elseif sprinting and moving and staminaSprintAvailable then
        state = "Sprinting"
    elseif sprinting and moving then
        state = "Walking (stamina/calibration)"
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
    safeSetLabel(staminaLabel, "Stamina: " .. staminaGuardStatus)
    safeSetLabel(baselineLabel, "Baseline: " .. baselineGuardStatus)
    safeSetLabel(teleportLabel, "Teleport: " .. getTeleportStatusText())
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

local function getAnimationId(track)
    local ok, animation = pcall(function()
        return track.Animation
    end)

    if ok and animation then
        local animationId = tostring(animation.AnimationId or "")
        if animationId ~= "" then
            return animationId
        end
    end

    return ""
end

local function getSprintAnimationState(humanoid)
    if not humanoid then
        return false, false
    end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        return false, false
    end

    local ok, tracks = pcall(function()
        return animator:GetPlayingAnimationTracks()
    end)

    if not ok or type(tracks) ~= "table" then
        return false, false
    end

    local runPlaying = false
    local walkPlaying = false

    for _, track in ipairs(tracks) do
        if track.IsPlaying then
            local name = tostring(track.Name or ""):lower()
            local animationId = getAnimationId(track)

            if runAnimationIds[animationId] or name == "run" or name:find("run", 1, true) then
                runPlaying = true
            end

            if walkAnimationIds[animationId] or name == "walkanim" or name:find("walk", 1, true) then
                walkPlaying = true
            end
        end
    end

    return runPlaying, walkPlaying
end

local function getMinimumNativeSprintSpeed()
    local walk = getActiveWalkSpeed()
    local run = math.max(getActiveRunSpeed(), walk)
    local bonus = math.max(run - walk, 0)

    return walk + math.max(staminaSprintMargin, bonus * staminaSprintBonusRatio)
end

local function updateStaminaSprintAvailability(humanoid, nativeSpeed)
    if not sprinting or not isMoving(humanoid) then
        staminaSprintAvailable = false
        staminaGuardStatus = sprinting and "held idle" or "not held"
        return false
    end

    local now = os.clock()
    local runAnimationPlaying, walkAnimationPlaying = getSprintAnimationState(humanoid)
    local sprintHeldFor = sprintHeldStartedAt > 0 and (now - sprintHeldStartedAt) or 0

    if runAnimationPlaying then
        sprintAnimationLastRunAt = now
    end

    if walkAnimationPlaying
        and not runAnimationPlaying
        and sprintHeldFor >= staminaAnimationStartGrace
        and (now - sprintAnimationLastRunAt) >= staminaAnimationDropGrace then
        staminaSprintAvailable = false
        staminaGraceUntil = 0
        staminaGuardStatus = "walk animation / stamina"
        return false
    end

    local humanoidSpeed = getHumanoidWalkSpeed(humanoid)
    local minSprint = getMinimumNativeSprintSpeed()
    local nativeSaysSprint = humanoidSpeed and humanoidSpeed >= minSprint

    if not nativeSaysSprint and (not enabled or sprintPercent == 100) then
        nativeSaysSprint = nativeSpeed and nativeSpeed >= minSprint
    end

    if nativeSaysSprint then
        staminaSprintAvailable = true
        staminaGraceUntil = os.clock() + staminaGraceDuration
        staminaGuardStatus = "native sprint"
        return true
    end

    if os.clock() < staminaGraceUntil then
        staminaGuardStatus = "grace"
        return true
    end

    staminaSprintAvailable = false
    staminaGuardStatus = "stamina empty / walking"
    return false
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
    if sprinting and staminaSprintAvailable and enabled and sprintPercent ~= 100 and humanoidValid then
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
    local samplingAsSprint = sprinting and staminaSprintAvailable

    if not isValidSampleSpeed(sampleSpeed) then
        return
    end

    if samplingAsSprint and not canSampleSprintSpeed() then
        if not humanoidSpeed then
            return
        end

        sampleSpeed = humanoidSpeed
        sampleSource = "humanoid"
    end

    if samplingAsSprint then
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
    baselineGuardStatus = "waiting for sprint sample"
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
    baselineGuardStatus = "waiting for flow sprint sample"

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
                .. " | Stamina: " .. staminaGuardStatus
                .. " | Baseline: " .. baselineGuardStatus
                .. " | Teleport: " .. getTeleportStatusText()
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
staminaLabel = MeasurementsBox:AddLabel("Stamina: waiting")
baselineLabel = MeasurementsBox:AddLabel("Baseline: waiting")
teleportLabel = MeasurementsBox:AddLabel("Teleport: ready")
guardLabel = MeasurementsBox:AddLabel("Guard: ready")
targetLabel = MeasurementsBox:AddLabel("Target sprint: " .. fmt(getTargetRunSpeed()))

local KeysBox = Tabs.Settings:AddLeftGroupbox("Keybinds")

KeysBox:AddLabel("Toggle modifier"):AddKeyPicker("ToggleKeybind", {
    Default = "N",
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
    Default = "RightAlt",
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
    "MenuKeybind",
    "ToggleKeybind"
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
        sprintHeldStartedAt = held and os.clock() or 0
        if not held then
            sprintAnimationLastRunAt = 0
            staminaSprintAvailable = false
            staminaGuardStatus = "not held"
        end
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
    latestNativeSpeed = nativeSpeed

    if isLikelyTeleportDelta(nativeDelta, nativeSpeed) then
        enterTeleportGuard(nativeDelta.Magnitude, nativeSpeed)
        lastRootPos = currentPos
        return
    end

    if isTeleportGuardActive() then
        sampleDistance = 0
        sampleDuration = 0
        sampleSource = "teleport"
        lastRootPos = currentPos
        return
    end

    if updateSlideState(nativeSpeed) then
        sampleDistance = 0
        sampleDuration = 0
        sampleSource = "slide-lock"
        staminaSprintAvailable = false
        staminaGuardStatus = "slide"
        lastRootPos = currentPos
        return
    end

    local nativeSprintAvailable = updateStaminaSprintAvailability(humanoid, nativeSpeed)

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

    if not enabled or not sprinting or not nativeSprintAvailable or not canModifySprintSpeed() or not isMoving(humanoid) then
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
    staminaSprintAvailable = false
    staminaGuardStatus = "respawn"
    baselineGuardStatus = "waiting for sprint sample"
    sprintHeldStartedAt = 0
    sprintAnimationLastRunAt = 0
    teleportGuardUntil = os.clock() + teleportPauseDuration
    teleportGuardStatus = "respawn"
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
    staminaSprintAvailable = false
    staminaGuardStatus = "unloaded"
    sprintHeldStartedAt = 0
    sprintAnimationLastRunAt = 0
    teleportGuardUntil = 0
    teleportGuardStatus = "ready"

    stopFlowDetector()
    setFlowInactive()
    slideActive = false
    slideSource = "none"
    slideLockUntil = 0
    slideInputWatchUntil = 0
    slideNextAttributeCheck = 0
    slideWatchStartSpeed = 0
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
