local StarterGui = game:GetService("StarterGui")

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = 8
        })
    end)
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
        local ok, value = pcall(provider)
        if ok and typeof(value) == "string" and value ~= "" then
            return value
        end
    end

    return "UNAVAILABLE"
end

local hwid = getHWID()

pcall(function()
    if setclipboard then
        setclipboard(hwid)
    end
end)

print("Current HWID:", hwid)
notify("HWID Checker", "HWID copied to clipboard.")

return hwid
