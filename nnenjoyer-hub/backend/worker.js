function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
    },
  });
}

function normalizeText(value) {
  if (value === null || value === undefined) {
    return "";
  }

  return String(value).trim();
}

function normalizeOptionalText(value) {
  const text = normalizeText(value);
  return text || null;
}

function toIso(value) {
  const text = normalizeText(value);
  if (!text) {
    return null;
  }

  const date = new Date(text);
  if (Number.isNaN(date.getTime())) {
    return null;
  }

  return date.toISOString();
}

function nowIso() {
  return new Date().toISOString();
}

function toPositiveInteger(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  const number = Number(value);
  if (!Number.isInteger(number) || number <= 0) {
    return null;
  }

  return number;
}

function normalizeIdList(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  const source = Array.isArray(value) ? value : [value];
  const unique = new Set();

  for (const entry of source) {
    const normalized = normalizeText(entry);
    if (normalized) {
      unique.add(normalized);
    }
  }

  const result = Array.from(unique);
  return result.length > 0 ? result : null;
}

function parseStoredIdList(value) {
  const text = normalizeText(value);
  if (!text) {
    return [];
  }

  try {
    const decoded = JSON.parse(text);
    return normalizeIdList(decoded) || [];
  } catch {
    return normalizeIdList(text) || [];
  }
}

function serializeIdList(list) {
  const normalized = normalizeIdList(list);
  return normalized ? JSON.stringify(normalized) : null;
}

function normalizeUrl(value) {
  const text = normalizeText(value);
  if (!text) {
    return null;
  }

  try {
    return new URL(text).toString();
  } catch {
    return null;
  }
}

function authFailed() {
  return json({ ok: false, error: "Unauthorized." }, 401);
}

function isAdmin(request, env) {
  const authHeader = normalizeText(request.headers.get("authorization"));
  if (!authHeader.startsWith("Bearer ")) {
    return false;
  }

  const token = authHeader.slice("Bearer ".length).trim();
  return token && env.ADMIN_TOKEN && token === env.ADMIN_TOKEN;
}

async function readJson(request) {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

function validateWindow(startsAt, expiresAt) {
  if (startsAt && !toIso(startsAt)) {
    return "startsAt must be a valid ISO date.";
  }

  if (expiresAt && !toIso(expiresAt)) {
    return "expiresAt must be a valid ISO date.";
  }

  if (startsAt && expiresAt) {
    const start = new Date(startsAt).getTime();
    const end = new Date(expiresAt).getTime();
    if (end <= start) {
      return "expiresAt must be later than startsAt.";
    }
  }

  return null;
}

function generateLicenseKey() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const makeChunk = (length) => {
    const bytes = crypto.getRandomValues(new Uint8Array(length));
    let result = "";

    for (let index = 0; index < length; index += 1) {
      result += alphabet[bytes[index] % alphabet.length];
    }

    return result;
  };

  return [makeChunk(4), makeChunk(4), makeChunk(4), makeChunk(4)].join("-");
}

async function findLicense(db, key) {
  return db
    .prepare("SELECT * FROM license_keys WHERE license_key = ?1 LIMIT 1")
    .bind(key)
    .first();
}

function evaluateTimeWindow(row) {
  const now = Date.now();

  if (row.starts_at) {
    const startsAt = new Date(row.starts_at).getTime();
    if (!Number.isNaN(startsAt) && now < startsAt) {
      return { ok: false, error: "Key is not active yet." };
    }
  }

  if (row.expires_at) {
    const expiresAt = new Date(row.expires_at).getTime();
    if (!Number.isNaN(expiresAt) && now >= expiresAt) {
      return { ok: false, error: "Key has expired." };
    }
  }

  return { ok: true };
}

function evaluateGameAccess(row, placeId, gameId) {
  const allowedPlaceIds = parseStoredIdList(row.allowed_place_ids);
  const allowedGameIds = parseStoredIdList(row.allowed_game_ids);
  const normalizedPlaceId = normalizeText(placeId);
  const normalizedGameId = normalizeText(gameId);

  if (allowedPlaceIds.length > 0) {
    if (!normalizedPlaceId) {
      return { ok: false, error: "placeId is required for this key." };
    }

    if (!allowedPlaceIds.includes(normalizedPlaceId)) {
      return { ok: false, error: `This key is not allowed in PlaceId ${normalizedPlaceId}.` };
    }
  }

  if (allowedGameIds.length > 0) {
    if (!normalizedGameId) {
      return { ok: false, error: "gameId is required for this key." };
    }

    if (!allowedGameIds.includes(normalizedGameId)) {
      return { ok: false, error: `This key is not allowed in GameId ${normalizedGameId}.` };
    }
  }

  return { ok: true };
}

