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
