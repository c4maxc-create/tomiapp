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



-- Voice rooms are additive: existing account/chat/call data stays unchanged.
CREATE TABLE IF NOT EXISTS tomi_voice_rooms (
 id TEXT PRIMARY KEY,
 title TEXT NOT NULL,
 owner_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 capacity INTEGER NOT NULL CHECK(capacity BETWEEN 2 AND 30),
 seat_count INTEGER NOT NULL CHECK(seat_count BETWEEN 2 AND 8),
 state TEXT NOT NULL DEFAULT 'open' CHECK(state IN ('open','closed')),
 revision INTEGER NOT NULL DEFAULT 1,
 created_at TEXT NOT NULL,
 empty_since TEXT,
 needs_delete INTEGER NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX IF NOT EXISTS tomi_one_owned_voice_room ON tomi_voice_rooms(owner_id) WHERE state='open';
CREATE TABLE IF NOT EXISTS tomi_voice_members (
 room_id TEXT NOT NULL REFERENCES tomi_voice_rooms(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 identity TEXT NOT NULL UNIQUE,
 session_hash TEXT NOT NULL,
 role TEXT NOT NULL CHECK(role IN ('owner','moderator','member')),
 state TEXT NOT NULL DEFAULT 'active' CHECK(state IN ('active','left','kicked')),
 seat INTEGER,
 mic_allowed INTEGER NOT NULL DEFAULT 0,
 requested_at TEXT,
 joined_at TEXT NOT NULL,
 last_seen TEXT NOT NULL,
 PRIMARY KEY(room_id,user_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS tomi_one_voice_seat ON tomi_voice_members(room_id,seat) WHERE state='active' AND seat IS NOT NULL;
CREATE TABLE IF NOT EXISTS tomi_voice_presence (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,
 room_id TEXT NOT NULL REFERENCES tomi_voice_rooms(id) ON DELETE CASCADE
);
-- Durable desired permissions/removals survive API restarts and SFU outages.
CREATE TABLE IF NOT EXISTS tomi_voice_jobs (
 identity TEXT PRIMARY KEY,
 room_id TEXT NOT NULL REFERENCES tomi_voice_rooms(id) ON DELETE CASCADE,
 publish INTEGER NOT NULL,
 version INTEGER NOT NULL DEFAULT 1
);


-- Additive 0.8. Reserved owner seat is -1; companion is -2; regular seats 0..7.
-- Keep the original room/seat-count CHECKs and all existing account data intact.
CREATE TABLE IF NOT EXISTS tomi_room_options (
 room_id TEXT PRIMARY KEY REFERENCES tomi_voice_rooms(id) ON DELETE CASCADE,
 announcement TEXT NOT NULL DEFAULT '',category TEXT NOT NULL DEFAULT 'الأصدقاء',
 mode TEXT NOT NULL DEFAULT 'عادي',background TEXT NOT NULL DEFAULT 'ocean',
 theme TEXT NOT NULL DEFAULT 'gold',picture TEXT NOT NULL DEFAULT 'headphones',
 image_upload_id TEXT UNIQUE REFERENCES tomi_image_uploads(id),
 companion_enabled INTEGER NOT NULL DEFAULT 1,
 chat_disabled INTEGER NOT NULL DEFAULT 0,images_disabled INTEGER NOT NULL DEFAULT 0,
 high_quality INTEGER NOT NULL DEFAULT 1,password_hash TEXT,
 xp BIGINT NOT NULL DEFAULT 0 CHECK(xp>=0),next_event BIGINT NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS tomi_room_seats (
 room_id TEXT NOT NULL REFERENCES tomi_voice_rooms(id) ON DELETE CASCADE,
 seat INTEGER NOT NULL CHECK(seat BETWEEN -2 AND 7 AND seat<>-1),
 locked INTEGER NOT NULL DEFAULT 0,muted INTEGER NOT NULL DEFAULT 0,
 PRIMARY KEY(room_id,seat)
);
CREATE TABLE IF NOT EXISTS tomi_room_invites (
 room_id TEXT NOT NULL REFERENCES tomi_voice_rooms(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 seat INTEGER NOT NULL,invited_by TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 expires_at TEXT NOT NULL,PRIMARY KEY(room_id,user_id)
);
CREATE TABLE IF NOT EXISTS tomi_room_wallets (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,
 coins BIGINT NOT NULL CHECK(coins>=0),next_claim TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tomi_room_gifts (
 id TEXT PRIMARY KEY,room_id TEXT NOT NULL REFERENCES tomi_voice_rooms(id) ON DELETE CASCADE,
 sender_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 recipient_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 request_id TEXT NOT NULL,gift_id TEXT NOT NULL,quantity INTEGER NOT NULL CHECK(quantity BETWEEN 1 AND 99),
 unit_price INTEGER NOT NULL,total BIGINT NOT NULL CHECK(total>0),created_at TEXT NOT NULL,
 UNIQUE(sender_id,request_id),CHECK(sender_id<>recipient_id)
);
CREATE INDEX IF NOT EXISTS tomi_room_gifts_rank ON tomi_room_gifts(room_id,sender_id);
CREATE TABLE IF NOT EXISTS tomi_room_events (
 room_id TEXT NOT NULL REFERENCES tomi_voice_rooms(id) ON DELETE CASCADE,
 sequence BIGINT NOT NULL,actor_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 request_id TEXT,kind TEXT NOT NULL CHECK(kind IN ('message','gift','system')),
 body TEXT NOT NULL,image_upload_id TEXT UNIQUE REFERENCES tomi_image_uploads(id),
 gift_id TEXT REFERENCES tomi_room_gifts(id),created_at TEXT NOT NULL,
 PRIMARY KEY(room_id,sequence),UNIQUE(room_id,actor_id,request_id)
);
CREATE TABLE IF NOT EXISTS tomi_room_audit (
 room_id TEXT NOT NULL REFERENCES tomi_voice_rooms(id) ON DELETE CASCADE,
 id TEXT PRIMARY KEY,actor_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 action TEXT NOT NULL,detail TEXT NOT NULL,created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS tomi_room_audit_recent ON tomi_room_audit(room_id,created_at,id);

-- 0.9: device capability negotiation and durable ring cancellation. No reset.
CREATE TABLE IF NOT EXISTS tomi_call_push_protocol (
 token_hash TEXT PRIMARY KEY REFERENCES tomi_push_devices(token_hash) ON DELETE CASCADE,
 protocol INTEGER NOT NULL DEFAULT 2
);
CREATE TABLE IF NOT EXISTS tomi_call_push_cancel (
 call_id TEXT PRIMARY KEY REFERENCES tomi_calls(id) ON DELETE CASCADE,
 recipient_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 thread_id TEXT NOT NULL,
 state TEXT NOT NULL DEFAULT 'pending',
 attempts INTEGER NOT NULL DEFAULT 0,
 next_at TEXT NOT NULL,
 lease_until TEXT NOT NULL DEFAULT '',
 created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tomi_call_push_cancel_receipts (
 call_id TEXT NOT NULL REFERENCES tomi_call_push_cancel(call_id) ON DELETE CASCADE,
 token_hash TEXT NOT NULL,
 PRIMARY KEY(call_id,token_hash)
);

CREATE INDEX IF NOT EXISTS tomi_call_push_cancel_pending ON tomi_call_push_cancel(state,next_at,lease_until);

-- 0.10: additive messaging features, media intent receipts and video attachments.
CREATE TABLE IF NOT EXISTS tomi_upload_digests (
 upload_id TEXT PRIMARY KEY, sha256 TEXT NOT NULL, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tomi_media_intents (
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 request_id TEXT NOT NULL, scope TEXT NOT NULL, payload_hash TEXT NOT NULL,
 upload_id TEXT NOT NULL, created_at TEXT NOT NULL,
 PRIMARY KEY(user_id,request_id)
);
CREATE TABLE IF NOT EXISTS tomi_chat_features (
 thread_id TEXT PRIMARY KEY REFERENCES tomi_chat_threads(id) ON DELETE CASCADE,
 revision INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS tomi_chat_message_meta (
 message_id TEXT PRIMARY KEY REFERENCES tomi_chat_messages(id) ON DELETE CASCADE,
 reply_to_id TEXT REFERENCES tomi_chat_messages(id) ON DELETE SET NULL,
 media_sha256 TEXT, revision INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS tomi_chat_reactions (
 message_id TEXT NOT NULL REFERENCES tomi_chat_messages(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 emoji TEXT NOT NULL, PRIMARY KEY(message_id,user_id)
);
CREATE TABLE IF NOT EXISTS tomi_chat_pins (
 thread_id TEXT PRIMARY KEY REFERENCES tomi_chat_threads(id) ON DELETE CASCADE,
 message_id TEXT NOT NULL REFERENCES tomi_chat_messages(id) ON DELETE CASCADE,
 pinned_by TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tomi_video_uploads (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 thread_id TEXT REFERENCES tomi_chat_threads(id) ON DELETE CASCADE,
 object_key TEXT NOT NULL UNIQUE, content_type TEXT NOT NULL,
 byte_length INTEGER NOT NULL, content_md5 TEXT NOT NULL,
 width INTEGER, height INTEGER, duration_ms INTEGER,
 state TEXT NOT NULL DEFAULT 'pending', created_at TEXT NOT NULL, expires_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tomi_chat_video (
 message_id TEXT PRIMARY KEY REFERENCES tomi_chat_messages(id) ON DELETE CASCADE,
 upload_id TEXT NOT NULL UNIQUE REFERENCES tomi_video_uploads(id)
);
CREATE TABLE IF NOT EXISTS tomi_post_video (
 post_id TEXT PRIMARY KEY REFERENCES tomi_posts(id) ON DELETE CASCADE,
 upload_id TEXT NOT NULL UNIQUE REFERENCES tomi_video_uploads(id), media_sha256 TEXT
);
CREATE INDEX IF NOT EXISTS tomi_video_cleanup ON tomi_video_uploads(state,expires_at);
CREATE INDEX IF NOT EXISTS tomi_chat_reply_targets ON tomi_chat_message_meta(reply_to_id);

CREATE TABLE IF NOT EXISTS tomi_post_request_meta (post_id TEXT PRIMARY KEY REFERENCES tomi_posts(id) ON DELETE CASCADE,payload_hash TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS tomi_post_receipts (user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,request_id TEXT NOT NULL,post_id TEXT NOT NULL,body TEXT NOT NULL,image_upload_id TEXT,payload_hash TEXT,PRIMARY KEY(user_id,request_id));
INSERT INTO tomi_post_receipts(user_id,request_id,post_id,body,image_upload_id,payload_hash) SELECT p.user_id,p.request_id,p.id,p.body,p.image_upload_id,x.payload_hash FROM tomi_posts p LEFT JOIN tomi_post_request_meta x ON x.post_id=p.id WHERE 1=1 ON CONFLICT(user_id,request_id) DO NOTHING;

-- 0.11: user identity, private room preferences and entry cosmetics.
CREATE TABLE IF NOT EXISTS tomi_user_progress (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,
 spent BIGINT NOT NULL DEFAULT 0 CHECK(spent>=0 AND spent<=9000000000000),
 gifts_sent BIGINT NOT NULL DEFAULT 0,received BIGINT NOT NULL DEFAULT 0 CHECK(received>=0 AND received<=9000000000000),
 gifts_received BIGINT NOT NULL DEFAULT 0,rooms_created INTEGER NOT NULL DEFAULT 0
);
INSERT INTO tomi_user_progress(user_id,spent,gifts_sent,received,gifts_received,rooms_created)
 SELECT u.id,COALESCE((SELECT SUM(g.total) FROM tomi_room_gifts g WHERE g.sender_id=u.id),0),
 (SELECT COUNT(*) FROM tomi_room_gifts g WHERE g.sender_id=u.id),COALESCE((SELECT SUM(g.total) FROM tomi_room_gifts g WHERE g.recipient_id=u.id),0),
 (SELECT COUNT(*) FROM tomi_room_gifts g WHERE g.recipient_id=u.id),(SELECT COUNT(*) FROM tomi_voice_rooms r WHERE r.owner_id=u.id)
 FROM tomi_users u WHERE NOT EXISTS(SELECT 1 FROM tomi_user_progress p WHERE p.user_id=u.id) ON CONFLICT(user_id) DO NOTHING;
CREATE TABLE IF NOT EXISTS tomi_user_identity (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,
 frame_id TEXT NOT NULL DEFAULT 'none',portrait_id TEXT NOT NULL DEFAULT 'none',entrance_id TEXT NOT NULL DEFAULT 'none',revision INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS tomi_room_preferences (
 room_id TEXT NOT NULL REFERENCES tomi_voice_rooms(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 favorite INTEGER NOT NULL DEFAULT 0 CHECK(favorite IN(0,1)),following INTEGER NOT NULL DEFAULT 0 CHECK(following IN(0,1)),
 revision INTEGER NOT NULL DEFAULT 0,updated_at TEXT NOT NULL,PRIMARY KEY(room_id,user_id)
);
CREATE TABLE IF NOT EXISTS tomi_room_entry_effects (
 room_id TEXT NOT NULL,sequence BIGINT NOT NULL,style_id TEXT NOT NULL,
 PRIMARY KEY(room_id,sequence),FOREIGN KEY(room_id,sequence) REFERENCES tomi_room_events(room_id,sequence) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS tomi_room_entry_cooldowns (
 room_id TEXT NOT NULL REFERENCES tomi_voice_rooms(id) ON DELETE CASCADE,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 last_effect_at TEXT NOT NULL,PRIMARY KEY(room_id,user_id)
);
CREATE INDEX IF NOT EXISTS tomi_room_preferences_user ON tomi_room_preferences(user_id,favorite,following,updated_at);
CREATE INDEX IF NOT EXISTS tomi_gifts_daily_sender ON tomi_room_gifts(created_at,sender_id);
CREATE INDEX IF NOT EXISTS tomi_gifts_room_period ON tomi_room_gifts(room_id,created_at,sender_id);
CREATE INDEX IF NOT EXISTS tomi_gifts_receiver ON tomi_room_gifts(recipient_id);

-- 0.12: platform moderation is independent from room microphone roles.
CREATE TABLE IF NOT EXISTS tomi_platform_roles (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,
 role TEXT NOT NULL DEFAULT 'member' CHECK(role IN('member','moderator')),
 revision INTEGER NOT NULL DEFAULT 0,granted_by TEXT NOT NULL,updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tomi_account_restrictions (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,
 suspended INTEGER NOT NULL DEFAULT 0 CHECK(suspended IN(0,1)),revision INTEGER NOT NULL DEFAULT 0,
 reason TEXT NOT NULL,updated_by TEXT NOT NULL,updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tomi_content_moderation (
 target_type TEXT NOT NULL CHECK(target_type IN('post','room')),target_id TEXT NOT NULL,
 hidden INTEGER NOT NULL DEFAULT 0 CHECK(hidden IN(0,1)),revision INTEGER NOT NULL DEFAULT 0,
 reason TEXT NOT NULL,updated_by TEXT NOT NULL,updated_at TEXT NOT NULL,PRIMARY KEY(target_type,target_id)
);
CREATE TABLE IF NOT EXISTS tomi_reports (
 id TEXT PRIMARY KEY,reporter_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 target_type TEXT NOT NULL CHECK(target_type IN('account','post','room')),target_id TEXT NOT NULL,subject_user_id TEXT NOT NULL,
 reason TEXT NOT NULL,description TEXT NOT NULL,snapshot TEXT NOT NULL,
 status TEXT NOT NULL DEFAULT 'open' CHECK(status IN('open','reviewing','resolved','dismissed')),
 revision INTEGER NOT NULL DEFAULT 0,public_message TEXT NOT NULL DEFAULT '',review_note TEXT NOT NULL DEFAULT '',
 reviewer_id TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tomi_report_requests (
 reporter_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,request_id TEXT NOT NULL,
 report_id TEXT NOT NULL REFERENCES tomi_reports(id) ON DELETE CASCADE,payload_hash TEXT NOT NULL,created_at TEXT NOT NULL,
 PRIMARY KEY(reporter_id,request_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS tomi_reports_one_open ON tomi_reports(reporter_id,target_type,target_id) WHERE status IN('open','reviewing');
CREATE INDEX IF NOT EXISTS tomi_reports_queue ON tomi_reports(status,created_at,id);
CREATE INDEX IF NOT EXISTS tomi_reports_reporter ON tomi_reports(reporter_id,created_at,id);
CREATE TABLE IF NOT EXISTS tomi_admin_audit (
 id TEXT PRIMARY KEY,actor_id TEXT NOT NULL,action TEXT NOT NULL,target_type TEXT NOT NULL,target_id TEXT NOT NULL,
 reason TEXT NOT NULL,report_id TEXT,details TEXT NOT NULL,created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS tomi_admin_audit_page ON tomi_admin_audit(created_at,id);
CREATE TABLE IF NOT EXISTS tomi_admin_requests (
 actor_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,request_id TEXT NOT NULL,
 payload_hash TEXT NOT NULL,result TEXT NOT NULL,created_at TEXT NOT NULL,PRIMARY KEY(actor_id,request_id)
);

-- 1.0 beta: personal data is erased; opaque stubs keep shared gift references.
CREATE TABLE IF NOT EXISTS tomi_deleted_accounts (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,
 requested_at TEXT NOT NULL,completed_at TEXT
);
CREATE TABLE IF NOT EXISTS tomi_deletion_receipts (
 id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES tomi_deleted_accounts(user_id) ON DELETE CASCADE,
 token_hash TEXT NOT NULL,created_at TEXT NOT NULL,expires_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tomi_erasure_media (
 id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES tomi_deleted_accounts(user_id) ON DELETE CASCADE,
 media_type TEXT NOT NULL CHECK(media_type IN('image','audio','video')),upload_id TEXT NOT NULL,
 scope TEXT NOT NULL CHECK(scope IN('public','private')),object_key TEXT NOT NULL,
 final_after TEXT NOT NULL,next_at TEXT NOT NULL,lease_until TEXT NOT NULL DEFAULT '',attempts INTEGER NOT NULL DEFAULT 0,
 UNIQUE(scope,object_key)
);
CREATE INDEX IF NOT EXISTS tomi_erasure_pending ON tomi_erasure_media(next_at,lease_until);
CREATE TABLE IF NOT EXISTS tomi_privacy_retention (
 kind TEXT NOT NULL CHECK(kind IN('report','audit')),id TEXT NOT NULL,expires_at TEXT NOT NULL,
 PRIMARY KEY(kind,id)
);
-- The earlier historical-gift backfill must never recreate erased identity data.
DELETE FROM tomi_user_progress WHERE user_id IN(SELECT user_id FROM tomi_deleted_accounts);
CREATE TABLE IF NOT EXISTS tomi_policy_acceptances (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,
 policy_version TEXT NOT NULL,accepted_at TEXT NOT NULL
);

-- 1.1: expiring stories and a persistent social activity inbox. Additive upgrade.
CREATE TABLE IF NOT EXISTS tomi_stories (
 id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 request_id TEXT NOT NULL,body TEXT NOT NULL,
 image_upload_id TEXT UNIQUE REFERENCES tomi_image_uploads(id),
 video_upload_id TEXT UNIQUE REFERENCES tomi_video_uploads(id),
 created_at TEXT NOT NULL,expires_at TEXT NOT NULL,UNIQUE(user_id,request_id),
 CHECK(image_upload_id IS NULL OR video_upload_id IS NULL)
);
CREATE INDEX IF NOT EXISTS tomi_stories_user ON tomi_stories(user_id,expires_at,created_at,id);
CREATE INDEX IF NOT EXISTS tomi_stories_expiry ON tomi_stories(expires_at);
CREATE TABLE IF NOT EXISTS tomi_story_views (
 story_id TEXT NOT NULL REFERENCES tomi_stories(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 viewed_at TEXT NOT NULL,PRIMARY KEY(story_id,user_id)
);
CREATE TABLE IF NOT EXISTS tomi_story_receipts (
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,request_id TEXT NOT NULL,
 story_id TEXT NOT NULL,payload_hash TEXT NOT NULL,created_at TEXT NOT NULL,PRIMARY KEY(user_id,request_id)
);
CREATE TABLE IF NOT EXISTS tomi_activity (
 id TEXT PRIMARY KEY,recipient_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 actor_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 kind TEXT NOT NULL CHECK(kind IN('follow','like','comment')),target_id TEXT NOT NULL,
 dedupe_key TEXT NOT NULL UNIQUE,created_at TEXT NOT NULL,read_at TEXT,
 push_state TEXT NOT NULL DEFAULT 'pending',next_at TEXT NOT NULL,lease_until TEXT NOT NULL DEFAULT '',attempts INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS tomi_activity_page ON tomi_activity(recipient_id,created_at,id);
CREATE INDEX IF NOT EXISTS tomi_activity_pending ON tomi_activity(push_state,next_at);
CREATE TABLE IF NOT EXISTS tomi_activity_push_receipts (
 activity_id TEXT NOT NULL REFERENCES tomi_activity(id) ON DELETE CASCADE,
 token_hash TEXT NOT NULL,PRIMARY KEY(activity_id,token_hash)
);
CREATE TABLE IF NOT EXISTS tomi_post_saves (
 post_id TEXT NOT NULL REFERENCES tomi_posts(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,created_at TEXT NOT NULL,
 PRIMARY KEY(post_id,user_id)
);

-- Additive1.2: private documents, built-in stickers and independently owned groups.
CREATE TABLE IF NOT EXISTS tomi_private_uploads (
 id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 thread_id TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN('image','audio','video','file')),
 object_key TEXT NOT NULL UNIQUE,content_type TEXT NOT NULL,byte_length INTEGER NOT NULL,
 content_md5 TEXT NOT NULL,file_name TEXT,duration_ms INTEGER,width INTEGER,height INTEGER,
 state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN('pending','attached','deleting')),
 created_at TEXT NOT NULL,expires_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS tomi_private_upload_expiry ON tomi_private_uploads(state,expires_at);
CREATE TABLE IF NOT EXISTS tomi_chat_documents (
 message_id TEXT PRIMARY KEY REFERENCES tomi_chat_messages(id) ON DELETE CASCADE,
 upload_id TEXT NOT NULL UNIQUE REFERENCES tomi_private_uploads(id)
);
CREATE TABLE IF NOT EXISTS tomi_chat_stickers (
 message_id TEXT PRIMARY KEY REFERENCES tomi_chat_messages(id) ON DELETE CASCADE,sticker_id TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tomi_groups (
 id TEXT PRIMARY KEY,owner_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 creator_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 title TEXT NOT NULL,request_id TEXT NOT NULL,payload_hash TEXT NOT NULL,
 next_seq BIGINT NOT NULL DEFAULT 0,revision INTEGER NOT NULL DEFAULT 0,
 pinned_message_id TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,
 UNIQUE(creator_id,request_id)
);
CREATE INDEX IF NOT EXISTS tomi_groups_recent ON tomi_groups(updated_at,id);
CREATE TABLE IF NOT EXISTS tomi_group_members (
 group_id TEXT NOT NULL REFERENCES tomi_groups(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 last_read_seq BIGINT NOT NULL DEFAULT 0,joined_seq BIGINT NOT NULL DEFAULT 0,joined_at TEXT NOT NULL,left_at TEXT,
 PRIMARY KEY(group_id,user_id)
);
CREATE TABLE IF NOT EXISTS tomi_group_messages (
 id TEXT PRIMARY KEY,group_id TEXT NOT NULL REFERENCES tomi_groups(id) ON DELETE CASCADE,
 sender_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 sequence BIGINT NOT NULL,request_id TEXT NOT NULL,payload_hash TEXT NOT NULL,body TEXT NOT NULL,
 upload_id TEXT UNIQUE REFERENCES tomi_private_uploads(id),sticker_id TEXT,reply_to_id TEXT,
 revision INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL,deleted_at TEXT,
 UNIQUE(group_id,sequence),UNIQUE(sender_id,request_id)
);
CREATE INDEX IF NOT EXISTS tomi_group_history ON tomi_group_messages(group_id,sequence);
CREATE TABLE IF NOT EXISTS tomi_group_reactions (
 message_id TEXT NOT NULL REFERENCES tomi_group_messages(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,emoji TEXT NOT NULL,
 PRIMARY KEY(message_id,user_id)
);
CREATE TABLE IF NOT EXISTS tomi_group_push (
 message_id TEXT NOT NULL REFERENCES tomi_group_messages(id) ON DELETE CASCADE,
 recipient_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 group_id TEXT NOT NULL,state TEXT NOT NULL DEFAULT 'pending',attempts INTEGER NOT NULL DEFAULT 0,
 next_at TEXT NOT NULL,lease_until TEXT NOT NULL DEFAULT '',created_at TEXT NOT NULL,
 PRIMARY KEY(message_id,recipient_id)
);
CREATE TABLE IF NOT EXISTS tomi_group_push_receipts (
 message_id TEXT NOT NULL,recipient_id TEXT NOT NULL,token_hash TEXT NOT NULL,
 PRIMARY KEY(message_id,recipient_id,token_hash),
 FOREIGN KEY(message_id,recipient_id) REFERENCES tomi_group_push(message_id,recipient_id) ON DELETE CASCADE
);


-- 1.3: additive room policy, immutable purchases and support ledger.
-- Legacy rooms are grandfathered as advanced with no charge. Never erase gifts.
DROP INDEX IF EXISTS tomi_one_owned_voice_room;
CREATE TABLE IF NOT EXISTS tomi_room_policy (
 room_id TEXT PRIMARY KEY REFERENCES tomi_voice_rooms(id) ON DELETE CASCADE,
 tier TEXT NOT NULL CHECK(tier IN ('free','advanced')),
 public_id TEXT UNIQUE, creator_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 price INTEGER NOT NULL DEFAULT 0, last_owner_visit TEXT NOT NULL,
 CHECK((tier='free' AND public_id IS NULL) OR (tier='advanced' AND public_id IS NOT NULL))
);
CREATE TABLE IF NOT EXISTS tomi_room_numbers (id INTEGER PRIMARY KEY,value BIGINT NOT NULL);
INSERT INTO tomi_room_numbers(id,value) VALUES(1,100000) ON CONFLICT(id) DO NOTHING;
INSERT INTO tomi_room_policy(room_id,tier,public_id,creator_id,price,last_owner_visit)
 SELECT r.id,'advanced','L-' || r.id,r.owner_id,0,r.created_at FROM tomi_voice_rooms r
 WHERE NOT EXISTS(SELECT 1 FROM tomi_room_policy p WHERE p.room_id=r.id);
CREATE INDEX IF NOT EXISTS tomi_room_expiry ON tomi_room_policy(tier,last_owner_visit);
CREATE TABLE IF NOT EXISTS tomi_room_chat_cursors (
 room_id TEXT NOT NULL REFERENCES tomi_voice_rooms(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 identity TEXT NOT NULL, after_sequence BIGINT NOT NULL, PRIMARY KEY(room_id,user_id)
);
CREATE TABLE IF NOT EXISTS tomi_room_support_batches (
 id TEXT PRIMARY KEY,room_id TEXT NOT NULL REFERENCES tomi_voice_rooms(id) ON DELETE CASCADE,
 sender_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 request_id TEXT NOT NULL, fingerprint TEXT NOT NULL,total BIGINT NOT NULL,recipients TEXT NOT NULL,
 UNIQUE(sender_id,request_id)
);
CREATE TABLE IF NOT EXISTS tomi_room_support (
 id TEXT PRIMARY KEY,room_id TEXT NOT NULL REFERENCES tomi_voice_rooms(id) ON DELETE CASCADE,
 sender_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 recipient_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 request_id TEXT NOT NULL,gift_id TEXT NOT NULL,quantity INTEGER NOT NULL CHECK(quantity BETWEEN 1 AND 99),
 unit_price INTEGER NOT NULL,total BIGINT NOT NULL CHECK(total>0),created_at TEXT NOT NULL,
 UNIQUE(sender_id,request_id)
);
CREATE INDEX IF NOT EXISTS tomi_support_rank ON tomi_room_support(room_id,created_at,sender_id);
CREATE VIEW IF NOT EXISTS tomi_room_all_gifts AS SELECT * FROM tomi_room_gifts UNION ALL SELECT * FROM tomi_room_support;
CREATE TABLE IF NOT EXISTS tomi_support_events (
 room_id TEXT NOT NULL,sequence BIGINT NOT NULL,gift_id TEXT NOT NULL REFERENCES tomi_room_support(id) ON DELETE CASCADE,
 PRIMARY KEY(room_id,sequence), FOREIGN KEY(room_id,sequence) REFERENCES tomi_room_events(room_id,sequence) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS tomi_room_cosmetics (
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,kind TEXT NOT NULL,
 style_id TEXT NOT NULL,expires_at TEXT NOT NULL,equipped INTEGER NOT NULL DEFAULT 1,
 PRIMARY KEY(user_id,kind,style_id)
);
CREATE TABLE IF NOT EXISTS tomi_cosmetic_purchases (
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,request_id TEXT NOT NULL,
 fingerprint TEXT NOT NULL,expires_at TEXT NOT NULL,total INTEGER NOT NULL,PRIMARY KEY(user_id,request_id)
);

CREATE INDEX IF NOT EXISTS tomi_support_user_rank ON tomi_room_support(sender_id,created_at);

-- 1.4: explicit platform staff permissions and audited owner account controls.
CREATE TABLE IF NOT EXISTS tomi_staff_permissions (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,
 permissions TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tomi_admin_profiles (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,
 special INTEGER NOT NULL DEFAULT 0 CHECK(special IN(0,1)),
 revision INTEGER NOT NULL DEFAULT 0
);

-- 1.5 additive roulette access, receipts and contribution metrics.
CREATE TABLE IF NOT EXISTS tomi_roulette_config (
 id INTEGER PRIMARY KEY CHECK(id=1),revision INTEGER NOT NULL DEFAULT 0,
 mode TEXT NOT NULL DEFAULT 'everyone',daily_limit INTEGER NOT NULL DEFAULT 5,prizes TEXT NOT NULL DEFAULT '[]'
);
INSERT INTO tomi_roulette_config(id) VALUES(1) ON CONFLICT(id) DO NOTHING;
CREATE TABLE IF NOT EXISTS tomi_roulette_access (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,
 allowed INTEGER NOT NULL CHECK(allowed IN(0,1)),updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tomi_roulette_daily (
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,day TEXT NOT NULL,
 used INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(user_id,day)
);
CREATE TABLE IF NOT EXISTS tomi_roulette_spins (
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,request_id TEXT NOT NULL,
 room_id TEXT NOT NULL REFERENCES tomi_voice_rooms(id) ON DELETE CASCADE,
 result TEXT NOT NULL,created_at TEXT NOT NULL,PRIMARY KEY(user_id,request_id)
);
CREATE TABLE IF NOT EXISTS tomi_roulette_requests (
 actor_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,request_id TEXT NOT NULL,
 fingerprint TEXT NOT NULL,result TEXT NOT NULL,action TEXT NOT NULL,created_at TEXT NOT NULL,PRIMARY KEY(actor_id,request_id)
);
CREATE TABLE IF NOT EXISTS tomi_contribution_credits (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,
 total BIGINT NOT NULL DEFAULT 0 CHECK(total>=0 AND total<=9000000000000)
);
CREATE INDEX IF NOT EXISTS tomi_activity_message_sender ON tomi_chat_messages(sender_id,created_at);

CREATE INDEX IF NOT EXISTS tomi_roulette_recent ON tomi_roulette_spins(user_id,created_at,request_id);
CREATE INDEX IF NOT EXISTS tomi_roulette_groups ON tomi_roulette_requests(created_at,request_id);

-- 1.6 shared room roulette. All stakes and settlements use database transactions.
CREATE TABLE IF NOT EXISTS tomi_live_roulette_state (
 id INTEGER PRIMARY KEY CHECK(id=1),data TEXT NOT NULL DEFAULT '{}',revision BIGINT NOT NULL DEFAULT 0
);
INSERT INTO tomi_live_roulette_state(id) VALUES(1) ON CONFLICT(id) DO NOTHING;
CREATE TABLE IF NOT EXISTS tomi_live_roulette_rounds (
 id TEXT PRIMARY KEY,day TEXT NOT NULL,started_at BIGINT NOT NULL,result TEXT,settled_at BIGINT
);
CREATE INDEX IF NOT EXISTS tomi_live_roulette_recent ON tomi_live_roulette_rounds(started_at DESC,id);
CREATE TABLE IF NOT EXISTS tomi_live_roulette_bets (
 round_id TEXT NOT NULL REFERENCES tomi_live_roulette_rounds(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 chips TEXT NOT NULL,total BIGINT NOT NULL,payout BIGINT NOT NULL DEFAULT 0,gross_payout BIGINT NOT NULL DEFAULT 0,settled INTEGER NOT NULL DEFAULT 0,
 PRIMARY KEY(round_id,user_id)
);
CREATE INDEX IF NOT EXISTS tomi_live_roulette_user ON tomi_live_roulette_bets(user_id,round_id);
CREATE TABLE IF NOT EXISTS tomi_live_roulette_requests (
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,request_id TEXT NOT NULL,
 fingerprint TEXT NOT NULL,result TEXT NOT NULL,created_at BIGINT NOT NULL,PRIMARY KEY(user_id,request_id)
);
CREATE TABLE IF NOT EXISTS tomi_live_roulette_last (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,chips TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tomi_live_roulette_daily (
 day TEXT NOT NULL,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 total_bet BIGINT NOT NULL DEFAULT 0,total_payout BIGINT NOT NULL DEFAULT 0,wins BIGINT NOT NULL DEFAULT 0,
 PRIMARY KEY(day,user_id)
);
CREATE INDEX IF NOT EXISTS tomi_live_roulette_daily_rank ON tomi_live_roulette_daily(day,total_payout DESC,wins DESC,user_id);
CREATE TABLE IF NOT EXISTS tomi_live_roulette_award_days (day TEXT PRIMARY KEY,created_at BIGINT NOT NULL);
CREATE TABLE IF NOT EXISTS tomi_live_roulette_awards (
 day TEXT NOT NULL,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,rank INTEGER NOT NULL,prize BIGINT NOT NULL,credited BIGINT NOT NULL,
 PRIMARY KEY(day,rank),UNIQUE(day,user_id)
);

-- 1.6 post sharing and recipient-controlled stranger requests.
-- 1.7 games. Private hands are stored only in server state; membership is separate.
CREATE TABLE IF NOT EXISTS tomi_game_progress (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,
 xp BIGINT NOT NULL DEFAULT 0 CHECK(xp>=0 AND xp<=240100)
);
CREATE TABLE IF NOT EXISTS tomi_game_awards (
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 source_kind TEXT NOT NULL,source_id TEXT NOT NULL,day TEXT NOT NULL,
 xp INTEGER NOT NULL CHECK(xp>=0),created_at BIGINT NOT NULL,
 PRIMARY KEY(user_id,source_kind,source_id)
);
CREATE INDEX IF NOT EXISTS tomi_game_award_day ON tomi_game_awards(user_id,day);
CREATE TABLE IF NOT EXISTS tomi_game_matches (
 id TEXT PRIMARY KEY,code TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN('uno','snakes')),
 mode TEXT NOT NULL CHECK(mode IN('practice','friends')),
 host_id TEXT REFERENCES tomi_users(id) ON DELETE SET NULL,
 status TEXT NOT NULL CHECK(status IN('waiting','playing','finished','cancelled')),
 revision BIGINT NOT NULL DEFAULT 0,state TEXT NOT NULL,
 due_at BIGINT NOT NULL,created_at BIGINT NOT NULL,updated_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS tomi_game_due ON tomi_game_matches(status,due_at);
CREATE TABLE IF NOT EXISTS tomi_game_players (
 match_id TEXT NOT NULL REFERENCES tomi_game_matches(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,seat INTEGER NOT NULL CHECK(seat>=0 AND seat<4),
 PRIMARY KEY(match_id,user_id),UNIQUE(match_id,seat)
);
CREATE INDEX IF NOT EXISTS tomi_game_membership ON tomi_game_players(user_id,match_id);
CREATE TABLE IF NOT EXISTS tomi_game_requests (
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,request_id TEXT NOT NULL,
 fingerprint TEXT NOT NULL,match_id TEXT NOT NULL REFERENCES tomi_game_matches(id) ON DELETE CASCADE,
 result TEXT NOT NULL,created_at BIGINT NOT NULL,PRIMARY KEY(user_id,request_id)
);
CREATE TABLE IF NOT EXISTS tomi_roulette_watchers (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,expires_at BIGINT NOT NULL
);

-- 1.6 post sharing and recipient-controlled stranger requests.
CREATE TABLE IF NOT EXISTS tomi_post_shares (
 message_id TEXT PRIMARY KEY REFERENCES tomi_chat_messages(id) ON DELETE CASCADE,
 post_id TEXT REFERENCES tomi_posts(id) ON DELETE SET NULL
);
CREATE TABLE IF NOT EXISTS tomi_post_share_receipts (
 sender_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,request_id TEXT NOT NULL,
 target_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,post_id TEXT NOT NULL,
 fingerprint TEXT NOT NULL,result TEXT NOT NULL,created_at TEXT NOT NULL,PRIMARY KEY(sender_id,request_id)
);
CREATE TABLE IF NOT EXISTS tomi_post_share_requests (
 id TEXT PRIMARY KEY,sender_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 recipient_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 post_id TEXT REFERENCES tomi_posts(id) ON DELETE SET NULL,client_nonce TEXT NOT NULL,
 state TEXT NOT NULL CHECK(state IN('pending','accepted','blocked')),created_at TEXT NOT NULL,updated_at TEXT NOT NULL,
 UNIQUE(sender_id,client_nonce)
);
CREATE INDEX IF NOT EXISTS tomi_post_share_inbox ON tomi_post_share_requests(recipient_id,state,created_at,id);
CREATE TABLE IF NOT EXISTS tomi_post_share_pairs (
 sender_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 recipient_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,created_at TEXT NOT NULL,
 PRIMARY KEY(sender_id,recipient_id)
);
CREATE TABLE IF NOT EXISTS tomi_post_share_actions (
 actor_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,request_id TEXT NOT NULL,
 fingerprint TEXT NOT NULL,result TEXT NOT NULL,created_at TEXT NOT NULL,PRIMARY KEY(actor_id,request_id)
);
CREATE TABLE IF NOT EXISTS tomi_game_search_locks (kind TEXT PRIMARY KEY,tick BIGINT NOT NULL DEFAULT 0);
INSERT INTO tomi_game_search_locks(kind) VALUES('uno'),('snakes'),('jackaroo'),('camel'),('wheel') ON CONFLICT(kind) DO NOTHING;
CREATE TABLE IF NOT EXISTS tomi_game_searches (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,
 kind TEXT NOT NULL CHECK(kind IN('uno','snakes','jackaroo','camel','wheel')),
 queued_at BIGINT NOT NULL,expires_at BIGINT NOT NULL,
 match_id TEXT REFERENCES tomi_game_matches(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS tomi_game_search_waiting ON tomi_game_searches(kind,match_id,queued_at);

CREATE TABLE IF NOT EXISTS tomi_call_cross_requests (
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 request_id TEXT NOT NULL, call_id TEXT NOT NULL REFERENCES tomi_calls(id) ON DELETE CASCADE,
 PRIMARY KEY(user_id,request_id)
);

CREATE TABLE IF NOT EXISTS tomi_post_options(post_id TEXT PRIMARY KEY REFERENCES tomi_posts(id) ON DELETE CASCADE,audience TEXT NOT NULL DEFAULT 'public' CHECK(audience IN('public','followers')),revision BIGINT NOT NULL DEFAULT 0,edited_at TEXT);
CREATE TABLE IF NOT EXISTS tomi_comment_replies(comment_id TEXT PRIMARY KEY REFERENCES tomi_comments(id) ON DELETE CASCADE,parent_id TEXT NOT NULL REFERENCES tomi_comments(id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS tomi_message_edits(message_id TEXT PRIMARY KEY,edited_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS tomi_message_receipts(message_id TEXT NOT NULL,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,delivered_at TEXT,read_at TEXT,PRIMARY KEY(message_id,user_id));
CREATE TABLE IF NOT EXISTS tomi_lives(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,session_hash TEXT NOT NULL,title TEXT NOT NULL,status TEXT NOT NULL,request_id TEXT NOT NULL,created_at BIGINT NOT NULL,seen_at BIGINT NOT NULL,UNIQUE(user_id,request_id));
CREATE INDEX IF NOT EXISTS tomi_lives_active ON tomi_lives(status,seen_at);
CREATE TABLE IF NOT EXISTS tomi_live_battles(id TEXT PRIMARY KEY,a_id TEXT NOT NULL REFERENCES tomi_lives(id) ON DELETE CASCADE,b_id TEXT NOT NULL REFERENCES tomi_lives(id) ON DELETE CASCADE,mode TEXT NOT NULL CHECK(mode IN('taps','gifts','combined')),state TEXT NOT NULL,created_at BIGINT NOT NULL,ends_at BIGINT NOT NULL,a_score BIGINT NOT NULL DEFAULT 0,b_score BIGINT NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS tomi_live_actions(user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,request_id TEXT NOT NULL,battle_id TEXT NOT NULL REFERENCES tomi_live_battles(id) ON DELETE CASCADE,target_id TEXT NOT NULL,kind TEXT NOT NULL,points BIGINT NOT NULL,created_at BIGINT NOT NULL,PRIMARY KEY(user_id,request_id));
CREATE TABLE IF NOT EXISTS tomi_live_cleanup(room TEXT PRIMARY KEY,created_at BIGINT NOT NULL);

CREATE TABLE IF NOT EXISTS tomi_live_revoke(room TEXT NOT NULL,identity TEXT NOT NULL,created_at BIGINT NOT NULL,PRIMARY KEY(room,identity));

CREATE TABLE IF NOT EXISTS tomi_story_options(story_id TEXT PRIMARY KEY REFERENCES tomi_stories(id) ON DELETE CASCADE,audience TEXT NOT NULL CHECK(audience IN('public','followers')));
CREATE TABLE IF NOT EXISTS tomi_live_watchers(user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,live_id TEXT NOT NULL REFERENCES tomi_lives(id) ON DELETE CASCADE,session_hash TEXT NOT NULL,seen_at BIGINT NOT NULL,PRIMARY KEY(user_id,live_id));

CREATE TABLE IF NOT EXISTS tomi_contact_preferences (
 user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,
 messages TEXT NOT NULL DEFAULT 'everyone' CHECK(messages IN('everyone','following','nobody')),
 calls TEXT NOT NULL DEFAULT 'everyone' CHECK(calls IN('everyone','following','nobody')),
 room_invites TEXT NOT NULL DEFAULT 'everyone' CHECK(room_invites IN('everyone','following','nobody'))
);
CREATE TABLE IF NOT EXISTS tomi_muted_chats (
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,
 thread_id TEXT NOT NULL REFERENCES tomi_chat_threads(id) ON DELETE CASCADE,
 PRIMARY KEY(user_id,thread_id)
);
CREATE TABLE IF NOT EXISTS tomi_video_posters (
 upload_id TEXT PRIMARY KEY REFERENCES tomi_video_uploads(id) ON DELETE CASCADE,
 poster TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tomi_private_video_posters (
 upload_id TEXT PRIMARY KEY REFERENCES tomi_private_uploads(id) ON DELETE CASCADE,
 poster TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tomi_session_devices (
 id TEXT PRIMARY KEY,session_hash TEXT NOT NULL UNIQUE REFERENCES tomi_sessions(token_hash) ON DELETE CASCADE,
 user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,label TEXT NOT NULL,platform TEXT NOT NULL,last_seen_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS tomi_session_devices_user ON tomi_session_devices(user_id);
CREATE TABLE IF NOT EXISTS tomi_saved_collections (
 id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,name TEXT NOT NULL,created_at TEXT NOT NULL,UNIQUE(id,user_id)
);
CREATE TABLE IF NOT EXISTS tomi_collection_items (
 collection_id TEXT NOT NULL,user_id TEXT NOT NULL,post_id TEXT NOT NULL,PRIMARY KEY(collection_id,user_id,post_id),
 FOREIGN KEY(collection_id,user_id) REFERENCES tomi_saved_collections(id,user_id) ON DELETE CASCADE,
 FOREIGN KEY(post_id,user_id) REFERENCES tomi_post_saves(post_id,user_id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS tomi_client_metrics (
 day TEXT NOT NULL,kind TEXT NOT NULL,area TEXT NOT NULL,bucket INTEGER NOT NULL,build INTEGER NOT NULL,total BIGINT NOT NULL,PRIMARY KEY(day,kind,area,bucket,build)
);

-- Build34: personal tools. Trial currency only.
CREATE TABLE IF NOT EXISTS tomi_chat_organisation(user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,thread_id TEXT NOT NULL REFERENCES tomi_chat_threads(id) ON DELETE CASCADE,pinned INTEGER NOT NULL DEFAULT 0,archived INTEGER NOT NULL DEFAULT 0,marked_unread INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(user_id,thread_id));
CREATE TABLE IF NOT EXISTS tomi_explore_preferences(user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,keywords TEXT NOT NULL DEFAULT '[]',topics TEXT NOT NULL DEFAULT '[]');
CREATE TABLE IF NOT EXISTS tomi_explore_hidden(user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,target_type TEXT NOT NULL CHECK(target_type IN('post','user')),target_id TEXT NOT NULL,PRIMARY KEY(user_id,target_type,target_id));
CREATE TABLE IF NOT EXISTS tomi_contact_exceptions(user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,target_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,kind TEXT NOT NULL CHECK(kind IN('messages','calls','roomInvites')),allowed INTEGER NOT NULL,PRIMARY KEY(user_id,target_id,kind));
CREATE TABLE IF NOT EXISTS tomi_support_tickets(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,subject TEXT NOT NULL,body TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'open',reply TEXT NOT NULL DEFAULT '',revision INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,request_id TEXT NOT NULL,UNIQUE(user_id,request_id));
CREATE TABLE IF NOT EXISTS tomi_polls(id TEXT PRIMARY KEY,owner_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,room_id TEXT REFERENCES tomi_voice_rooms(id) ON DELETE CASCADE,question TEXT NOT NULL,options TEXT NOT NULL,ends_at TEXT NOT NULL,created_at TEXT NOT NULL,request_id TEXT NOT NULL,UNIQUE(owner_id,request_id));
CREATE TABLE IF NOT EXISTS tomi_poll_votes(poll_id TEXT NOT NULL REFERENCES tomi_polls(id) ON DELETE CASCADE,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,choice INTEGER NOT NULL,PRIMARY KEY(poll_id,user_id));
CREATE TABLE IF NOT EXISTS tomi_invitations(id TEXT PRIMARY KEY,sender_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,recipient_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,kind TEXT NOT NULL CHECK(kind IN('room','game','live')),target_id TEXT NOT NULL,state TEXT NOT NULL DEFAULT 'pending',created_at TEXT NOT NULL,expires_at TEXT NOT NULL,request_id TEXT NOT NULL,UNIQUE(sender_id,request_id));
CREATE INDEX IF NOT EXISTS tomi_invitations_recipient ON tomi_invitations(recipient_id,expires_at,created_at);
CREATE INDEX IF NOT EXISTS tomi_support_user ON tomi_support_tickets(user_id,created_at);
CREATE INDEX IF NOT EXISTS tomi_polls_room ON tomi_polls(room_id,created_at);
CREATE TABLE IF NOT EXISTS tomi_multipart_uploads(upload_id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,provider_id TEXT NOT NULL,object_key TEXT NOT NULL,completed INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS tomi_group_organisation(user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,group_id TEXT NOT NULL REFERENCES tomi_groups(id) ON DELETE CASCADE,pinned INTEGER NOT NULL DEFAULT 0,archived INTEGER NOT NULL DEFAULT 0,marked_unread INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(user_id,group_id));
CREATE TABLE IF NOT EXISTS tomi_video_jobs(upload_id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,source_table TEXT NOT NULL,object_key TEXT NOT NULL,state TEXT NOT NULL DEFAULT 'pending',attempts INTEGER NOT NULL DEFAULT 0,lease_until BIGINT NOT NULL DEFAULT 0,next_at BIGINT NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS tomi_video_renditions(upload_id TEXT NOT NULL,height INTEGER NOT NULL,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,object_key TEXT NOT NULL,byte_length BIGINT NOT NULL,PRIMARY KEY(upload_id,height));
CREATE TABLE IF NOT EXISTS tomi_notices(id TEXT PRIMARY KEY,recipient_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,actor_id TEXT REFERENCES tomi_users(id) ON DELETE SET NULL,kind TEXT NOT NULL,target_id TEXT NOT NULL,source_key TEXT NOT NULL,created_at TEXT NOT NULL,read_at TEXT,push_state TEXT NOT NULL DEFAULT 'pending',attempts INTEGER NOT NULL DEFAULT 0,next_at TEXT NOT NULL,lease_until TEXT NOT NULL DEFAULT '',UNIQUE(recipient_id,source_key));
CREATE INDEX IF NOT EXISTS tomi_notices_inbox ON tomi_notices(recipient_id,created_at,id);
CREATE TABLE IF NOT EXISTS tomi_notice_receipts(notice_id TEXT NOT NULL REFERENCES tomi_notices(id) ON DELETE CASCADE,token_hash TEXT NOT NULL,PRIMARY KEY(notice_id,token_hash));
CREATE TABLE IF NOT EXISTS tomi_content_preferences(user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,comments TEXT NOT NULL DEFAULT 'everyone',mentions TEXT NOT NULL DEFAULT 'everyone',words TEXT NOT NULL DEFAULT '[]');

CREATE INDEX IF NOT EXISTS tomi_comment_replies_parent ON tomi_comment_replies(parent_id,comment_id);

-- Build41: authenticator secrets encrypted with a server-only key; recovery codes hashed.
CREATE TABLE IF NOT EXISTS tomi_mfa(user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,secret TEXT NOT NULL,enabled INTEGER NOT NULL DEFAULT 0,last_step BIGINT NOT NULL DEFAULT -1,pending_until TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS tomi_mfa_recovery(user_id TEXT NOT NULL REFERENCES tomi_mfa(user_id) ON DELETE CASCADE,code_hash TEXT NOT NULL,PRIMARY KEY(user_id,code_hash));
CREATE TABLE IF NOT EXISTS tomi_mfa_sessions(session_hash TEXT PRIMARY KEY REFERENCES tomi_sessions(token_hash) ON DELETE CASCADE,verified_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS tomi_security_events(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,kind TEXT NOT NULL,created_at TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS tomi_security_events_user ON tomi_security_events(user_id,created_at,id);

-- Build42: opaque direct-chat transport. Private Olm/ratchet/archive keys never enter these tables.
CREATE TABLE IF NOT EXISTS tomi_e2ee_devices(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,session_hash TEXT UNIQUE REFERENCES tomi_sessions(token_hash) ON DELETE SET NULL,signing_key TEXT NOT NULL,identity_key TEXT NOT NULL,label TEXT NOT NULL,created_at TEXT NOT NULL,revoked_at TEXT);
CREATE INDEX IF NOT EXISTS tomi_e2ee_device_user ON tomi_e2ee_devices(user_id,revoked_at);
CREATE TABLE IF NOT EXISTS tomi_e2ee_challenges(session_hash TEXT PRIMARY KEY REFERENCES tomi_sessions(token_hash) ON DELETE CASCADE,nonce_hash TEXT NOT NULL,expires_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS tomi_e2ee_prekeys(device_id TEXT NOT NULL REFERENCES tomi_e2ee_devices(id) ON DELETE CASCADE,key_id TEXT NOT NULL,public_key TEXT NOT NULL,signature TEXT NOT NULL,PRIMARY KEY(device_id,key_id));
CREATE TABLE IF NOT EXISTS tomi_e2ee_fallback(device_id TEXT PRIMARY KEY REFERENCES tomi_e2ee_devices(id) ON DELETE CASCADE,key_id TEXT NOT NULL,public_key TEXT NOT NULL,signature TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS tomi_e2ee_threads(thread_id TEXT PRIMARY KEY REFERENCES tomi_chat_threads(id) ON DELETE CASCADE,enabled_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS tomi_e2ee_packets(message_id TEXT PRIMARY KEY REFERENCES tomi_chat_messages(id) ON DELETE CASCADE,sender_device TEXT REFERENCES tomi_e2ee_devices(id) ON DELETE SET NULL,roster_hash TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS tomi_e2ee_envelopes(message_id TEXT NOT NULL REFERENCES tomi_e2ee_packets(message_id) ON DELETE CASCADE,device_id TEXT NOT NULL REFERENCES tomi_e2ee_devices(id) ON DELETE CASCADE,body TEXT NOT NULL,type INTEGER NOT NULL,PRIMARY KEY(message_id,device_id));
CREATE TABLE IF NOT EXISTS tomi_e2ee_claims(device_id TEXT NOT NULL REFERENCES tomi_e2ee_devices(id) ON DELETE CASCADE,request_id TEXT NOT NULL,target_device TEXT NOT NULL REFERENCES tomi_e2ee_devices(id) ON DELETE CASCADE,result TEXT NOT NULL,created_at TEXT NOT NULL,PRIMARY KEY(device_id,request_id));
CREATE TABLE IF NOT EXISTS tomi_e2ee_uploads(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,thread_id TEXT NOT NULL REFERENCES tomi_chat_threads(id) ON DELETE CASCADE,message_id TEXT REFERENCES tomi_chat_messages(id) ON DELETE SET NULL,object_key TEXT NOT NULL,byte_length BIGINT NOT NULL,content_md5 TEXT NOT NULL,content_sha256 TEXT NOT NULL,state TEXT NOT NULL DEFAULT 'pending',expires_at TEXT NOT NULL);

-- Verified external identity is keyed by project + Firebase UID, never by email/name/phone.
CREATE TABLE IF NOT EXISTS tomi_external_identities(project_id TEXT NOT NULL,subject TEXT NOT NULL,user_id TEXT NOT NULL REFERENCES tomi_users(id) ON DELETE CASCADE,created_at TEXT NOT NULL,PRIMARY KEY(project_id,subject));
CREATE INDEX IF NOT EXISTS tomi_external_user ON tomi_external_identities(user_id);
CREATE TABLE IF NOT EXISTS tomi_account_auth(user_id TEXT PRIMARY KEY REFERENCES tomi_users(id) ON DELETE CASCADE,password_enabled INTEGER NOT NULL DEFAULT 1);