function buildLicensePayload(row) {
  return {
    ok: true,
    key: row.license_key,
    tier: row.tier,
    startsAt: row.starts_at,
    expiresAt: row.expires_at,
    status: row.status,
    redeemedAt: row.redeemed_at,
    durationSeconds: row.duration_seconds ?? null,
    scriptUrl: row.script_url || null,
    allowedPlaceIds: parseStoredIdList(row.allowed_place_ids),
    allowedGameIds: parseStoredIdList(row.allowed_game_ids),
  };
}

async function issueKey(request, env) {
  if (!isAdmin(request, env)) {
    return authFailed();
  }

  const body = await readJson(request);
  if (!body) {
    return json({ ok: false, error: "Invalid JSON body." }, 400);
  }

  const key = normalizeText(body.key) || generateLicenseKey();
  const tier = normalizeText(body.tier) || "basic";
  const startsAt = toIso(body.startsAt);
  const expiresAt = toIso(body.expiresAt);
  const durationSeconds = toPositiveInteger(body.durationSeconds);
  const note = normalizeText(body.note);
  const boundUserId = normalizeOptionalText(body.boundUserId ?? body.userId);
  const boundDeviceId = normalizeOptionalText(body.boundDeviceId ?? body.deviceId);
  const scriptUrl = body.scriptUrl === null || body.scriptUrl === undefined || body.scriptUrl === ""
    ? null
    : normalizeUrl(body.scriptUrl);
  const allowedPlaceIds = normalizeIdList(
    body.allowedPlaceIds ?? body.placeIds ?? body.placeId
  );
  const allowedGameIds = normalizeIdList(
    body.allowedGameIds ?? body.gameIds ?? body.gameId
  );

  const windowError = validateWindow(startsAt, expiresAt);
  if (windowError) {
    return json({ ok: false, error: windowError }, 400);
  }

  if (body.durationSeconds !== undefined && durationSeconds === null) {
    return json({ ok: false, error: "durationSeconds must be a positive integer." }, 400);
  }

  if (body.scriptUrl !== undefined && body.scriptUrl !== null && body.scriptUrl !== "" && !scriptUrl) {
    return json({ ok: false, error: "scriptUrl must be a valid absolute URL." }, 400);
  }

  if ((boundUserId && !boundDeviceId) || (!boundUserId && boundDeviceId)) {
    return json({ ok: false, error: "boundUserId and boundDeviceId must be provided together." }, 400);
  }

  const existing = await findLicense(env.DB, key);
  if (existing) {
    return json({ ok: false, error: "Key already exists." }, 409);
  }

  const createdAt = nowIso();

  await env.DB.prepare(
    `INSERT INTO license_keys
      (
        license_key,
        tier,
        status,
        starts_at,
        expires_at,
        duration_seconds,
        note,
        script_url,
        allowed_place_ids,
        allowed_game_ids,
        bound_user_id,
        bound_device_id,
        created_at,
        updated_at
      )
     VALUES (?1, ?2, 'active', ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?12)`
  )
    .bind(
      key,
      tier,
      startsAt,
      expiresAt,
      durationSeconds,
      note || null,
      scriptUrl,
      serializeIdList(allowedPlaceIds),
      serializeIdList(allowedGameIds),
      boundUserId,
      boundDeviceId,
      createdAt
    )
    .run();

  return json({
    ok: true,
    key,
    tier,
    startsAt,
    expiresAt,
    status: "active",
    durationSeconds,
    scriptUrl,
    allowedPlaceIds: allowedPlaceIds || [],
    allowedGameIds: allowedGameIds || [],
    boundUserId,
    boundDeviceId,
  });
}

