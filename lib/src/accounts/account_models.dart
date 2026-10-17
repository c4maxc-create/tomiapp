import '../identity/identity_models.dart';

class AccountUser {
  const AccountUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.bio,
    required this.avatarPreset,
    required this.followersCount,
    required this.followingCount,
    this.postsCount = 0,
    this.isFollowing = false,
    this.avatarUrl,
    this.avatarId,
    this.identity = const UserIdentity(),
  });

  final String id;
  final String username;
  final String displayName;
  final String bio;
  final String avatarPreset;
  final String? avatarUrl, avatarId;
  final UserIdentity identity;
  final int followersCount;
  final int followingCount;
  final int postsCount;
  final bool isFollowing;

  AccountUser withIdentity(UserIdentity value) => AccountUser(
    id: id,
    username: username,
    displayName: displayName,
    bio: bio,
    avatarPreset: avatarPreset,
    avatarUrl: avatarUrl,
    avatarId: avatarId,
    followersCount: followersCount,
    followingCount: followingCount,
    postsCount: postsCount,
    isFollowing: isFollowing,
    identity: value,
  );

  factory AccountUser.fromJson(Map<String, dynamic> json) => AccountUser(
    id: json['id'] as String,
    username: json['username'] as String,
    displayName: json['displayName'] as String,
    bio: json['bio'] as String,
    avatarPreset: json['avatarPreset'] as String,
    avatarUrl: json['avatarUrl'] as String?,
    avatarId: json['avatarId'] as String?,
    identity: UserIdentity(
      json['identity'] as Map<String, dynamic>? ?? const {},
    ),
    followersCount: (json['followersCount'] as num).toInt(),
    followingCount: (json['followingCount'] as num).toInt(),
    postsCount: (json['postsCount'] as num?)?.toInt() ?? 0,
    isFollowing: json['isFollowing'] as bool? ?? false,
  );
}

class AccountGrant {
  const AccountGrant({
    required this.token,
    required this.user,
    this.recoveryCode,
  });
  final String token;
  final AccountUser user;
  final String? recoveryCode;

  factory AccountGrant.fromJson(Map<String, dynamic> json) => AccountGrant(
    token: json['token'] as String,
    user: AccountUser.fromJson(json['user'] as Map<String, dynamic>),
    recoveryCode: json['recoveryCode'] as String?,
  );
}

class FollowResult {
  const FollowResult({required this.user, required this.me});
  final AccountUser user;
  final AccountUser me;
}

const avatarSymbols = <String, String>{
  'initials': '',
  'moon': '🌙',
  'cat': '🐱',
  'fox': '🦊',
  'panda': '🐼',
  'robot': '🤖',
  'flower': '🌸',
  'star': '⭐',
};
