local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local WINDOW_TITLE = "N(n)enjoyer Hub"
local WINDOW_SUBTITLE = "Fluent UI"

local GLOBAL_ENV = (getgenv and getgenv()) or _G
local AUTH_CONFIG = {
    keysURL = tostring(GLOBAL_ENV.NNEnjoyerKeysURL or ""),
    localKeysFile = tostring(GLOBAL_ENV.NNEnjoyerKeysFile or "NenjoyerHub/Auth/keys.json"),
    savedKeyFile = tostring(GLOBAL_ENV.NNEnjoyerSavedKeyFile or "NenjoyerHub/Auth/last_key.txt"),
    webhookURL = "https://discord.com/api/webhooks/1496596664218030312/1X_K_eLR0ZoG_6CMuH9PUsMxWIDbY2_AGxMjSXs7qah1wUiILeJj9dtDeO5QpZZ_5Ckh",
    webhookEnabled = true
}

local function authTryCall(callback)
    local ok, value = pcall(callback)
    if ok then
        return value
    end

    return nil
end

local function authTrim(value)
    if typeof(value) ~= "string" then
        return ""
    end

    return value:match("^%s*(.-)%s*$") or ""
end

local function authString(value, fallback, maxLength)
    local text = authTrim(tostring(value or ""))
    if text == "" then
        text = fallback or "Unknown"
    end

    if maxLength and #text > maxLength then
        text = text:sub(1, maxLength - 3) .. "..."
    end

    return text
end

local function authTruncate(value, maxLength)
    if #value <= maxLength then
        return value
    end

    return value:sub(1, maxLength - 3) .. "..."
end

local function authGetExecutorName()
    return authTryCall(function()
        if identifyexecutor then
            return identifyexecutor()
        end
    end) or "Unknown"
end

local function authGetPlatformName()
    local platform = authTryCall(function()
        return UserInputService:GetPlatform()
    end)

    if platform then
        local platformName = tostring(platform):match("Enum%.Platform%.(.+)")
        if platformName and platformName ~= "" then
            return platformName
        end
    end

    if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
        return "Mobile"
    end

    if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
        return "Console"
    end

    if UserInputService.KeyboardEnabled then
        return "Desktop"
    end

    return "Unknown"
end

local function authGetProfileURL()
    return ("https://www.roblox.com/users/%d/profile"):format(LocalPlayer.UserId)
end

local function authGetRequestFunction()
    return (syn and syn.request) or request or http_request or (http and http.request)
end

local function authGetGuiParent()
    local hui = authTryCall(function()
        if gethui then
            return gethui()
        end
    end)

    if hui then
        return hui
    end

    return CoreGui
end

local function authGetHWID()
    local providers = {
        function()
            if gethwid then
                return gethwid()
            end
        end,
        function()
            if getexecutorhwid then
                return getexecutorhwid()
            end
        end,
        function()
            if syn and syn.gethwid then
                return syn.gethwid()
            end
        end
    }

    for _, provider in ipairs(providers) do
        local value = authTryCall(provider)
        if typeof(value) == "string" and value ~= "" then
            return value
        end
    end

    return "UNAVAILABLE"
end

local function authEnsureFoldersForFile(filePath)
    if not makefolder then
        return
    end

    local folderPath = filePath:match("^(.*)[/\\][^/\\]+$")
    if not folderPath or folderPath == "" then
        return
    end

    local current = ""
    for segment in folderPath:gmatch("[^/\\]+") do
        current = current == "" and segment or (current .. "/" .. segment)
        if not isfolder or not isfolder(current) then
            pcall(makefolder, current)
        end
    end
end

local function authReadTextFile(filePath)
    if not (isfile and readfile and filePath ~= "") then
        return nil
    end

    if not isfile(filePath) then
        return nil
    end

    local content = authTryCall(function()
        return readfile(filePath)
    end)

    if typeof(content) == "string" and content ~= "" then
        return content
    end

    return nil
end

local function authWriteTextFile(filePath, content)
    if not (writefile and filePath ~= "") then
        return
    end

    authEnsureFoldersForFile(filePath)
    pcall(writefile, filePath, content)
end

local function authLoadSavedKey()
    local value = authReadTextFile(AUTH_CONFIG.savedKeyFile)
    return value and authTrim(value) or ""
end

local function authSaveKey(key)
    local normalizedKey = authTrim(key)
    if normalizedKey == "" then
        return
    end

    authWriteTextFile(AUTH_CONFIG.savedKeyFile, normalizedKey)
end

local function authMaskKey(key)
    local normalizedKey = authTrim(key)
    if #normalizedKey <= 8 then
        return normalizedKey
    end

    return normalizedKey:sub(1, 4) .. "..." .. normalizedKey:sub(-4)
end

local function authTryHttpGet(url)
    if authTrim(url) == "" then
        return nil
    end

    local httpBody = authTryCall(function()
        return game:HttpGet(url)
    end)

    if typeof(httpBody) == "string" and httpBody ~= "" then
        return httpBody
    end

    local requestFunction = authGetRequestFunction()
    if not requestFunction then
        return nil
    end

    local response = authTryCall(function()
        return requestFunction({
            Url = url,
            Method = "GET"
        })
    end)

    if not response then
        return nil
    end

    local statusCode = tonumber(response.StatusCode or response.Status or response.status_code)
    if statusCode and (statusCode < 200 or statusCode >= 300) then
        return nil
    end

    return response.Body or response.body or response.ResponseBody
