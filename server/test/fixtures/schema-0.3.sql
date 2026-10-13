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

-- Additive 0.3 schema: preserves existing users and sessions.
CREATE TABLE IF NOT EXISTS tomi_image_uploads (
 id TEXT PRIMARY KEY,
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 object_key TEXT NOT NULL UNIQUE, content_type TEXT NOT NULL,
 byte_length INTEGER NOT NULL, content_md5 TEXT NOT NULL,
 state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','attached','deleting')),
 width INTEGER, height INTEGER, created_at TEXT NOT NULL, expires_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS tomi_upload_expiry_idx ON tomi_image_uploads(state,expires_at);
CREATE TABLE IF NOT EXISTS tomi_posts (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 request_id TEXT NOT NULL, body TEXT NOT NULL,
 image_upload_id TEXT UNIQUE REFERENCES tomi_image_uploads(id), created_at TEXT NOT NULL,
 UNIQUE(user_id,request_id)
);
CREATE INDEX IF NOT EXISTS tomi_posts_feed_idx ON tomi_posts(created_at,id);
CREATE INDEX IF NOT EXISTS tomi_posts_user_idx ON tomi_posts(user_id,created_at,id);
CREATE TABLE IF NOT EXISTS tomi_post_likes (
 post_id TEXT NOT NULL REFERENCES tomi_posts(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE, created_at TEXT NOT NULL,
 PRIMARY KEY(post_id,user_id)
);
CREATE TABLE IF NOT EXISTS tomi_comments (
 id TEXT PRIMARY KEY, post_id TEXT NOT NULL REFERENCES tomi_posts(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 request_id TEXT NOT NULL, body TEXT NOT NULL, created_at TEXT NOT NULL,
 UNIQUE(user_id,request_id)
);
CREATE INDEX IF NOT EXISTS tomi_comments_post_idx ON tomi_comments(post_id,created_at,id);
