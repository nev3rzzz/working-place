local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

local WINDOW_TITLE = "N(n)enjoyer Hub"
local WINDOW_SUBTITLE = "Loader"

local GLOBAL_ENV = (getgenv and getgenv()) or _G
local CONFIG = {
    backendURL = tostring(GLOBAL_ENV.NNEnjoyerBackendURL or ""),
    redeemPath = tostring(GLOBAL_ENV.NNEnjoyerRedeemPath or "/redeem"),
    savedKeyFile = tostring(GLOBAL_ENV.NNEnjoyerSavedKeyFile or "NenjoyerHub/Auth/last_key.txt")
}

local GAME_LOADERS = {
    [8146731988] = {
        name = "Ultra Power",
        url = "https://raw.githubusercontent.com/nev3rzzz/working-place/main/nnenjoyer-hub/client/games/ultra_power.lua"
    }
}

local function tryCall(callback)
    local ok, value = pcall(callback)
    if ok then
        return value
    end

    return nil
end

local function trim(value)
    if typeof(value) ~= "string" then
        return ""
    end

    return value:match("^%s*(.-)%s*$") or ""
end

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = 6
        })
    end)
end

local function ensureFoldersForFile(filePath)
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

local function readTextFile(filePath)
    if not (isfile and readfile and filePath ~= "") then
        return nil
    end

    if not isfile(filePath) then
        return nil
    end

    local content = tryCall(function()
        return readfile(filePath)
    end)

    if typeof(content) == "string" then
        return content
    end

    return nil
end

local function writeTextFile(filePath, content)
    if not (writefile and filePath ~= "") then
        return
    end

    ensureFoldersForFile(filePath)
    pcall(writefile, filePath, content)
end

local function loadSavedKey()
    return trim(readTextFile(CONFIG.savedKeyFile) or "")
end

local function saveKey(key)
    local normalizedKey = trim(key)
    if normalizedKey ~= "" then
        writeTextFile(CONFIG.savedKeyFile, normalizedKey)
    end
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

local function requestJson(url, method, body)
    local requestFunction = getRequestFunction()
    if not requestFunction then
        return nil, "No request function is available in this executor."
    end

    local response = tryCall(function()
        return requestFunction({
            Url = url,
            Method = method or "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = body and HttpService:JSONEncode(body) or nil
        })
    end)

    if not response then
        return nil, "The backend request failed."
    end

    local statusCode = tonumber(response.StatusCode or response.Status or response.status_code)
    local responseBody = response.Body or response.body or response.ResponseBody or ""
    local decoded = tryCall(function()
        return HttpService:JSONDecode(responseBody)
    end)

    if statusCode and (statusCode < 200 or statusCode >= 300) then
        if typeof(decoded) == "table" and trim(tostring(decoded.error or decoded.message or "")) ~= "" then
            return nil, trim(tostring(decoded.error or decoded.message))
        end

        if trim(responseBody) ~= "" then
            return nil, trim(responseBody)
        end

        if statusCode == 404 then
            return nil, "Key not found."
        end

        if statusCode == 403 then
            return nil, "Access denied."
        end

        if statusCode == 401 then
            return nil, "Unauthorized."
        end

        if statusCode == 400 then
            return nil, "Invalid request."
        end

        return nil, "The backend returned an error."
    end

    if typeof(decoded) ~= "table" then
        return nil, "The backend returned invalid JSON."
    end

    return decoded, nil
end

local function normalizeFailureMessage(message)
    local normalized = trim(tostring(message or ""))
    local lower = string.lower(normalized)

    if lower == "key not found." then
        return "Verification required: key not found."
    end

    if lower == "device mismatch." or lower == "key is bound to another device." then
        return "Verification required: wrong HWID."
    end

    if lower == "user mismatch." or lower == "key is bound to another user." then
        return "Verification required: wrong user."
    end

    if lower == "access denied." then
        return "Verification required: wrong HWID or key not found."
    end

    if string.find(lower, "not allowed in placeid", 1, true) or
        string.find(lower, "not allowed in gameid", 1, true) or
        string.find(lower, "not allowed in the current placeid", 1, true) or
        string.find(lower, "not allowed in the current gameid", 1, true) then
        return "Unsupported game."
    end

    if normalized == "" then
        return "Access denied."
    end

    return normalized
end