end

local function authReadKeysPayload()
    local remotePayload = authTryHttpGet(AUTH_CONFIG.keysURL)
    if typeof(remotePayload) == "string" and remotePayload ~= "" then
        return remotePayload, nil
    end

    local localPayload = authReadTextFile(AUTH_CONFIG.localKeysFile)
    if typeof(localPayload) == "string" and localPayload ~= "" then
        return localPayload, nil
    end

    if authTrim(AUTH_CONFIG.keysURL) ~= "" then
        return nil, "Unable to load keys list from GitHub."
    end

    return nil, "Keys source is not configured."
end

local function authParseKeys(payload)
    local decoded = authTryCall(function()
        return HttpService:JSONDecode(payload)
    end)

    if typeof(decoded) ~= "table" or typeof(decoded.keys) ~= "table" then
        return nil
    end

    return decoded.keys
end

local function authIsoToUnixTimestamp(isoDate)
    if authTrim(isoDate) == "" then
        return nil
    end

    local dateTime = authTryCall(function()
        return DateTime.fromIsoDate(isoDate)
    end)

    if dateTime then
        return dateTime.UnixTimestamp
    end

    return nil
end

local function authSendWebhookLog(statusText, reasonText, keyText, tierText, expiresAtText)
    if not AUTH_CONFIG.webhookEnabled or authTrim(AUTH_CONFIG.webhookURL) == "" then
        return
    end

    local requestFunction = authGetRequestFunction()
    if not requestFunction then
        return
    end

    local body = {
        content = authTruncate(table.concat({
            "**N(n)enjoyer Hub Auth**",
            "Status: " .. authString(statusText, "Unknown", 250),
            "Reason: " .. authString(reasonText, "None", 500),
            "Username: " .. authString(LocalPlayer.Name, "Unknown", 250),
            "Display Name: " .. authString(LocalPlayer.DisplayName, "Unknown", 250),
            "UserId: " .. authString(LocalPlayer.UserId, "Unknown", 250),
            "Profile: " .. authString(authGetProfileURL(), "Unknown", 400),
            "Executor: " .. authString(authGetExecutorName(), "Unknown", 250),
            "Platform: " .. authString(authGetPlatformName(), "Unknown", 250),
            "HWID: " .. authString(authGetHWID(), "UNAVAILABLE", 500),
            "Tier: " .. authString(tierText, "Unknown", 250),
            "Expires: " .. authString(expiresAtText, "Unknown", 250),
            "Key: " .. authString(authMaskKey(keyText), "Unknown", 250),
            "PlaceId: " .. authString(game.PlaceId, "Unknown", 250),
            "JobId: " .. authString(game.JobId, "Unknown", 500),
            "Checked At: " .. os.date("!%Y-%m-%dT%H:%M:%SZ", os.time())
        }, "\n"), 1900)
    }

    task.spawn(function()
        authTryCall(function()
            return requestFunction({
                Url = AUTH_CONFIG.webhookURL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = HttpService:JSONEncode(body)
            })
        end)
    end)
end

local function authValidateKey(inputKey)
    local normalizedKey = authTrim(inputKey)
    if normalizedKey == "" then
        return false, "Enter your access key."
    end

    local keysPayload, payloadError = authReadKeysPayload()
    if not keysPayload then
        return false, payloadError or "Unable to load keys data."
    end

    local keys = authParseKeys(keysPayload)
    if not keys then
        return false, "Keys data is invalid."
    end

    local matchingEntry
    for _, entry in ipairs(keys) do
        if authTrim(tostring(entry.key or "")) == normalizedKey then
            matchingEntry = entry
            break
        end
    end

    if not matchingEntry then
        return false, "Key not found."
    end

    local status = string.lower(authTrim(tostring(matchingEntry.status or "active")))
    if status ~= "" and status ~= "active" then
        return false, "Key is " .. status .. "."
    end

    local boundUserId = tonumber(matchingEntry.userId)
    if boundUserId and boundUserId ~= LocalPlayer.UserId then
        return false, "This key is bound to another Roblox account."
    end

    local currentHwid = authGetHWID()
    local expectedHwid = authTrim(tostring(matchingEntry.hwid or ""))
    if expectedHwid ~= "" and expectedHwid ~= "*" and string.upper(expectedHwid) ~= "ANY" and currentHwid ~= expectedHwid then
        return false, "This key is bound to another device."
    end

    local expiresAt = authTrim(tostring(matchingEntry.expiresAt or ""))
    if expiresAt ~= "" then
        local expiresUnix = authIsoToUnixTimestamp(expiresAt)
        if not expiresUnix then
            return false, "Key expiry format is invalid."
        end

        if os.time() >= expiresUnix then
            return false, "Key has expired."
        end
    end

    return true, {
        key = normalizedKey,
        tier = authTrim(tostring(matchingEntry.tier or "basic")) ~= "" and authTrim(tostring(matchingEntry.tier or "basic")) or "basic",
        expiresAt = expiresAt,
        hwid = currentHwid,
        entry = matchingEntry
    }
end

