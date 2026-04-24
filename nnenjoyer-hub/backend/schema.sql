CREATE TABLE IF NOT EXISTS license_keys (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    license_key TEXT NOT NULL UNIQUE,
    tier TEXT NOT NULL DEFAULT 'basic',
    status TEXT NOT NULL DEFAULT 'active',
    starts_at TEXT,
    expires_at TEXT,
    duration_seconds INTEGER,
    note TEXT,
    script_url TEXT,
    allowed_place_ids TEXT,
    allowed_game_ids TEXT,
    bound_user_id TEXT,
    bound_device_id TEXT,
    redeemed_at TEXT,
    last_validated_at TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_license_key ON license_keys (license_key);
CREATE INDEX IF NOT EXISTS idx_status ON license_keys (status);
CREATE INDEX IF NOT EXISTS idx_bound_user_id ON license_keys (bound_user_id);

CREATE TABLE IF NOT EXISTS live_sessions (
    session_id TEXT PRIMARY KEY,
    license_key TEXT NOT NULL,
    user_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    place_id TEXT,
    game_id TEXT,
    game_name TEXT,
    job_id TEXT,
    executor TEXT,
    platform TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    pending_command TEXT,
    command_nonce TEXT,
    command_payload TEXT,
    command_updated_at TEXT,
    started_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    last_seen_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    ended_at TEXT,
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_live_sessions_license_key ON live_sessions (license_key);
CREATE INDEX IF NOT EXISTS idx_live_sessions_user_id ON live_sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_live_sessions_status ON live_sessions (status);
CREATE INDEX IF NOT EXISTS idx_live_sessions_last_seen_at ON live_sessions (last_seen_at);

CREATE TABLE IF NOT EXISTS system_settings (
    setting_key TEXT PRIMARY KEY,
    setting_value TEXT,
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