async function redeemKey(request, env) {
  const body = await readJson(request);
  if (!body) {
    return json({ ok: false, error: "Invalid JSON body." }, 400);
  }

  const key = normalizeText(body.key);
  const userId = normalizeText(body.userId);
  const deviceId = normalizeText(body.deviceId);
  const placeId = normalizeText(body.placeId);
  const gameId = normalizeText(body.gameId);

  if (!key || !userId || !deviceId) {
    return json({ ok: false, error: "key, userId and deviceId are required." }, 400);
  }

  const row = await findLicense(env.DB, key);
  if (!row) {
    return json({ ok: false, error: "Key not found." }, 404);
  }

  if (row.status !== "active") {
    return json({ ok: false, error: `Key is ${row.status}.` }, 403);
  }

  const windowResult = evaluateTimeWindow(row);
  if (!windowResult.ok) {
    return json({ ok: false, error: windowResult.error }, 403);
  }

  const gameResult = evaluateGameAccess(row, placeId, gameId);
  if (!gameResult.ok) {
    return json({ ok: false, error: gameResult.error }, 403);
  }

  const boundUserId = normalizeText(row.bound_user_id);
  const boundDeviceId = normalizeText(row.bound_device_id);

  if (boundUserId && boundUserId !== userId) {
    return json({ ok: false, error: "Key is bound to another user." }, 403);
  }

  if (boundDeviceId && boundDeviceId !== deviceId) {
    return json({ ok: false, error: "Key is bound to another device." }, 403);
  }

  const now = nowIso();
  const finalUserId = boundUserId || userId;
  const finalDeviceId = boundDeviceId || deviceId;
  let redeemedAt = normalizeOptionalText(row.redeemed_at);
  let expiresAt = normalizeOptionalText(row.expires_at);

  if (!redeemedAt) {
    redeemedAt = now;
  }

  if (!expiresAt && row.duration_seconds) {
    expiresAt = new Date(Date.now() + (row.duration_seconds * 1000)).toISOString();
  }

  await env.DB.prepare(
    `UPDATE license_keys
     SET bound_user_id = ?2,
         bound_device_id = ?3,
         redeemed_at = ?4,
         expires_at = ?5,
         last_validated_at = ?6,
         updated_at = ?6
      WHERE license_key = ?1`
  )
    .bind(
      key,
      finalUserId,
      finalDeviceId,
      redeemedAt,
      expiresAt,
      now
    )
    .run();

  const updatedRow = {
    ...row,
    bound_user_id: finalUserId,
    bound_device_id: finalDeviceId,
    redeemed_at: redeemedAt,
    expires_at: expiresAt,
    last_validated_at: now,
  };

  const refreshedWindow = evaluateTimeWindow(updatedRow);
  if (!refreshedWindow.ok) {
    return json({ ok: false, error: refreshedWindow.error }, 403);
  }

  return json(buildLicensePayload(updatedRow));
}

async function validateKey(request, env) {
  const body = await readJson(request);
  if (!body) {
    return json({ ok: false, error: "Invalid JSON body." }, 400);
  }

  const key = normalizeText(body.key);
  const userId = normalizeText(body.userId);
  const deviceId = normalizeText(body.deviceId);
  const placeId = normalizeText(body.placeId);
  const gameId = normalizeText(body.gameId);

  if (!key || !userId || !deviceId) {
    return json({ ok: false, error: "key, userId and deviceId are required." }, 400);
  }

  const row = await findLicense(env.DB, key);
  if (!row) {
    return json({ ok: false, error: "Key not found." }, 404);
  }

  if (row.status !== "active") {
    return json({ ok: false, error: `Key is ${row.status}.` }, 403);
  }

  const windowResult = evaluateTimeWindow(row);
  if (!windowResult.ok) {
    return json({ ok: false, error: windowResult.error }, 403);
  }

  const gameResult = evaluateGameAccess(row, placeId, gameId);
  if (!gameResult.ok) {
    return json({ ok: false, error: gameResult.error }, 403);
  }

  if (normalizeText(row.bound_user_id) !== userId) {
    return json({ ok: false, error: "User mismatch." }, 403);
  }

  if (normalizeText(row.bound_device_id) !== deviceId) {
    return json({ ok: false, error: "Device mismatch." }, 403);
  }

  const now = nowIso();

  await env.DB.prepare(
    `UPDATE license_keys
     SET last_validated_at = ?2,
         updated_at = ?2
     WHERE license_key = ?1`
  )
    .bind(key, now)
    .run();

  return json(buildLicensePayload({
    ...row,
    last_validated_at: now,
  }));
}

async function revokeKey(request, env) {
  if (!isAdmin(request, env)) {
    return authFailed();
  }

  const body = await readJson(request);
  if (!body) {
    return json({ ok: false, error: "Invalid JSON body." }, 400);
  }

  const key = normalizeText(body.key);
  if (!key) {
    return json({ ok: false, error: "key is required." }, 400);
  }

  const row = await findLicense(env.DB, key);
  if (!row) {
    return json({ ok: false, error: "Key not found." }, 404);
  }

  await env.DB.prepare(
    `UPDATE license_keys
     SET status = 'revoked',
         updated_at = ?2
     WHERE license_key = ?1`
  )
    .bind(key, nowIso())
    .run();

  return json({ ok: true, key, status: "revoked" });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true, service: "license-backend" });
    }

    if (request.method === "POST" && url.pathname === "/issue") {
      return issueKey(request, env);
    }

    if (request.method === "POST" && url.pathname === "/redeem") {
      return redeemKey(request, env);
    }

    if (request.method === "POST" && url.pathname === "/validate") {
      return validateKey(request, env);
    }

    if (request.method === "POST" && url.pathname === "/revoke") {
      return revokeKey(request, env);
    }

    return json({ ok: false, error: "Not found." }, 404);
  },
};