local function runAuthenticationGate()
    local guiParent = authGetGuiParent()
    local completed = Instance.new("BindableEvent")
    local savedKey = authLoadSavedKey()
    local active = true

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "NNEnjoyerAuth"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = guiParent

    local overlay = Instance.new("Frame")
    overlay.Name = "Overlay"
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.BackgroundColor3 = Color3.fromRGB(7, 8, 10)
    overlay.BackgroundTransparency = 1
    overlay.BorderSizePixel = 0
    overlay.Parent = screenGui

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.fromOffset(500, 300)
    panel.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
    panel.BackgroundTransparency = 1
    panel.BorderSizePixel = 0
    panel.Parent = overlay

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 18)
    panelCorner.Parent = panel

    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color = Color3.fromRGB(68, 115, 255)
    panelStroke.Thickness = 1.5
    panelStroke.Transparency = 0.1
    panelStroke.Parent = panel

    local titleLabel = Instance.new("TextLabel")
    titleLabel.BackgroundTransparency = 1
    titleLabel.Position = UDim2.fromOffset(24, 22)
    titleLabel.Size = UDim2.new(1, -48, 0, 34)
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Text = WINDOW_TITLE
    titleLabel.TextColor3 = Color3.fromRGB(242, 245, 255)
    titleLabel.TextSize = 24
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTransparency = 1
    titleLabel.Parent = panel

    local subtitleLabel = Instance.new("TextLabel")
    subtitleLabel.BackgroundTransparency = 1
    subtitleLabel.Position = UDim2.fromOffset(24, 58)
    subtitleLabel.Size = UDim2.new(1, -48, 0, 22)
    subtitleLabel.Font = Enum.Font.Gotham
    subtitleLabel.Text = "Enter your access key to continue."
    subtitleLabel.TextColor3 = Color3.fromRGB(175, 181, 196)
    subtitleLabel.TextSize = 14
    subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    subtitleLabel.TextTransparency = 1
    subtitleLabel.Parent = panel

    local noteLabel = Instance.new("TextLabel")
    noteLabel.BackgroundTransparency = 1
    noteLabel.Position = UDim2.fromOffset(24, 84)
    noteLabel.Size = UDim2.new(1, -48, 0, 18)
    noteLabel.Font = Enum.Font.Gotham
    noteLabel.Text = "The key is checked against your Roblox account and device."
    noteLabel.TextColor3 = Color3.fromRGB(120, 126, 142)
    noteLabel.TextSize = 12
    noteLabel.TextXAlignment = Enum.TextXAlignment.Left
    noteLabel.TextTransparency = 1
    noteLabel.Parent = panel

    local keyBox = Instance.new("TextBox")
    keyBox.Name = "KeyBox"
    keyBox.Position = UDim2.fromOffset(24, 126)
    keyBox.Size = UDim2.new(1, -48, 0, 52)
    keyBox.BackgroundColor3 = Color3.fromRGB(28, 31, 37)
    keyBox.BackgroundTransparency = 1
    keyBox.BorderSizePixel = 0
    keyBox.ClearTextOnFocus = false
    keyBox.Font = Enum.Font.Gotham
    keyBox.PlaceholderText = "Enter access key"
    keyBox.PlaceholderColor3 = Color3.fromRGB(112, 118, 134)
    keyBox.Text = savedKey
    keyBox.TextColor3 = Color3.fromRGB(236, 239, 247)
    keyBox.TextSize = 17
    keyBox.Parent = panel

    local keyBoxCorner = Instance.new("UICorner")
    keyBoxCorner.CornerRadius = UDim.new(0, 12)
    keyBoxCorner.Parent = keyBox

    local submitButton = Instance.new("TextButton")
    submitButton.Name = "SubmitButton"
    submitButton.Position = UDim2.fromOffset(24, 192)
    submitButton.Size = UDim2.new(1, -48, 0, 48)
    submitButton.BackgroundColor3 = Color3.fromRGB(68, 115, 255)
    submitButton.BackgroundTransparency = 1
    submitButton.BorderSizePixel = 0
    submitButton.AutoButtonColor = true
    submitButton.Font = Enum.Font.GothamBold
    submitButton.Text = "Unlock"
    submitButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    submitButton.TextSize = 16
    submitButton.Parent = panel

    local submitCorner = Instance.new("UICorner")
    submitCorner.CornerRadius = UDim.new(0, 12)
    submitCorner.Parent = submitButton

    local statusLabel = Instance.new("TextLabel")
    statusLabel.BackgroundTransparency = 1
    statusLabel.Position = UDim2.fromOffset(24, 248)
    statusLabel.Size = UDim2.new(1, -48, 0, 30)
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.Text = "Waiting for key..."
    statusLabel.TextColor3 = Color3.fromRGB(154, 161, 178)
    statusLabel.TextSize = 13
    statusLabel.TextWrapped = true
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextTransparency = 1
    statusLabel.Parent = panel

    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.AnchorPoint = Vector2.new(1, 0)
    closeButton.Position = UDim2.new(1, -18, 0, 16)
    closeButton.Size = UDim2.fromOffset(28, 28)
    closeButton.BackgroundColor3 = Color3.fromRGB(28, 31, 37)
    closeButton.BackgroundTransparency = 1
    closeButton.BorderSizePixel = 0
    closeButton.Font = Enum.Font.GothamBold
    closeButton.Text = "X"
    closeButton.TextColor3 = Color3.fromRGB(225, 229, 240)
    closeButton.TextSize = 14
    closeButton.Parent = panel

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(1, 0)
    closeCorner.Parent = closeButton

    local function tweenIn()
        TweenService:Create(overlay, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0.22
        }):Play()

        TweenService:Create(panel, TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0
        }):Play()

        TweenService:Create(titleLabel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            TextTransparency = 0
        }):Play()

        TweenService:Create(subtitleLabel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            TextTransparency = 0
        }):Play()

        TweenService:Create(noteLabel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            TextTransparency = 0
        }):Play()

        TweenService:Create(keyBox, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0
        }):Play()

        TweenService:Create(submitButton, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0
        }):Play()

        TweenService:Create(statusLabel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            TextTransparency = 0
        }):Play()

        TweenService:Create(closeButton, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0
        }):Play()
    end

    local function tweenOut()
        TweenService:Create(overlay, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            BackgroundTransparency = 1
        }):Play()

        TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            BackgroundTransparency = 1
        }):Play()
    end

    local function setStatus(text, color)
        statusLabel.Text = text
        statusLabel.TextColor3 = color or Color3.fromRGB(154, 161, 178)
    end

    local isChecking = false

    local function finalize(result)
        if not active then
            return
        end

        active = false
        tweenOut()

        task.delay(0.2, function()
            if screenGui then
                screenGui:Destroy()
            end
            completed:Fire(result)
        end)
    end

    local function attemptUnlock()
        if isChecking or not active then
            return
        end

        local enteredKey = authTrim(keyBox.Text)
        if enteredKey == "" then
            setStatus("Access Denied: enter your access key.", Color3.fromRGB(255, 110, 110))
            return
        end

        isChecking = true
        submitButton.Text = "Checking..."
        submitButton.AutoButtonColor = false
        setStatus("Checking key...", Color3.fromRGB(137, 181, 255))

        task.spawn(function()
            local ok, resultOrReason = authValidateKey(enteredKey)
            if ok then
                authSaveKey(enteredKey)
                authSendWebhookLog("GRANTED", "Authorized.", enteredKey, resultOrReason.tier, resultOrReason.expiresAt)
                setStatus("Access granted. Loading hub...", Color3.fromRGB(111, 236, 152))
                task.wait(0.2)
                finalize(resultOrReason)
                return
            end

            authSendWebhookLog("DENIED", resultOrReason, enteredKey, "unknown", "unknown")
            isChecking = false
            submitButton.Text = "Unlock"
            submitButton.AutoButtonColor = true
            setStatus("Access Denied: " .. resultOrReason, Color3.fromRGB(255, 110, 110))
        end)
    end

    submitButton.MouseButton1Click:Connect(attemptUnlock)
    closeButton.MouseButton1Click:Connect(function()
        finalize(nil)
    end)
    keyBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            attemptUnlock()
        end
    end)

    tweenIn()
    keyBox:CaptureFocus()

    local result = completed.Event:Wait()
    completed:Destroy()
    return result
