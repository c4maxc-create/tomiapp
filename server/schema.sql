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

-- Additive 0.4 private chat schema.
CREATE TABLE IF NOT EXISTS tomi_chat_threads (
 id TEXT PRIMARY KEY,low_user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 high_user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 next_seq BIGINT NOT NULL DEFAULT 0,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,
 UNIQUE(low_user_id,high_user_id),CHECK(low_user_id<high_user_id)
);
CREATE TABLE IF NOT EXISTS tomi_chat_members (
 thread_id TEXT NOT NULL REFERENCES tomi_chat_threads(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 last_read_seq BIGINT NOT NULL DEFAULT 0,visible INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(thread_id,user_id)
);
CREATE TABLE IF NOT EXISTS tomi_chat_messages (
 id TEXT PRIMARY KEY,thread_id TEXT NOT NULL REFERENCES tomi_chat_threads(id) ON DELETE CASCADE,
 sender_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,sequence BIGINT NOT NULL,
 request_id TEXT NOT NULL,payload_hash TEXT NOT NULL,body TEXT NOT NULL,
 image_upload_id TEXT UNIQUE REFERENCES tomi_image_uploads(id),created_at TEXT NOT NULL,deleted_at TEXT,
 UNIQUE(thread_id,sequence),UNIQUE(sender_id,request_id)
);
CREATE INDEX IF NOT EXISTS tomi_chat_unread_idx ON tomi_chat_messages(thread_id,sender_id,sequence);
CREATE INDEX IF NOT EXISTS tomi_chat_list_idx ON tomi_chat_threads(updated_at,id);
CREATE TABLE IF NOT EXISTS tomi_user_blocks (
 blocker_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 blocked_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,created_at TEXT NOT NULL,
 PRIMARY KEY(blocker_id,blocked_id),CHECK(blocker_id<>blocked_id)
);

-- Additive 0.5 tables: preserve the complete 0.4 schema.
CREATE TABLE IF NOT EXISTS tomi_audio_uploads (
 id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 thread_id TEXT NOT NULL REFERENCES tomi_chat_threads(id) ON DELETE CASCADE,
 object_key TEXT NOT NULL UNIQUE,content_type TEXT NOT NULL,byte_length INTEGER NOT NULL,
 content_md5 TEXT NOT NULL,duration_ms INTEGER NOT NULL,
 state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','attached','deleting')),
 created_at TEXT NOT NULL,expires_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS tomi_audio_expiry_idx ON tomi_audio_uploads(state,expires_at);
CREATE TABLE IF NOT EXISTS tomi_chat_audio (
 message_id TEXT PRIMARY KEY REFERENCES tomi_chat_messages(id) ON DELETE CASCADE,
 upload_id TEXT NOT NULL UNIQUE REFERENCES tomi_audio_uploads(id)
);
CREATE TABLE IF NOT EXISTS tomi_user_avatars (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,
 upload_id TEXT NOT NULL UNIQUE REFERENCES tomi_image_uploads(id)
);
CREATE TABLE IF NOT EXISTS tomi_avatar_requests (
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,request_id TEXT NOT NULL,
 upload_id TEXT,created_at TEXT NOT NULL,PRIMARY KEY(user_id,request_id)
);
CREATE TABLE IF NOT EXISTS tomi_push_settings (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0,1))
);
CREATE TABLE IF NOT EXISTS tomi_push_devices (
 token_hash TEXT PRIMARY KEY,token TEXT NOT NULL,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 session_hash TEXT NOT NULL REFERENCES tomi_sessions(token_hash) ON DELETE CASCADE,
 platform TEXT NOT NULL CHECK(platform IN ('android','ios')),updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS tomi_push_user_idx ON tomi_push_devices(user_id);
CREATE TABLE IF NOT EXISTS tomi_push_outbox (
 message_id TEXT PRIMARY KEY REFERENCES tomi_chat_messages(id) ON DELETE CASCADE,
 recipient_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,thread_id TEXT NOT NULL,
 state TEXT NOT NULL DEFAULT 'pending',attempts INTEGER NOT NULL DEFAULT 0,next_at TEXT NOT NULL,
 lease_until TEXT NOT NULL DEFAULT '',created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS tomi_push_pending_idx ON tomi_push_outbox(state,next_at,lease_until);
CREATE TABLE IF NOT EXISTS tomi_push_receipts (
 message_id TEXT NOT NULL REFERENCES tomi_push_outbox(message_id) ON DELETE CASCADE,
 token_hash TEXT NOT NULL,PRIMARY KEY(message_id,token_hash)
);

-- Additive 0.6: call metadata persists; SDP/ICE is removed when a call ends.
CREATE TABLE IF NOT EXISTS tomi_calls (
 id TEXT PRIMARY KEY,thread_id TEXT NOT NULL REFERENCES tomi_chat_threads(id) ON DELETE CASCADE,
 caller_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 callee_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 caller_session TEXT NOT NULL,callee_session TEXT,
 request_id TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN ('audio','video')),
 state TEXT NOT NULL CHECK(state IN ('ringing','connecting','connected','ended')),reason TEXT,
 created_at TEXT NOT NULL,updated_at TEXT NOT NULL,ring_deadline TEXT NOT NULL,
 connect_deadline TEXT,accepted_at TEXT,connected_at TEXT,ended_at TEXT,
 caller_seen TEXT NOT NULL,callee_seen TEXT,
 caller_connected INTEGER NOT NULL DEFAULT 0,callee_connected INTEGER NOT NULL DEFAULT 0,
 next_seq BIGINT NOT NULL DEFAULT 0,UNIQUE(caller_id,request_id),CHECK(caller_id<>callee_id)
);
CREATE INDEX IF NOT EXISTS tomi_calls_caller_idx ON tomi_calls(caller_id,created_at,id);
CREATE INDEX IF NOT EXISTS tomi_calls_callee_idx ON tomi_calls(callee_id,created_at,id);
CREATE INDEX IF NOT EXISTS tomi_calls_active_idx ON tomi_calls(state,caller_seen);
CREATE TABLE IF NOT EXISTS tomi_active_calls (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,
 call_id TEXT NOT NULL REFERENCES tomi_calls(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS tomi_active_call_idx ON tomi_active_calls(call_id);
CREATE TABLE IF NOT EXISTS tomi_call_signals (
 call_id TEXT NOT NULL REFERENCES tomi_calls(id) ON DELETE CASCADE,sequence BIGINT NOT NULL,
 sender_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 request_id TEXT NOT NULL,signal_type TEXT NOT NULL,payload TEXT NOT NULL,payload_hash TEXT NOT NULL,
 created_at TEXT NOT NULL,PRIMARY KEY(call_id,sequence),UNIQUE(call_id,sender_id,request_id)
);
CREATE TABLE IF NOT EXISTS tomi_call_push_outbox (
 call_id TEXT PRIMARY KEY REFERENCES tomi_calls(id) ON DELETE CASCADE,
 recipient_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,thread_id TEXT NOT NULL,
 state TEXT NOT NULL DEFAULT 'pending',attempts INTEGER NOT NULL DEFAULT 0,next_at TEXT NOT NULL,
 lease_until TEXT NOT NULL DEFAULT '',created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS tomi_call_push_pending_idx ON tomi_call_push_outbox(state,next_at,lease_until);
CREATE TABLE IF NOT EXISTS tomi_call_push_receipts (
 call_id TEXT NOT NULL REFERENCES tomi_call_push_outbox(call_id) ON DELETE CASCADE,
 token_hash TEXT NOT NULL,PRIMARY KEY(call_id,token_hash)
);

-- Additive 0.6.1: consent and independent SDP rounds for media changes.
CREATE TABLE IF NOT EXISTS tomi_call_media_changes (
 call_id TEXT NOT NULL REFERENCES tomi_calls(id) ON DELETE CASCADE,
 request_id TEXT NOT NULL,requester_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 previous_kind TEXT NOT NULL CHECK(previous_kind IN ('audio','video')),
 target_kind TEXT NOT NULL CHECK(target_kind IN ('audio','video')),
 revision INTEGER NOT NULL,state TEXT NOT NULL,
 caller_ready INTEGER NOT NULL DEFAULT 0,callee_ready INTEGER NOT NULL DEFAULT 0,
 caller_applied INTEGER NOT NULL DEFAULT 0,callee_applied INTEGER NOT NULL DEFAULT 0,
 created_at TEXT NOT NULL,updated_at TEXT NOT NULL,deadline TEXT NOT NULL,
 PRIMARY KEY(call_id,request_id),UNIQUE(call_id,revision)
);
