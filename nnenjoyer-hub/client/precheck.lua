local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local function tryCall(callback)
    local ok, value = pcall(callback)
    if ok then
        return value
    end

    return nil
end

local function getRequestFunction()
    return (syn and syn.request) or request or http_request or (http and http.request)
end

local function downloadText(url)
    local body = tryCall(function()
        return game:HttpGet(url)
    end)

    if typeof(body) == "string" and body ~= "" then
        return body
    end

    local requestFunction = getRequestFunction()
    if not requestFunction then
        return nil
    end

    local response = tryCall(function()
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

    local responseBody = response.Body or response.body or response.ResponseBody
    if typeof(responseBody) == "string" and responseBody ~= "" then
        return responseBody
    end

    return nil
end

local function loadFluent()
    local sources = {
        "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/main.lua",
        "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"
    }

    for _, url in ipairs(sources) do
        local source = downloadText(url)
        if typeof(source) == "string" and source ~= "" then
            local chunk = tryCall(function()
                return loadstring(source)
            end)

            if type(chunk) == "function" then
                local library = tryCall(chunk)
                if type(library) == "table" then
                    return library
                end
            end
        end
    end

    error("Failed to load Fluent UI.")
end

local Fluent = loadFluent()

local CONFIG = {
    webhookURL = "https://discord.com/api/webhooks/1496596664218030312/1X_K_eLR0ZoG_6CMuH9PUsMxWIDbY2_AGxMjSXs7qah1wUiILeJj9dtDeO5QpZZ_5Ckh",
    defaultKey = "TEMP-REPLACE-ME",
    defaultTier = "basic",
    durationHours = 24,
    note = "issued via precheck"
}

local function getExecutorName()
    return tryCall(function()
        if identifyexecutor then
            return identifyexecutor()
        end
    end) or "Unknown"
end

local function getHWID()
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
        local value = tryCall(provider)
        if typeof(value) == "string" and value ~= "" then
            return value
        end
    end

    return "UNAVAILABLE"
end

local function getPlatformName()
    local platform = tryCall(function()
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

local function toIsoUtc(unixTimestamp)
    return os.date("!%Y-%m-%dT%H:%M:%SZ", unixTimestamp)
end

local function trim(value)
    if typeof(value) ~= "string" then
        return ""
    end

    return value:match("^%s*(.-)%s*$") or ""
end

local function getProfileURL()
    return ("https://www.roblox.com/users/%d/profile"):format(LocalPlayer.UserId)
end

local function webhookString(value, fallback, maxLength)
    local text = trim(tostring(value or ""))
    if text == "" then
        text = fallback or "Unknown"
    end

    if maxLength and #text > maxLength then
        text = text:sub(1, maxLength - 3) .. "..."
    end

    return text
end

local function isHttpUrl(value)
    return typeof(value) == "string" and value:match("^https?://") ~= nil
end

local function truncateForDiscord(value, maxLength)
    if #value <= maxLength then
        return value
    end

    return value:sub(1, maxLength - 3) .. "..."
end

local function getAvatarThumbnailURL()
    local avatarTypes = {
        Enum.ThumbnailType.AvatarThumbnail,
        Enum.ThumbnailType.HeadShot
    }

    local thumbnailSizes = {
        Enum.ThumbnailSize.Size420x420,
        Enum.ThumbnailSize.Size352x352,
        Enum.ThumbnailSize.Size180x180
    }

    for _, thumbnailType in ipairs(avatarTypes) do
        for _, thumbnailSize in ipairs(thumbnailSizes) do
            local content, isReady = tryCall(function()
                return Players:GetUserThumbnailAsync(LocalPlayer.UserId, thumbnailType, thumbnailSize)
            end)

            if typeof(content) == "string" and content ~= "" then
                return content, isReady == true
            end
        end
    end

    return nil, false
end

local function promptDiscordUsername()
    local completed = Instance.new("BindableEvent")
    local discordUsernameValue = ""

    local window = Fluent:CreateWindow({
        Title = "N(n)enjoyer Hub",
        SubTitle = "Discord Verification",
        TabWidth = 160,
        Size = UDim2.fromOffset(520, 280),
        Acrylic = false,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.RightAlt
    })

    local tab = window:AddTab({
        Title = "Verify",
        Icon = "shield-check"
    })

    tab:AddParagraph({
        Title = "Discord Username",
        Content = "Enter your Discord username for verification before precheck data is submitted."
    })

    local input = tab:AddInput("DiscordUsernameInput", {
        Title = "Discord Username",
        Default = "",
        Placeholder = "@yourname or yourname#1234",
        Numeric = false,
        Finished = false,
        Callback = function(value)
            discordUsernameValue = value
        end
    })

    local function submit()
        local value = trim(input.Value or discordUsernameValue)
        if value == "" then
            Fluent:Notify({
                Title = "N(n)enjoyer Hub",
                Content = "Discord username is required.",
                Duration = 4
            })
            return
        end

        completed:Fire(value)
    end

    tab:AddButton({
        Title = "Continue",
        Description = "Submit precheck with this Discord username",
        Callback = submit
    })

    window:SelectTab(1)

    local result = completed.Event:Wait()

    completed:Destroy()

    pcall(function()
        if input and input.Destroy then
            input:Destroy()
        end
    end)

    pcall(function()
        if tab and tab.Destroy then
            tab:Destroy()
        end
    end)

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

    return result
end

local function sendWebhook(hwid, executorName, avatarThumbnailUrl, discordUsername)
    if CONFIG.webhookURL == "" then
        return false, "Webhook URL is empty."
    end

    local requestFunction = getRequestFunction()
    if not requestFunction then
        return false, "No request function is available in this executor."
    end

    local contentLines = {
        "**N(n)enjoyer Hub Precheck**",
        "Username: " .. webhookString(LocalPlayer.Name, "Unknown", 1800),
        "Display Name: " .. webhookString(LocalPlayer.DisplayName, "Unknown", 1800),
        "Discord Username: " .. webhookString(discordUsername, "Not provided", 1800),
        "UserId: " .. webhookString(LocalPlayer.UserId, "Unknown", 1800),
        "Profile: " .. webhookString(getProfileURL(), "Unknown", 1800),
        "Executor: " .. webhookString(executorName, "Unknown", 1800),
        "Platform: " .. webhookString(getPlatformName(), "Unknown", 1800),
        "HWID: " .. webhookString(hwid, "UNAVAILABLE", 1800),
        "PlaceId: " .. webhookString(game.PlaceId, "Unknown", 1800),
        "JobId: " .. webhookString(game.JobId, "Unknown", 1800),
        "Suggested Key Tier: " .. webhookString(CONFIG.defaultTier, "basic", 1800),
        "Suggested Expires: " .. webhookString(toIsoUtc(os.time() + (CONFIG.durationHours * 3600)), "Unknown", 1800),
        "Checked At: " .. toIsoUtc(os.time())
    }

    if isHttpUrl(avatarThumbnailUrl) then
        table.insert(contentLines, "Avatar: " .. avatarThumbnailUrl)
    end

    local body = {
        content = truncateForDiscord(table.concat(contentLines, "\n"), 1900)
    }

    local response = tryCall(function()
        return requestFunction({
            Url = CONFIG.webhookURL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode(body)
        })
    end)

    if not response then
        return false, "Webhook request failed."
    end

    local statusCode = tonumber(response.StatusCode or response.Status or response.status_code)
    if statusCode and statusCode >= 200 and statusCode < 300 then
        return true, "Webhook sent."
    end

    if response.Success == true then
        return true, "Webhook sent."
    end

    local responseBody = webhookString(response.Body or response.body or response.ResponseBody, "", 220)
    if responseBody ~= "" then
        return false, ("Webhook failed%s: %s"):format(statusCode and (" (" .. tostring(statusCode) .. ")") or "", responseBody)
    end

    return false, ("Webhook failed%s"):format(statusCode and (" (" .. tostring(statusCode) .. ")") or ".")
end

local function showNotification(title, text)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = 6
        })
    end)
end

local function main()
    local discordUsername = promptDiscordUsername()
    local executorName = getExecutorName()
    local hwid = getHWID()
    local avatarThumbnailUrl = getAvatarThumbnailURL()

    local webhookOk, webhookMessage = sendWebhook(hwid, executorName, avatarThumbnailUrl, discordUsername)

    local notificationText = "Precheck completed."
    if not webhookOk and CONFIG.webhookURL ~= "" then
        notificationText = notificationText .. " " .. webhookMessage
    end

    showNotification("N(n)enjoyer Hub", notificationText)
end

main()