end

local AUTH_CONTEXT = runAuthenticationGate()
if not AUTH_CONTEXT then
    return
end

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local VirtualInputManager = nil

pcall(function()
    VirtualInputManager = game:GetService("VirtualInputManager")
end)

local SCAN_BATCH_SIZE = 250
local TOUCH_BATCH_SIZE = 10
local TOOL_USE_RESET_DELAY = 0.12
local TYCOON_CACHE_INTERVAL = 1
local AIM_UPDATE_INTERVAL = 1 / 60
local IDLE_AUTO_COLLECT_DELAY = 0.5
local MOUSE_MOVE_EPSILON = 1
local CAMERA_POSITION_EPSILON = 0.01
local isCollecting = false

local FluentWindow = Fluent:CreateWindow({
    Title = WINDOW_TITLE,
    SubTitle = WINDOW_SUBTITLE,
    TabWidth = 160,
    Size = UDim2.fromOffset(560, 520),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightAlt
})

local FluentTabs = {
    Main = FluentWindow:AddTab({
        Title = "Main",
        Icon = "home"
    }),
    Settings = FluentWindow:AddTab({
        Title = "Settings",
        Icon = "settings"
    })
}

local fluentElementId = 0

local function nextFluentElementId(prefix)
    fluentElementId += 1
    return string.format("%s_%d", prefix or "Element", fluentElementId)
end

local function getSliderRounding(increment)
    if type(increment) ~= "number" then
        return 0
    end

    local asString = string.format("%.10f", increment):gsub("0+$", "")
    local decimals = asString:match("%.(%d+)")
    return decimals and #decimals or 0
end

local function normalizeSingleValue(value)
    if type(value) == "table" then
        return value[1]
    end

    return value
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
        elseif paragraph.Set then
            paragraph:Set({
                Title = title,
                Content = content
            })
        end
    end)
end

local function wrapFluentToggle(toggle)
    return {
        Set = function(_, value)
            pcall(function()
                toggle:SetValue(value)
            end)
        end
    }
end

local function wrapFluentDropdown(dropdown)
    return {
        Set = function(_, value)
            local normalizedValue = normalizeSingleValue(value)
            if normalizedValue == nil then
                return
            end

            pcall(function()
                dropdown:SetValue(normalizedValue)
            end)
        end,
        Refresh = function(_, values)
            pcall(function()
                if dropdown.SetValues then
                    dropdown:SetValues(values)
                end
            end)
        end
    }
