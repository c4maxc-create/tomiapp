import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/preferences/media_preferences.dart';
import 'package:tomi_app/src/social/social_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('data saver selects the 144p rendition without checking connectivity', () async {
    final preferences = MediaPreferences.instance;
    preferences
      ..loaded = true
      ..dataSaver = true
      ..smartQuality = false;
    final video = PostVideo({
      'url': 'https://media.example/original.mp4',
      'renditions': [
        {'height': 144, 'url': 'https://media.example/144.mp4'},
        {'height': 540, 'url': 'https://media.example/540.mp4'},
        {'height': 720, 'url': 'https://media.example/720.mp4'},
      ],
    });

    expect(await video.playbackUrl(), 'https://media.example/144.mp4');

    preferences
      ..dataSaver = false
      ..smartQuality = true;
  });
}
