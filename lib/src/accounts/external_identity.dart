import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart' as fb;
import 'account_api.dart';

class ExternalIdentity {
  static Future<void>? _google;
  static Future<void> ensure(String? project) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS))
      throw const AccountFailure(
        'IDENTITY_PLATFORM',
        'سجّل بهذه الطرق من نسخة الهاتف.',
      );
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    } catch (_) {
      throw const AccountFailure(
        'IDENTITY_CONFIG',
        'إعداد Firebase للتطبيق غير مكتمل لدى الإدارة.',
      );
    }
    if (project == null || Firebase.app().options.projectId != project)
      throw const AccountFailure(
        'IDENTITY_PROJECT',
        'إعدادات Firebase بالخادم والتطبيق غير متطابقة.',
      );
  }

  static String message(Object e) {
    if (e is AccountFailure) return e.message;
    if (e is GoogleSignInException) {
      return switch (e.code) {
        GoogleSignInExceptionCode.clientConfigurationError =>
          e.description?.contains('serverClientId') == true
              ? 'إعداد Google غير موجود داخل هذه النسخة. حدّث التطبيق إلى النسخة الجديدة.'
              : 'إعداد Google أو بصمة توقيع هذه النسخة غير مطابق. راجع إعدادات النسخة لدى الإدارة.',
        GoogleSignInExceptionCode.providerConfigurationError =>
          'خدمة Google غير جاهزة؛ تحقق من خدمات Google Play وإعداد المزوّد.',
        GoogleSignInExceptionCode.canceled => 'أُلغي اختيار حساب Google.',
        GoogleSignInExceptionCode.interrupted =>
          'انقطع اختيار حساب Google؛ جرّب مجدداً.',
        GoogleSignInExceptionCode.uiUnavailable =>
          'تعذّر فتح نافذة Google؛ أعد فتح التطبيق وجرّب مجدداً.',
        GoogleSignInExceptionCode.userMismatch =>
          'اختَر حساب Google المرتبط بنفس حسابك.',
        _ =>
          'تعذّر الدخول عبر Google (${e.code.name})؛ تحقق من الاتصال وجرّب مجدداً.',
      };
    }

    if (e is FirebaseAuthException)
      return switch (e.code) {
        'operation-not-allowed' => 'طريقة الدخول تحتاج تفعيلها من Firebase.',
        'account-exists-with-different-credential' =>
          'الحساب موجود بطريقة دخول أخرى؛ استخدمها ثم اربط الطرق من الإعدادات.',
        'credential-already-in-use' => 'طريقة الدخول مرتبطة بحساب آخر.',
        'user-mismatch' => 'اختَر طريقة الدخول الخاصة بنفس حسابك.',
        'invalid-verification-code' => 'رمز التحقق غير صحيح.',
        'session-expired' => 'انتهى رمز التحقق؛ اطلب رمزاً جديداً.',
        'too-many-requests' => 'محاولات كثيرة؛ انتظر قبل إعادة المحاولة.',
        'quota-exceeded' => 'حصة رسائل التحقق غير متاحة حالياً لدى الإدارة.',
        'invalid-phone-number' => 'اكتب الرقم بالصيغة الدولية، مثل +964…',
        'app-not-authorized' =>
          'تحتاج الإدارة تسجيل بصمة نسخة التطبيق في Firebase.',
        'network-request-failed' => 'تعذّر الاتصال؛ تحقق من الإنترنت.',
        _ => 'تعذّر إكمال الدخول مع المزوّد.',
      };
    return 'تعذّر إكمال الدخول؛ تحقق من إعدادات المزوّد أو جرّب مجدداً.';
  }

  static Future<String> authenticate(
    String provider, {
    bool reauth = false,
    bool link = false,
  }) async {
    try {
      final auth = FirebaseAuth.instance;
      final current = auth.currentUser;
      UserCredential result;
      if (provider == 'apple') {
        final p = AppleAuthProvider()
          ..addScope('email')
          ..addScope('name');
        result = reauth
            ? await current!.reauthenticateWithProvider(p)
            : link && current != null
            ? await current.linkWithProvider(p)
            : await auth.signInWithProvider(p);
      } else {
        AuthCredential credential;
        if (provider == 'google') {
          try {
            await (_google ??= GoogleSignIn.instance.initialize());
          } catch (_) {
            _google = null;
            rethrow;
          }
          final account = await GoogleSignIn.instance.authenticate();
          final token = account.authentication.idToken;
          if (token == null)
            throw const AccountFailure(
              'GOOGLE_CONFIG',
              'تحتاج إعداد OAuth وبصمة التطبيق لدى الإدارة.',
            );
          credential = GoogleAuthProvider.credential(idToken: token);
        } else if (provider == 'facebook') {
          final random = Random.secure(),
              nonce = base64UrlEncode(
                List.generate(32, (_) => random.nextInt(256)),
              ).replaceAll('=', '');
          final result = await fb.FacebookAuth.instance.login(
            permissions: const ['public_profile', 'email'],
            loginTracking: Platform.isIOS
                ? fb.LoginTracking.limited
                : fb.LoginTracking.enabled,
            nonce: sha256.convert(utf8.encode(nonce)).toString(),
          );
          if (result.status == fb.LoginStatus.cancelled)
            throw const AccountFailure('CANCELLED', 'أُلغي تسجيل الدخول.');
          final token = result.accessToken;
          if (result.status != fb.LoginStatus.success || token == null)
            throw const AccountFailure(
              'FACEBOOK_CONFIG',
              'تعذّر دخول Facebook؛ راجع إعداد التطبيق لدى الإدارة.',
            );
          credential = token is fb.LimitedToken
              ? OAuthProvider(
                  'facebook.com',
                ).credential(idToken: token.tokenString, rawNonce: nonce)
              : FacebookAuthProvider.credential(token.tokenString);
        } else {
          throw const AccountFailure(
            'IDENTITY_PROVIDER',
            'طريقة الدخول غير مدعومة.',
          );
        }
        result = reauth
            ? await current!.reauthenticateWithCredential(credential)
            : link && current != null
            ? await current.linkWithCredential(credential)
            : await auth.signInWithCredential(credential);
      }
      final token = await result.user?.getIdToken(true);
      if (token == null)
        throw const AccountFailure('IDENTITY_TOKEN', 'تعذّر تأكيد الدخول.');
      return token;
    } catch (e) {
      if (e is AccountFailure) rethrow;
      throw AccountFailure('IDENTITY_PROVIDER', message(e));
    }
  }

  static Future<void> signOut() async {
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    try {
      if (_google != null) await GoogleSignIn.instance.signOut();
    } catch (_) {}
    try {
      await fb.FacebookAuth.instance.logOut();
    } catch (_) {}
  }
}