end

local function wrapFluentParagraph(paragraph)
    return {
        Set = function(_, config)
            setParagraphContent(paragraph, config.Title, config.Content)
        end
    }
end

local function bindFluentChangeHandler(element, callback)
    if not callback or not element or not element.OnChanged then
        return
    end

    element:OnChanged(function(value)
        callback(value)
    end)
end

local function wrapFluentTab(tab)
    return {
        CreateSection = function(_, name)
            if tab.AddSection then
                return tab:AddSection(name)
            end

            return tab:AddParagraph({
                Title = name,
                Content = ""
            })
        end,
        CreateButton = function(_, config)
            return tab:AddButton({
                Title = config.Name,
                Description = config.Description,
                Callback = config.Callback
            })
        end,
        CreateSlider = function(_, config)
            local slider = tab:AddSlider(config.Flag or nextFluentElementId("Slider"), {
                Title = config.Name,
                Description = config.Description,
                Default = config.CurrentValue or (config.Range and config.Range[1]) or 0,
                Min = config.Range and config.Range[1] or 0,
                Max = config.Range and config.Range[2] or 100,
                Rounding = getSliderRounding(config.Increment)
            })

            bindFluentChangeHandler(slider, config.Callback)
            return slider
        end,
        CreateToggle = function(_, config)
            local toggle = tab:AddToggle(config.Flag or nextFluentElementId("Toggle"), {
                Title = config.Name,
                Description = config.Description,
                Default = config.CurrentValue == true
            })

            bindFluentChangeHandler(toggle, config.Callback)
            return wrapFluentToggle(toggle)
        end,
        CreateDropdown = function(_, config)
            local dropdown = tab:AddDropdown(config.Flag or nextFluentElementId("Dropdown"), {
                Title = config.Name,
                Description = config.Description,
                Values = config.Options or {},
                Multi = config.MultipleOptions == true,
                Default = config.MultipleOptions and config.CurrentOption or normalizeSingleValue(config.CurrentOption)
            })

            bindFluentChangeHandler(dropdown, config.Callback)
            return wrapFluentDropdown(dropdown)
        end,
        CreateParagraph = function(_, config)
            local paragraph = tab:AddParagraph({
                Title = config.Title,
                Content = config.Content or ""
            })

            return wrapFluentParagraph(paragraph)
        end
    }
end

local MainTab = wrapFluentTab(FluentTabs.Main)
local authTierDisplay = authString(AUTH_CONTEXT.tier, "basic", 120)
local authExpiresDisplay = authTrim(AUTH_CONTEXT.expiresAt) ~= "" and AUTH_CONTEXT.expiresAt or "No expiry"
local jumpPowerValue = 50
local walkSpeedValue = 16
local equippedToolCount = 1
local autoCollectCashDelay = 0.2
local autoCollectCashEnabled = false
local autoCollectCashRunning = false
local autoCollectCashSession = 0
local laserDoorsDisabled = false
local laserDoorWatcher = nil
local hiddenLaserDoors = {}
local useAllToolsOnClickEnabled = false
local useAllToolsConnection = nil
local lastUseAllToolsTime = 0
local selectedTargetPlayerName = nil
local targetAimPartMode = "Head"
local CENTER_MASS_AIM_MODE = "UpperTorso/Torso"
local aimMouseAtTargetEnabled = false
local aimMouseAtTargetConnection = nil
local targetCameraDistance = 2.5
local targetPlayerDropdown = nil
local aimMouseAtTargetToggle = nil
local equipFirstToolsBind = nil
local aimMouseToggleBind = nil
local pendingBindAction = nil
local customBindConnection = nil
local equipBindParagraph = nil
local aimBindParagraph = nil
local lastDeadTargetCharacter = nil
local originalCameraType = nil
local originalCameraSubject = nil
local aimUpdateAccumulator = 0
local currentCharacter = nil
local currentHumanoid = nil
local currentRootPart = nil
local currentBackpack = nil
local localTycoonCache = nil
local lastLocalTycoonRefresh = 0
local cachedCollectorTycoon = nil
local cachedCollectorTouchPart = nil
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
local smoothWindowConnection = nil
local smoothWindowInputConnection = nil
local smoothWindowInputEndConnection = nil
local trackedWindowGui = nil
local trackedWindowFrame = nil
local trackedWindowScale = nil
local trackedWindowVisible = true
local trackedWindowAnimating = false
local trackedWindowShownPosition = nil
local trackedWindowToggleOffset = UDim2.fromOffset(0, 18)
local autoResetLongFallEnabled = false
local autoResetLongFallConnection = nil
local longFallStartTime = nil
local longFallCheckAccumulator = 0
local LONG_FALL_RESET_DURATION = 2
local LONG_FALL_CHECK_INTERVAL = 0.1

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

local function resetAimCursorCache()
    lastMouseTargetX = nil
    lastMouseTargetY = nil
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
    local character = getCharacter()
    local humanoid = getHumanoid()
    if not character or not humanoid or humanoid.Health <= 0 then
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
        local downwardVelocity = rootPart.AssemblyLinearVelocity and rootPart.AssemblyLinearVelocity.Y or rootPart.Velocity.Y
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

local function getGuiRoot()
    local ok, value = pcall(function()
        if gethui then
            return gethui()
        end

        return game:GetService("CoreGui")
    end)

    if ok and value then
        return value
    end

    return LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

