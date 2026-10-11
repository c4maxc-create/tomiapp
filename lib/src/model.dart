import 'package:flutter/foundation.dart';

class DemoPost {
  DemoPost({
    required this.id,
    required this.name,
    required this.username,
    required this.text,
    this.kind = 'text',
    this.likes = 0,
    this.verified = false,
    this.isMine = false,
  });

  final int id;
  final String name;
  final String username;
  final String text;
  final String kind;
  final bool verified;
  final bool isMine;
  int likes;
  bool liked = false;
  bool saved = false;
  final List<String> comments = [];
}

class DemoMessage {
  const DemoMessage(this.text, {this.mine = false});
  final String text;
  final bool mine;
}

class DemoChat {
  DemoChat(this.name, this.username, this.messages, {this.unread = 0});
  final String name;
  final String username;
  final List<DemoMessage> messages;
  int unread;
}

class DemoRoom {
  const DemoRoom(this.title, this.topic, this.people, this.symbol);
  final String title;
  final String topic;
  final int people;
  final String symbol;
}

class TomiStore extends ChangeNotifier {
  String displayName = 'تولو';
  String username = 'tolo';
  String bio = 'لحظات جميلة، سوالف قريبة، ولعب يجمعنا.';
  int coins = 2500;
  int charisma = 280;
  int xp = 950;
  final Set<String> following = {'ali'};
  final List<String> myStories = [];
  int _nextPostId = 4;
  int get level => 1 + xp ~/ 100;
  double get levelProgress => (xp % 100) / 100;

  final List<DemoPost> posts = [
    DemoPost(
      id: 1,
      name: 'TOMI',
      username: 'tomi',
      verified: true,
      text: 'أهلًا بيكم في تومي ✨ مكان يجمع لحظاتكم، أصدقاءكم، وألعابكم.',
      kind: 'photo',
      likes: 128,
    ),
    DemoPost(
      id: 2,
      name: 'علي',
      username: 'ali',
      text: 'الليلة جمعتنا حلوة. منو يشاركنا التحدّي؟ 🎮',
      kind: 'video',
      likes: 86,
    ),
    DemoPost(
      id: 3,
      name: 'فاطمة',
      username: 'fatima',
      text: 'شنو أجمل شي صار وياكم اليوم؟ خلّونا نتشارك الأشياء الحلوة 💜',
      likes: 42,
    ),
  ];

  final List<DemoChat> chats = [
    DemoChat('علي', 'ali', [
      const DemoMessage('هلا تولو، شلونك؟'),
      const DemoMessage('هلا بيك، تمام الحمد لله 💜', mine: true),
      const DemoMessage('نشوفك بغرفة الأصدقاء الليلة؟'),
    ], unread: 2),
    DemoChat('فاطمة', 'fatima', [
      const DemoMessage('واجهة تومي الجديدة حلوة ✨'),
    ], unread: 1),
    DemoChat('أصدقاء TOMI', 'friends', [
      const DemoMessage('محمد: يلا نجرّب تحدّي الأسئلة!'),
    ]),
  ];

  static const rooms = [
    DemoRoom('سوالف الأصدقاء', 'دردشة • العراق', 24, '💜'),
    DemoRoom('ليلة ألعاب', 'ألعاب • تحدّيات', 16, '🎮'),
    DemoRoom('قهوة وموسيقى', 'استرخاء • موسيقى', 38, '☕'),
    DemoRoom('أهلًا بالكل', 'تعارف • سوالف', 12, '✨'),
  ];

  void toggleLike(DemoPost post) {
    post.liked = !post.liked;
    post.likes += post.liked ? 1 : -1;
    notifyListeners();
  }

  void toggleSave(DemoPost post) {
    post.saved = !post.saved;
    notifyListeners();
  }

  void toggleFollow(String target) {
    if (!following.add(target)) following.remove(target);
    notifyListeners();
  }

  void addComment(DemoPost post, String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    post.comments.add(clean);
    notifyListeners();
  }

  void addPost(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    posts.insert(0, DemoPost(
      id: _nextPostId++, name: displayName, username: username, text: clean, isMine: true,
    ));
    notifyListeners();
  }

  void addStory(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    myStories.insert(0, clean);
    notifyListeners();
  }

  void markRead(DemoChat chat) {
    chat.unread = 0;
    notifyListeners();
  }

  void sendMessage(DemoChat chat, String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    chat.messages.add(DemoMessage(clean, mine: true));
    notifyListeners();
  }

  bool sendGift({required int price, required int charismaPoints, required bool toSelf}) {
    if (price <= 0 || charismaPoints < 0 || coins < price) return false;
    coins -= price;
    if (toSelf) charisma += charismaPoints;
    notifyListeners();
    return true;
  }

  void addDemoCoins() {
    coins += 1000;
    notifyListeners();
  }

  void awardQuizXp(int points) {
    xp += points;
    notifyListeners();
  }

  void updateProfile(String name, String handle, String about) {
    displayName = name.trim();
    username = handle.trim().toLowerCase();
    bio = about.trim();
    notifyListeners();
  }
}
