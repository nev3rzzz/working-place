# Lightweight License Backend

Minimal backend template for a Roblox-oriented key system.

Stack:
- Cloudflare Workers
- Cloudflare D1 (SQLite)

What it supports:
- `POST /issue` create a key
- `POST /redeem` bind a key to a Roblox account + device on first successful use
- `POST /validate` validate an existing binding
- `POST /revoke` revoke a key
- `GET /health` health check

It now also supports:
- access windows with `startsAt` / `expiresAt`
- time-limited access starting from the first redeem via `durationSeconds`
- per-key `PlaceId` restrictions
- per-key `GameId` restrictions
- optional `scriptUrl` metadata for client-side dispatchers

Recommended loader pattern:
- backend decides whether the key is valid for the current player/device/game
- the client loader keeps its own local `PlaceId -> loadstring URL` table
- if the current `PlaceId` is allowed and present in the local table, the loader runs that game-specific script
- in that setup, `scriptUrl` is optional and can be omitted entirely

## Files

- [worker.js](./worker.js) Worker API
- [schema.sql](./schema.sql) D1 schema
- [wrangler.toml.example](./wrangler.toml.example) Wrangler config example

## Setup

1. Create a D1 database.
2. Apply [schema.sql](./schema.sql).
3. Copy [wrangler.toml.example](./wrangler.toml.example) to `wrangler.toml`.
4. Fill in:
   - your worker name
   - your D1 database id
5. Add the admin secret:

```bash
wrangler secret put ADMIN_TOKEN
```

6. Deploy:

```bash
wrangler deploy
```

## Data model

Each key can be:
- `active`
- `revoked`

Each key may also define:
- `starts_at`
- `expires_at`
- `duration_seconds`
- `script_url`
- `allowed_place_ids`
- `allowed_game_ids`

Binding flow:
- first successful `redeem` binds the key to `user_id`
- first successful `redeem` binds the key to `device_id`
- if `durationSeconds` is set and `expiresAt` is not set, `expires_at` is generated from the first redeem timestamp
- later `redeem` or `validate` calls must match the same `userId` and `deviceId`

## Important note about game checks

The backend can enforce `placeId` / `gameId` against values sent by the client.

That is useful for policy and routing, but it is still client-reported data. Without a trusted Roblox-side proof, it should be treated as a practical restriction, not a cryptographic guarantee.

## Issue a key

`POST /issue`

Headers:

```text
Authorization: Bearer YOUR_ADMIN_TOKEN
Content-Type: application/json
```

Body:

```json
{
  "tier": "basic",
  "durationSeconds": 90,
  "allowedPlaceIds": [1234567890],
  "allowedGameIds": ["987654321012345"],
  "note": "90 second first-redeem trial"
}
```

`key` is optional now. If you omit it, the worker generates one.

If you want a fixed window instead of first-redeem duration:

```json
{
  "key": "USER1-BASIC-001",
  "tier": "basic",
  "startsAt": "2026-04-23T15:00:00Z",
  "expiresAt": "2026-04-23T15:30:00Z",
  "allowedPlaceIds": [1234567890]
}
```

## Redeem a key

`POST /redeem`

```json
{
  "key": "USER1-BASIC-001",
  "userId": "3162632551",
  "deviceId": "executor-hwid-123",
  "placeId": "1234567890",
  "gameId": "987654321012345"
}
```

On first success:
- the key is bound
- `redeemedAt` is written
- `expiresAt` is generated if `durationSeconds` exists and no fixed `expiresAt` was set

## Validate a key

`POST /validate`

```json
{
  "key": "USER1-BASIC-001",
  "userId": "3162632551",
  "deviceId": "executor-hwid-123",
  "placeId": "1234567890",
  "gameId": "987654321012345"
}
```

## Revoke a key

`POST /revoke`

Headers:

```text
Authorization: Bearer YOUR_ADMIN_TOKEN
Content-Type: application/json
```

Body:

```json
{
  "key": "USER1-BASIC-001"
}
```

## Response shape

Success:

```json
{
  "ok": true,
  "key": "USER1-BASIC-001",
  "tier": "basic",
  "startsAt": null,
  "expiresAt": "2026-04-23T15:31:30.000Z",
  "status": "active",
  "redeemedAt": "2026-04-23T15:30:00.000Z",
  "durationSeconds": 90,
  "scriptUrl": null,
  "allowedPlaceIds": ["1234567890"],
  "allowedGameIds": ["987654321012345"]
}
```

Failure:

```json
{
  "ok": false,
  "error": "This key is bound to another device."
}
```