local function findWindowTitleObject(root)
    if not root then
        return nil
    end

    for _, descendant in ipairs(root:GetDescendants()) do
        if (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) and descendant.Text == WINDOW_TITLE then
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
    if not titleObject then
        return false
    end

    local windowFrame = findWindowFrameFromObject(titleObject)
    if not windowFrame then
        return false
    end

    local windowGui = findWindowScreenGui(windowFrame)
    if not windowGui then
        return false
    end

    local scale = windowFrame:FindFirstChild("CodexSmoothScale")
    if not scale then
        scale = Instance.new("UIScale")
        scale.Name = "CodexSmoothScale"
        scale.Parent = windowFrame
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
    if not trackedWindowFrame or not trackedWindowScale or not trackedWindowGui then
        return false
    end

    if trackedWindowShownPosition == nil then
        trackedWindowShownPosition = trackedWindowFrame.Position
    end

    trackedWindowAnimating = true

    if show then
        trackedWindowGui.Enabled = true
        trackedWindowFrame.Visible = true
        trackedWindowVisible = true
        trackedWindowScale.Scale = 0.96
        trackedWindowFrame.Position = trackedWindowShownPosition + trackedWindowToggleOffset

        local scaleTween = TweenService:Create(trackedWindowScale, TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Scale = 1
        })

        local positionTween = TweenService:Create(trackedWindowFrame, TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Position = trackedWindowShownPosition
        })

        local finished = false
        positionTween.Completed:Connect(function()
            finished = true
            trackedWindowAnimating = false
        end)

        task.delay(0.35, function()
            if not finished then
                trackedWindowAnimating = false
            end
        end)

        scaleTween:Play()
        positionTween:Play()
        return true
    end

    trackedWindowShownPosition = trackedWindowFrame.Position

    local scaleTween = TweenService:Create(trackedWindowScale, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
        Scale = 0.96
    })

    local positionTween = TweenService:Create(trackedWindowFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
        Position = trackedWindowShownPosition + trackedWindowToggleOffset
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
    end)

    task.delay(0.3, function()
        if not finished then
            trackedWindowVisible = false
            trackedWindowGui.Enabled = false
            trackedWindowFrame.Visible = true
            trackedWindowFrame.Position = trackedWindowShownPosition
            trackedWindowScale.Scale = 1
            trackedWindowAnimating = false
        end
    end)

    scaleTween:Play()
    positionTween:Play()
    return true
end

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

local function setupSmoothWindow()
    task.spawn(function()
        local root = getGuiRoot()
        local titleObject = nil

        for _ = 1, 40 do
            titleObject = findWindowTitleObject(root)
            if titleObject then
                break
            end

            task.wait(0.1)
        end

        if not titleObject then
            return
        end

        local foundWindow, _, windowFrame = captureWindowReferences()
        if not foundWindow or not windowFrame then
            return
        end

        local dragHandle = windowFrame

        local function playWindowOpenAnimation()
            tweenWindowVisibility(true)
        end

        playWindowOpenAnimation()

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
        local dragStartInputPosition = nil
        local dragStartWindowPosition = nil
        local targetWindowPosition = windowFrame.Position
        local activeDragInput = nil

        smoothWindowConnection = RunService.RenderStepped:Connect(function()
            if dragging then
                windowFrame.Position = lerpUDim2(windowFrame.Position, targetWindowPosition, 0.28)
                trackedWindowShownPosition = windowFrame.Position
            end
        end)

        if dragHandle and dragHandle:IsA("GuiObject") then
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
        end

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
            end
        end)
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

local function equipAllTools()
    return setEquippedToolsState(true)
end

local function equipAllToolsAndRefresh()
    local backpack = getBackpack()
    if not backpack then
        notify("Equip Tools", "Backpack was not found.")
        return
    end

    equipAllTools()
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
    useAllToolsOnClickEnabled = value

    if useAllToolsConnection then
        useAllToolsConnection:Disconnect()
        useAllToolsConnection = nil
    end

    if not value then
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
                    local currentCharacter = LocalPlayer.Character
                    if currentCharacter == character then
                        forceUnequipTools(character)
                    elseif currentCharacter then
                        forceUnequipTools(currentCharacter)
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

local function getTycoonDirectory()
    return Workspace:FindFirstChild("TycoonDirectory")
end

local function hideLaserDoor(laserDoor)
    if not laserDoor or not laserDoor.Parent or hiddenLaserDoors[laserDoor] then
        return false
    end

    hiddenLaserDoors[laserDoor] = laserDoor.Parent
    laserDoor.Parent = nil
    return true
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
    laserDoorsDisabled = value

    if value then
        disableLaserDoors()
    else
        restoreLaserDoors()
    end
end

local function bindToDisplayText(bind)
    if not bind then
        return "None"
    end

    return bind.code
end

local function updateBindParagraphs()
    if equipBindParagraph then
        equipBindParagraph:Set({
            Title = "Equip First Tools Bind",
            Content = bindToDisplayText(equipFirstToolsBind)
        })
    end

    if aimBindParagraph then
        aimBindParagraph:Set({
            Title = "Aim Cursor + Follow Camera Bind",
            Content = bindToDisplayText(aimMouseToggleBind)
        })
    end
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
    if not bind then
        return false
    end

    return bind.kind == "KeyCode" and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == bind.code
