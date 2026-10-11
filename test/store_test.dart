import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/model.dart';

void main() {
  test('like toggle restores the original count', () {
    final store = TomiStore();
    addTearDown(store.dispose);
    final post = store.posts.first;
    final initial = post.likes;
    store.toggleLike(post);
    expect(post.liked, isTrue);
    expect(post.likes, initial + 1);
    store.toggleLike(post);
    expect(post.likes, initial);
  });

  test('blank input cannot create a post, comment, story, or message', () {
    final store = TomiStore();
    addTearDown(store.dispose);
    final posts = store.posts.length;
    final messages = store.chats.first.messages.length;
    store.addPost('  ');
    store.addComment(store.posts.first, '  ');
    store.addStory('  ');
    store.sendMessage(store.chats.first, '  ');
    expect(store.posts.length, posts);
    expect(store.posts.first.comments, isEmpty);
    expect(store.myStories, isEmpty);
    expect(store.chats.first.messages.length, messages);
  });

  test('profile edits do not lose ownership of existing posts', () {
    final store = TomiStore();
    addTearDown(store.dispose);
    store.addPost('منشوري التجريبي');
    store.updateProfile('تولو الجديد', 'tolo_new', 'مرحبًا');
    expect(store.posts.where((post) => post.isMine).length, 1);
  });

  test('gifts never produce a negative balance and XP stays separate', () {
    final store = TomiStore();
    addTearDown(store.dispose);
    final charisma = store.charisma;
    final xp = store.xp;
    expect(store.sendGift(price: 1000, charismaPoints: 120, toSelf: true), isTrue);
    expect(store.coins, 1500);
    expect(store.charisma, charisma + 120);
    expect(store.xp, xp);
    expect(store.sendGift(price: 2000, charismaPoints: 100, toSelf: true), isFalse);
    expect(store.coins, 1500);
    expect(store.sendGift(price: 500, charismaPoints: 50, toSelf: false), isTrue);
    expect(store.charisma, charisma + 120);
    final coins = store.coins;
    store.awardQuizXp(100);
    expect(store.coins, coins);
    expect(store.level, 11);
  });
}
