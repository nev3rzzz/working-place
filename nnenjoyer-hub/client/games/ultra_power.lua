return function(context)
    local source = game:HttpGet("https://raw.githubusercontent.com/nev3rzzz/working-place/50509ecd59bd417dca1e8e68187cddc9767eaa64/nnenjoyer-hub/client/games/ultra_power.lua")
    source = source:gsub("\r\n", "\n")
    source = source:gsub("[ \t]*MinimizeKey = Enum%.KeyCode%.Unknown\n", "")

    local chunk = assert(loadstring(source, "@ultra_power_hotfix"))
    local exported = chunk()

    if type(exported) == "function" then
        return exported(context)
    end

    if type(exported) == "table" then
        local runner = exported.run or exported.Start
        if type(runner) == "function" then
            return runner(context)
        end
    end

    error("Ultra Power hotfix failed to return a runnable script.")
end