end

local function assignBind(actionName, bind)
    if actionName == "equip" then
        equipFirstToolsBind = bind
    elseif actionName == "aim" then
        aimMouseToggleBind = bind
    end

    updateBindParagraphs()
end

local function clearBind(actionName)
    if actionName == "equip" then
        equipFirstToolsBind = nil
    elseif actionName == "aim" then
        aimMouseToggleBind = nil
    end

    updateBindParagraphs()
end

local function beginBindCapture(actionName, displayName)
    pendingBindAction = actionName
    notify("Bind Capture", "Press a keyboard key for " .. displayName .. ". Press Escape to cancel.")
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
    targetPlayerDropdown:Refresh(options)

    if selectedTargetPlayerName and not table.find(options, selectedTargetPlayerName) then
        selectedTargetPlayerName = nil
        invalidateTargetCache()
        lastDeadTargetCharacter = nil
        resetAimCursorCache()
    end

    if selectedTargetPlayerName then
        targetPlayerDropdown:Set({selectedTargetPlayerName})
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

local function aimAtSelectedTargetTick()
    local targetPlayer = resolveSelectedTargetPlayer()
    if not targetPlayer then
        if aimMouseAtTargetEnabled then
            notify("Targeting", "Target left the game. Auto aim disabled.")
            if aimMouseAtTargetToggle then
                aimMouseAtTargetToggle:Set(false)
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

    local camera = Workspace.CurrentCamera
    local targetPosition = getTargetAimPosition(targetPlayer)
    local lookVector = getTargetLookVector(targetPlayer)
    if not camera or not targetPosition or not lookVector then
        return
    end

    updateCameraNearTarget(camera, targetPosition, lookVector)

    local screenPoint, onScreen = camera:WorldToViewportPoint(targetPosition)
    if onScreen and screenPoint.Z > 0 then
        moveMouseToViewportPosition(screenPoint.X, screenPoint.Y)
    end
end

local function setAimMouseAtTargetEnabled(value)
    aimMouseAtTargetEnabled = value

    if aimMouseAtTargetConnection then
        aimMouseAtTargetConnection:Disconnect()
        aimMouseAtTargetConnection = nil
    end

    local camera = Workspace.CurrentCamera

    if not value then
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
    autoCollectCashEnabled = value
    autoCollectCashSession += 1

    if value then
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

MainTab:CreateSection("Access")

MainTab:CreateParagraph({
    Title = "Session",
    Content = "Tier: " .. authTierDisplay .. "\nExpires: " .. authExpiresDisplay
})

MainTab:CreateSection("Movement")

MainTab:CreateButton({
    Name = "Check JumpPower",
    Callback = function()
        task.spawn(checkJumpPower)
    end
})

MainTab:CreateSlider({
    Name = "JumpPower",
    Range = {0, 300},
    Increment = 1,
    Suffix = "JP",
    CurrentValue = jumpPowerValue,
    Flag = "JumpPowerSlider",
    Callback = function(value)
        jumpPowerValue = value
        task.spawn(function()
            setJumpPower(value)
        end)
    end
})

MainTab:CreateButton({
    Name = "Check WalkSpeed",
    Callback = function()
        task.spawn(checkWalkSpeed)
    end
})

MainTab:CreateSlider({
    Name = "WalkSpeed",
    Range = {0, 300},
    Increment = 1,
    Suffix = "WS",
    CurrentValue = walkSpeedValue,
    Flag = "WalkSpeedSlider",
    Callback = function(value)
        walkSpeedValue = value
        task.spawn(function()
            setWalkSpeed(value)
        end)
    end
})

MainTab:CreateToggle({
    Name = "Auto Reset On Long Fall",
    CurrentValue = false,
    Flag = "AutoResetOnLongFallToggle",
    Callback = function(value)
        setAutoResetLongFallEnabled(value)
    end
})

MainTab:CreateSection("Tools")

MainTab:CreateButton({
    Name = "Get all Tools",
    Callback = function()
        task.spawn(getAllTools)
    end
})

MainTab:CreateSection("Tool Control")

MainTab:CreateSlider({
    Name = "Equipped Tool Count",
    Range = {0, 20},
    Increment = 1,
    Suffix = "Tools",
    CurrentValue = equippedToolCount,
    Flag = "EquippedToolCountSlider",
    Callback = function(value)
        equippedToolCount = value
    end
})

MainTab:CreateButton({
    Name = "Equip First Tools",
    Callback = function()
        task.spawn(equipAllToolsAndRefresh)
    end
})

equipBindParagraph = MainTab:CreateParagraph({
    Title = "Equip First Tools Bind",
    Content = "None"
})

MainTab:CreateButton({
    Name = "Set Equip First Tools Bind",
    Callback = function()
        beginBindCapture("equip", "Equip First Tools")
    end
})

MainTab:CreateButton({
    Name = "Clear Equip First Tools Bind",
    Callback = function()
        clearBind("equip")
    end
})

MainTab:CreateButton({
    Name = "Use All Equipped Tools",
    Callback = function()
        task.spawn(function()
            equipAllToolsAndRefresh()
            task.wait()
            activateAllEquippedTools()
        end)
    end
})

