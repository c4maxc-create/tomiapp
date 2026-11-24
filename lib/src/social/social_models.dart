import 'package:connectivity_plus/connectivity_plus.dart';
import '../preferences/media_preferences.dart';
import '../identity/identity_models.dart';

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../accounts/account_models.dart';

String newRequestId() {
  final b = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return h.substring(0, 8) +
      '-' +
      h.substring(8, 12) +
      '-' +
      h.substring(12, 16) +
      '-' +
      h.substring(16, 20) +
      '-' +
      h.substring(20);
}

class PostAuthor {
  const PostAuthor({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarPreset,
    this.storyExpiresAt,
    this.avatarUrl,
    this.avatarId,
    this.identity = const UserIdentity(),
  });
  final String id, username, displayName, avatarPreset;
  final String? avatarUrl, avatarId;
  final DateTime? storyExpiresAt;
  bool get hasStory => storyExpiresAt?.isAfter(DateTime.now()) ?? false;
  final UserIdentity identity;
  factory PostAuthor.fromJson(Map<String, dynamic> d) => PostAuthor(
    id: d['id'] as String,
    username: d['username'] as String,
    displayName: d['displayName'] as String,
    avatarPreset: d['avatarPreset'] as String,
    avatarUrl: d['avatarUrl'] as String?,
    avatarId: d['avatarId'] as String?,
    storyExpiresAt: DateTime.tryParse(d['storyExpiresAt'] as String? ?? ''),
    identity: UserIdentity(d['identity'] as Map<String, dynamic>? ?? const {}),
  );
  AccountUser get avatarUser => AccountUser(
    id: id,
    username: username,
    displayName: displayName,
    bio: '',
    avatarPreset: avatarPreset,
    avatarUrl: avatarUrl,
    avatarId: avatarId,
    storyExpiresAt: storyExpiresAt,
    identity: identity,
    followersCount: 0,
    followingCount: 0,
  );
}

class PostImage {
  const PostImage({this.url, required this.width, required this.height});
  final String? url;
  final int width, height;
  factory PostImage.fromJson(Map<String, dynamic> d) => PostImage(
    url: d['url'] as String?,
    width: (d['width'] as num).toInt(),
    height: (d['height'] as num).toInt(),
  );
}

class SocialPost {
  const SocialPost({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.author,
    this.image,
    this.video,
    this.saved = false,
    this.audience = 'public',
    this.revision = 0,
    required this.likesCount,
    required this.commentsCount,
    required this.liked,
    required this.isMine,
  });
  final String id, text;
  final DateTime createdAt;
  final PostAuthor author;
  final PostImage? image;
  final PostVideo? video;
  final int likesCount, commentsCount;
  final bool liked, isMine, saved;
  final String audience;
  final int revision;
  factory SocialPost.fromJson(Map<String, dynamic> d) => SocialPost(
    id: d['id'] as String,
    text: d['text'] as String,
    createdAt: DateTime.parse(d['createdAt'] as String),
    author: PostAuthor.fromJson(d['author'] as Map<String, dynamic>),
    image: d['image'] == null
        ? null
        : PostImage.fromJson(d['image'] as Map<String, dynamic>),
    video: d['video'] == null
        ? null
        : PostVideo(d['video'] as Map<String, dynamic>),
    likesCount: (d['likesCount'] as num).toInt(),
    commentsCount: (d['commentsCount'] as num).toInt(),
    saved: d['saved'] == true,
    audience: d['audience'] as String? ?? 'public',
    revision: (d['revision'] as num?)?.toInt() ?? 0,
    liked: d['liked'] as bool,
    isMine: d['isMine'] as bool,
  );
}

class SocialComment {
  const SocialComment({
    this.parentId,
    this.rootId,
    this.replyCount = 0,
    this.replyToName,
    this.replyToUsername,
    required this.id,
    required this.text,
    required this.createdAt,
    required this.author,
    required this.isMine,
  });
  final String id, text;
  final String? parentId, rootId, replyToName, replyToUsername;
  final int replyCount;
  final DateTime createdAt;
  final PostAuthor author;
  final bool isMine;
  factory SocialComment.fromJson(Map<String, dynamic> d) => SocialComment(
    parentId: d['parentId'] as String?,
    rootId: d['rootId'] as String?,
    replyCount: (d['replyCount'] as num?)?.toInt() ?? 0,
    replyToName: d['replyToName'] as String?,
    replyToUsername: d['replyToUsername'] as String?,
    id: d['id'] as String,
    text: d['text'] as String,
    createdAt: DateTime.parse(d['createdAt'] as String),
    author: PostAuthor.fromJson(d['author'] as Map<String, dynamic>),
    isMine: d['isMine'] as bool,
  );
}

