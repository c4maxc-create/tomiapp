import 'package:tomi_app/src/accounts/account_controller.dart';

class MemoryTokenVault implements TokenVault {
  MemoryTokenVault([this.token]);
  String? token;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String value) async { token = value; }
  @override
  Future<void> clear() async { token = null; }
}

Map<String, dynamic> accountJson({String id = '11111111-1111-4111-8111-111111111111',
    String username = 'tolo', String name = 'تولو', String bio = 'نبذة محفوظة',
    int followers = 0, int following = 0, bool isFollowing = false}) => {
  'id': id, 'username': username, 'displayName': name, 'bio': bio,
  'avatarPreset': 'panda', 'followersCount': followers, 'followingCount': following,
  'postsCount': 0, 'isFollowing': isFollowing,
};
