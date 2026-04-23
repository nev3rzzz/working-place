# N(n)enjoyer Hub GitHub Structure

This folder is the recommended layout for publishing your scripts to GitHub.

## Repository layout

```text
github_repo_ready/
  client/
    loader.lua
    precheck.lua
    games/
      README.md
      ultra_power.lua
    templates/
      game_script_template.lua
  backend/
    worker.js
    schema.sql
    README.md
    wrangler.toml.example
  examples/
    issue-ultra-power.json
    issue-remote-game.json
  .gitignore
```

## What each file is for

- `client/loader.lua`
  Main script players run after they receive a key. It checks the backend, validates the current `PlaceId`, and then loads the correct game script.

- `client/precheck.lua`
  Script players run first so you can collect `userId`, `HWID`, Discord username, and other data before manually whitelisting them.

- `client/games/`
  Publish future game-specific scripts here. Each file in this folder should contain only the logic for one game.

- `client/templates/game_script_template.lua`
  Starter template for a new game-specific script.

- `backend/`
  Cloudflare Worker backend for issuing, redeeming, validating, and revoking keys.

- `examples/`
  Ready JSON payload examples for issuing keys.

## Recommended publishing flow

1. Publish this repository to GitHub.
2. Deploy the backend from `backend/`.
3. Give players `client/precheck.lua` first.
4. After precheck, manually issue a key tied to that player's `userId` and `HWID`.
5. Give players `client/loader.lua` as the main script.
6. When you support a new game, add a new file in `client/games/` and add its raw GitHub URL to `GAME_LOADERS` in `client/loader.lua`.

## How to add a new game later

1. Copy `client/templates/game_script_template.lua`.
2. Save it as something like `client/games/blade_ball.lua`.
3. Publish the repo.
4. Take the raw GitHub URL for that file.
5. Add a new `PlaceId -> url` route inside `client/loader.lua`.
6. Issue keys with `allowedPlaceIds` that match that game.

## Current setup

- `Ultra Power`
  PlaceId: `8146731988`
  Published as `client/games/ultra_power.lua`

The loader is now universal. It authenticates with the backend first, then routes by `PlaceId` to the correct game-specific file.