class FeedPage {
  const FeedPage({
    required this.posts,
    this.nextCursor,
    this.imageUploadEnabled = false,
    this.videoUploadEnabled = false,
  });
  final List<SocialPost> posts;
  final String? nextCursor;
  final bool imageUploadEnabled, videoUploadEnabled;
  factory FeedPage.fromJson(Map<String, dynamic> d) => FeedPage(
    posts: (d['posts'] as List)
        .map((p) => SocialPost.fromJson(p as Map<String, dynamic>))
        .toList(),
    nextCursor: d['nextCursor'] as String?,
    imageUploadEnabled: d['imageUploadEnabled'] as bool? ?? false,
    videoUploadEnabled: d['videoUploadEnabled'] == true,
  );
}

class CommentPage {
  const CommentPage({
    required this.comments,
    this.nextCursor,
    this.threaded = false,
    this.root,
  });
  final List<SocialComment> comments;
  final bool threaded;
  final SocialComment? root;
  final String? nextCursor;
  factory CommentPage.fromJson(Map<String, dynamic> d) => CommentPage(
    threaded: d['threaded'] == true,
    root: d['root'] is Map
        ? SocialComment.fromJson((d['root'] as Map).cast<String, dynamic>())
        : null,
    comments: (d['comments'] as List)
        .map((p) => SocialComment.fromJson(p as Map<String, dynamic>))
        .toList(),
    nextCursor: d['nextCursor'] as String?,
  );
}

class PublishResult {
  const PublishResult({required this.post, required this.user});
  final SocialPost post;
  final AccountUser user;
}

class CommentResult {
  const CommentResult({required this.comment, required this.post});
  final SocialComment comment;
  final SocialPost post;
}

class ImageDraft {
  ImageDraft(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
  late final String contentMd5 = base64Encode(md5.convert(bytes).bytes);
  late final String contentSha256 = sha256.convert(bytes).toString();
}

class VideoDraft extends ImageDraft {
  VideoDraft(
    Uint8List bytes, {
    required this.durationMs,
    required this.width,
    required this.height,
    this.poster,
  }) : super(bytes, 'video/mp4');
  final String? poster;
  late final Uint8List? posterBytes = _decodePoster();
  Uint8List? _decodePoster() {
    final raw = poster;
    if (raw == null ||
        raw.length > 44000 ||
        !raw.startsWith('data:image/png;base64,'))
      return null;
    try {
      return base64Decode(raw.substring(22));
    } catch (_) {
      return null;
    }
  }

  final int durationMs, width, height;
}

class PostVideo {
  PostVideo(this.data);
  Future<String?> playbackUrl() async {
    final preferences = MediaPreferences.instance;
    await preferences.restore();
    final variants = (data['renditions'] as List? ?? []).cast<Map>();
    if (variants.isEmpty || !preferences.smartQuality && !preferences.dataSaver)
      return url;
    bool low = preferences.dataSaver;
    if (preferences.smartQuality) {
      try {
        final c = await Connectivity().checkConnectivity();
        low =
            low ||
            !c.contains(ConnectivityResult.wifi) &&
                !c.contains(ConnectivityResult.ethernet);
      } catch (_) {
        low = true;
      }
    }
    final target = low ? 540 : 720;
    return variants.where((v) => v['height'] == target).firstOrNull?['url']
            as String? ??
        url;
  }

  final Map<String, dynamic> data;
  String? get url => data['url'] as String?;
  String? get poster => data['poster'] as String?;
  static final decodedPosters = Expando<Uint8List>();
  Uint8List? get posterBytes {
    final raw = poster;
    if (raw == null ||
        raw.length > 44000 ||
        !raw.startsWith('data:image/png;base64,'))
      return null;
    try {
      return decodedPosters[data] ??= base64Decode(raw.substring(22));
    } catch (_) {
      return null;
    }
  }

  int get width => (data['width'] as num).toInt();
  int get height => (data['height'] as num).toInt();
  int get durationMs => (data['durationMs'] as num).toInt();
}

class ImageUpload {
  const ImageUpload({
    required this.id,
    required this.url,
    required this.headers,
    this.resumablePath,
  });
  final String id;
  final String? resumablePath;
  final Uri url;
  final Map<String, String> headers;
  Map<String, dynamic> toJson() => {
    'uploadId': id,
    'uploadUrl': url.toString(),
    'headers': headers,
    if (resumablePath != null) 'resumablePath': resumablePath,
  };
  factory ImageUpload.fromJson(Map<String, dynamic> d) => ImageUpload(
    id: d['uploadId'] as String,
    resumablePath: d['resumablePath'] as String?,
    url: Uri.parse(d['uploadUrl'] as String),
    headers: (d['headers'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, v as String),
    ),
  );
}
