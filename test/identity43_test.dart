import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:tomi_app/src/accounts/external_identity.dart';

void main() {
  test(
    '43 Google configuration failures identify outdated APK without exposing SDK details',
    () {
      final missing = ExternalIdentity.message(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError,
          description:
              'CredentialManager requires a serverClientId. fake-sensitive-details',
        ),
      );
      expect(missing, contains('حدّث التطبيق'));
      expect(missing, isNot(contains('fake-sensitive-details')));
      final wrong = ExternalIdentity.message(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError,
          description: 'DEVELOPER_ERROR fake-sensitive-details',
        ),
      );
      expect(wrong, contains('بصمة'));
      expect(wrong, isNot(contains('fake-sensitive-details')));
      expect(
        ExternalIdentity.message(
          const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
        ),
        contains('أُلغي'),
      );
    },
  );
}
