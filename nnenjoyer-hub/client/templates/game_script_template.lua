return function(context)
    local Players = context.Players
    local LocalPlayer = context.LocalPlayer
    local PlaceId = context.PlaceId
    local GameId = context.GameId
    local Auth = context.Auth

    local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

    local window = Fluent:CreateWindow({
        Title = context.WindowTitle,
        SubTitle = "Game Script Template",
        TabWidth = 160,
        Size = UDim2.fromOffset(560, 520),
        Acrylic = false,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.RightAlt
    })

    local mainTab = window:AddTab({
        Title = "Main",
        Icon = "home"
    })

    mainTab:AddParagraph({
        Title = "Loaded",
        Content = "Player: " .. tostring(LocalPlayer and LocalPlayer.Name or "Unknown") ..
            "\nPlaceId: " .. tostring(PlaceId) ..
            "\nGameId: " .. tostring(GameId) ..
            "\nTier: " .. tostring(Auth and Auth.tier or "unknown")
    })

    mainTab:AddButton({
        Title = "Test Button",
        Description = "Replace this with game-specific logic.",
        Callback = function()
            Fluent:Notify({
                Title = "Template",
                Content = "Remote script is running.",
                Duration = 4
            })
        end
    })
end
