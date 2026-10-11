CREATE TABLE IF NOT EXISTS tomi_users (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  bio TEXT NOT NULL DEFAULT '',
  avatar_preset TEXT NOT NULL DEFAULT 'initials',
  password_hash TEXT NOT NULL,
  recovery_hash TEXT NOT NULL,
  auth_version INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tomi_sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
  auth_version INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS tomi_sessions_user_idx ON tomi_sessions(user_id);
CREATE INDEX IF NOT EXISTS tomi_sessions_expiry_idx ON tomi_sessions(expires_at);

CREATE TABLE IF NOT EXISTS tomi_follows (
  follower_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
  following_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  PRIMARY KEY (follower_id, following_id),
  CHECK (follower_id <> following_id)
);
CREATE INDEX IF NOT EXISTS tomi_follows_target_idx ON tomi_follows(following_id);

CREATE TABLE IF NOT EXISTS tomi_rate_limits (
  bucket_key TEXT PRIMARY KEY,
  window_started BIGINT NOT NULL,
  hits INTEGER NOT NULL
);