local function getBackendUrl(path)
    local baseUrl = trim(CONFIG.backendURL)
    if baseUrl == "" then
        return nil
    end

    local normalizedPath = trim(path)
    if normalizedPath == "" then
        return baseUrl
    end

    if baseUrl:sub(-1) == "/" then
        baseUrl = baseUrl:sub(1, -2)
    end

    if normalizedPath:sub(1, 1) ~= "/" then
        normalizedPath = "/" .. normalizedPath
    end

    return baseUrl .. normalizedPath
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

local function redeemKey(key)
    local backendUrl = getBackendUrl(CONFIG.redeemPath)
    if not backendUrl then
        return nil, "NNEnjoyerBackendURL is not configured."
    end

    return requestJson(backendUrl, "POST", {
        key = trim(key),
        userId = tostring(LocalPlayer.UserId),
        deviceId = getHWID(),
        placeId = tostring(game.PlaceId),
        gameId = tostring(game.GameId)
    })
end

local function promptForKey()
    local Fluent = loadFluent()
    local completed = Instance.new("BindableEvent")
    local currentValue = loadSavedKey()

    local window = Fluent:CreateWindow({
        Title = WINDOW_TITLE,
        SubTitle = WINDOW_SUBTITLE,
        TabWidth = 160,
        Size = UDim2.fromOffset(520, 320),
        Acrylic = false,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.RightAlt
    })

    local tab = window:AddTab({
        Title = "Access",
        Icon = "lock"
    })

    local statusParagraph = tab:AddParagraph({
        Title = "Status",
        Content = "Enter your access key to continue."
    })

    local input = tab:AddInput("AccessKeyInput", {
        Title = "Access Key",
        Default = currentValue,
        Placeholder = "Enter access key",
        Numeric = false,
        Finished = false,
        Callback = function(value)
            currentValue = value
        end
    })

    local function setStatus(text)
        pcall(function()
            statusParagraph:SetDesc(text)
        end)
        pcall(function()
            if statusParagraph.SetContent then
                statusParagraph:SetContent(text)
            end
        end)
    end

    local function submit()
        local key = trim(input.Value or currentValue)
        if key == "" then
            setStatus("Enter your access key.")
            return
        end

        setStatus("Checking key...")

        task.spawn(function()
            local payload, errorMessage = redeemKey(key)
            if payload then
                saveKey(key)
                completed:Fire({
                    key = key,
                    payload = payload
                })
                return
            end

            setStatus(normalizeFailureMessage(errorMessage))
        end)
    end

    tab:AddButton({
        Title = "Unlock",
        Description = "Redeem and validate this key",
        Callback = submit
    })

    window:SelectTab(1)

    local result = completed.Event:Wait()

    completed:Destroy()

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

local function buildContext(authResult)
    return {
        Auth = authResult.payload,
        Key = authResult.key,
        PlaceId = game.PlaceId,
        GameId = game.GameId,
        Players = Players,
        LocalPlayer = LocalPlayer,
        HttpService = HttpService,
        UserInputService = UserInputService,
        WindowTitle = WINDOW_TITLE,
        WindowSubtitle = WINDOW_SUBTITLE
    }
end

local function executeRoute(route, context)
    local source = downloadText(route.url)
    if typeof(source) ~= "string" or source == "" then
        notify(WINDOW_TITLE, "Failed to download the game script.")
        return
    end

    local chunk = tryCall(function()
        return loadstring(source, "@" .. route.url)
    end)

    if type(chunk) ~= "function" then
        notify(WINDOW_TITLE, "Failed to compile the game script.")
        return
    end

    local ok, exported = pcall(chunk)
    if not ok then
        notify(WINDOW_TITLE, "Game script runtime error.")
        warn(exported)
        return
    end

    if type(exported) == "function" then
        exported(context)
        return
    end

    if type(exported) == "table" and type(exported.run) == "function" then
        exported.run(context)
        return
    end

    notify(WINDOW_TITLE, "Game script must return a function or Module.run.")
end

local route = GAME_LOADERS[tonumber(game.PlaceId)]
if not route then
    notify(WINDOW_TITLE, "Unsupported game.")
    return
end

local authResult = promptForKey()
if not authResult or not authResult.payload then
    notify(WINDOW_TITLE, "Verification required.")
    return
end

executeRoute(route, buildContext(authResult))
