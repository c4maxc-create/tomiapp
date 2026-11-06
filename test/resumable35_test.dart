import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/social/social_models.dart';

void main() {
  test(
    'multipart retry skips committed parts, preserves bytes and never sends account tokens to storage',
    () async {
      const chunk = 5 * 1024 * 1024,
          id = '11111111-1111-4111-8111-111111111111',
          path = '/v1/media/resumable/image_uploads/$id';
      int first = 0, second = 0, finished = 0;
      bool stored = false, lost = true;
      final client = MockClient((r) async {
        if (r.url.host == 'api.example.com') {
          expect(r.headers['authorization'], 'Bearer private-token');
          if (r.url.path.endsWith('/complete')) {
            finished++;
            return http.Response('{"completed":true}', 200);
          }
          return http.Response(
            jsonEncode({
              'completed': false,
              'chunkSize': chunk,
              'total': chunk + 1000,
              'parts': [
                {
                  'number': 1,
                  'size': chunk,
                  'uploaded': stored,
                  'url':
                      'https://bucket.r2.cloudflarestorage.com/file?partNumber=1',
                },
                {
                  'number': 2,
                  'size': 1000,
                  'uploaded': false,
                  'url':
                      'https://bucket.r2.cloudflarestorage.com/file?partNumber=2',
                },
              ],
            }),
            200,
          );
        }
        expect(r.headers.containsKey('authorization'), false);
        if (r.url.queryParameters['partNumber'] == '1') {
          first++;
          expect(r.bodyBytes.length, chunk);
          stored = true;
        } else {
          second++;
          expect(r.bodyBytes.length, 1000);
          if (lost) {
            lost = false;
            throw http.ClientException('network lost');
          }
        }
        return http.Response('', 200);
      });
      final api = AccountApi('https://api.example.com', client: client),
          image = ImageDraft(Uint8List(chunk + 1000), 'image/jpeg'),
          upload = ImageUpload(
            id: id,
            url: Uri.parse('https://bucket.r2.cloudflarestorage.com/file'),
            headers: {},
            resumablePath: path,
          );
      await expectLater(
        api.uploadResumable('private-token', upload, image),
        throwsA(isA<AccountFailure>()),
      );
      await api.uploadResumable('private-token', upload, image);
      expect(first, 1);
      expect(second, 2);
      expect(finished, 1);
    },
  );
  test(
    'invalid resumable plan cannot redirect media to an arbitrary host',
    () async {
      final api = AccountApi(
        'https://api.example.com',
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({
              'completed': false,
              'chunkSize': 5 * 1024 * 1024,
              'total': 5 * 1024 * 1024 + 1,
              'parts': [
                {
                  'number': 1,
                  'size': 5 * 1024 * 1024,
                  'uploaded': false,
                  'url': 'https://attacker.example/file',
                },
                {
                  'number': 2,
                  'size': 1,
                  'uploaded': false,
                  'url': 'https://attacker.example/file',
                },
              ],
            }),
            200,
          ),
        ),
      );
      await expectLater(
        api.uploadResumable(
          'token',
          ImageUpload(
            id: '11111111-1111-4111-8111-111111111111',
            url: Uri.parse('https://bucket.r2.cloudflarestorage.com/file'),
            headers: {},
            resumablePath:
                '/v1/media/resumable/image_uploads/11111111-1111-4111-8111-111111111111',
          ),
          ImageDraft(Uint8List(5 * 1024 * 1024 + 1), 'image/jpeg'),
        ),
        throwsA(isA<AccountFailure>()),
      );
    },
  );
}