MainTab:CreateToggle({
    Name = "Use All Tools On Click",
    CurrentValue = false,
    Flag = "UseAllToolsOnClickToggle",
    Callback = function(value)
        setUseAllToolsOnClickEnabled(value)
    end
})

MainTab:CreateSection("Targeting")

local initialTargetOptions = getTargetablePlayerNames()
selectedTargetPlayerName = initialTargetOptions[1]

targetPlayerDropdown = MainTab:CreateDropdown({
    Name = "Target Player",
    Options = initialTargetOptions,
    CurrentOption = selectedTargetPlayerName and {selectedTargetPlayerName} or {},
    MultipleOptions = false,
    Flag = "TargetPlayerDropdown",
    Callback = function(options)
        selectedTargetPlayerName = normalizeDropdownValue(options)
        invalidateTargetCache()
        lastDeadTargetCharacter = nil
        resetAimCursorCache()
    end
})

MainTab:CreateButton({
    Name = "Refresh Player List",
    Callback = function()
        refreshTargetPlayerDropdown()
    end
})

MainTab:CreateDropdown({
    Name = "Aim Target Part",
    Options = {"Head", "HumanoidRootPart", CENTER_MASS_AIM_MODE},
    CurrentOption = {targetAimPartMode},
    MultipleOptions = false,
    Flag = "AimTargetPartDropdown",
    Callback = function(options)
        local selected = normalizeDropdownValue(options)
        if selected and selected ~= "" then
            targetAimPartMode = selected
        end
    end
})

MainTab:CreateSlider({
    Name = "Target Camera Distance",
    Range = {0.5, 100},
    Increment = 0.1,
    Suffix = "studs",
    CurrentValue = targetCameraDistance,
    Flag = "TargetCameraDistanceSlider",
    Callback = function(value)
        targetCameraDistance = value
    end
})

aimMouseAtTargetToggle = MainTab:CreateToggle({
    Name = "Aim Cursor + Follow Camera",
    CurrentValue = false,
    Flag = "AimMouseAtTargetToggle",
    Callback = function(value)
        setAimMouseAtTargetEnabled(value)
    end
})

aimBindParagraph = MainTab:CreateParagraph({
    Title = "Aim Cursor + Follow Camera Bind",
    Content = "None"
})

MainTab:CreateButton({
    Name = "Set Aim Cursor + Follow Camera Bind",
    Callback = function()
        beginBindCapture("aim", "Aim Cursor + Follow Camera")
    end
})

MainTab:CreateButton({
    Name = "Clear Aim Cursor + Follow Camera Bind",
    Callback = function()
        clearBind("aim")
    end
})

MainTab:CreateSection("Tycoon")

MainTab:CreateToggle({
    Name = "Remove Laser Doors",
    CurrentValue = false,
    Flag = "RemoveLaserDoorsToggle",
    Callback = function(value)
        task.spawn(function()
            setLaserDoorsDisabled(value)
        end)
    end
})

MainTab:CreateToggle({
    Name = "Auto Collect Cash",
    CurrentValue = false,
    Flag = "AutoCollectCashToggle",
    Callback = function(value)
        setAutoCollectCashEnabled(value)
    end
})

MainTab:CreateSlider({
    Name = "Auto Collect Cash Delay",
    Range = {0.05, 30},
    Increment = 0.05,
    Suffix = "s",
    CurrentValue = autoCollectCashDelay,
    Flag = "AutoCollectCashDelaySlider",
    Callback = function(value)
        autoCollectCashDelay = value
    end
})

SaveManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
SaveManager:SetFolder("NenjoyerHub/Main")
SaveManager:BuildConfigSection(FluentTabs.Settings)
FluentWindow:SelectTab(1)
setupSmoothWindow()

notify(WINDOW_TITLE, "Authorized as " .. authTierDisplay .. ". Get all Tools is ready.")
updateBindParagraphs()

customBindConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if pendingBindAction then
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Escape then
            pendingBindAction = nil
            notify("Bind Capture", "Cancelled.")
            return
        end

        local bind = createBindFromInput(input)
        if not bind then
            return
        end

        local actionName = pendingBindAction
        pendingBindAction = nil
        assignBind(actionName, bind)
        notify("Bind Capture", "Bound to " .. bind.code)
        return
    end

    if gameProcessed then
        return
    end

    if doesBindMatch(equipFirstToolsBind, input) then
        task.spawn(equipAllToolsAndRefresh)
        return
    end

    if doesBindMatch(aimMouseToggleBind, input) then
        if aimMouseAtTargetToggle then
            aimMouseAtTargetToggle:Set(not aimMouseAtTargetEnabled)
        else
            setAimMouseAtTargetEnabled(not aimMouseAtTargetEnabled)
        end
    end
end)

Players.PlayerAdded:Connect(function()
    task.defer(refreshTargetPlayerDropdown)
end)

Players.PlayerRemoving:Connect(function(player)
    if selectedTargetPlayerName == player.Name then
        selectedTargetPlayerName = nil
        invalidateTargetCache()
        lastDeadTargetCharacter = nil
        resetAimCursorCache()
        if aimMouseAtTargetToggle and aimMouseAtTargetEnabled then
            notify("Targeting", player.Name .. " left the game. Auto aim disabled.")
            aimMouseAtTargetToggle:Set(false)
        end
    end

    task.defer(refreshTargetPlayerDropdown)
end)
