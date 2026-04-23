# Game Scripts

Put future game-specific scripts in this folder.

Suggested naming:

- `ultra_power.lua`
- `blade_ball.lua`
- `pet_simulator_99.lua`

Each script should return either:

```lua
return function(context)
    -- your game logic
end
```

or:

```lua
local Module = {}

function Module.run(context)
    -- your game logic
end

return Module
```

After publishing a file here, add its raw GitHub URL to `GAME_LOADERS` in `client/loader.lua`.

Example:

```lua
[1234567890] = {
    name = "Another Game",
    url = "https://raw.githubusercontent.com/USERNAME/REPO/main/nnenjoyer-hub/client/games/another_game.lua"
}
```
