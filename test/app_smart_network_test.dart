import 'package:app_smart_network/app_smart_network.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── NetworkLocale ──────────────────────────────────────────────────────────

  group('NetworkLocale', () {
    setUp(() => NetworkLocale.setLocale('en'));

    test('defaults to English', () {
      expect(NetworkLocale.current, 'en');
      expect(
        NetworkLocale.getErrorMessage('NoInternetConnection'),
        'No internet connection.',
      );
    });

    test('switches to Arabic', () {
      NetworkLocale.setLocale('ar');
      expect(NetworkLocale.current, 'ar');
      expect(
        NetworkLocale.getErrorMessage('NoInternetConnection'),
        'لا يوجد اتصال بالإنترنت.',
      );
    });

    test('strips region tag from locale (en-US → en)', () {
      NetworkLocale.setLocale('en-US');
      expect(NetworkLocale.current, 'en');
    });

    test('falls back to English for unknown locale', () {
      NetworkLocale.setLocale('zz');
      expect(
        NetworkLocale.getErrorMessage('NoInternetConnection'),
        'No internet connection.',
      );
    });

    test('returns status message for known code', () {
      expect(NetworkLocale.getStatusMessage(404), 'Resource not found.');
    });

    test('builds default 4xx message when code is unknown', () {
      final msg = NetworkLocale.getStatusMessage(499);
      expect(msg, contains('499'));
    });

    test('custom translations override built-ins', () {
      NetworkLocale.addTranslations('en', {
        'NoInternetConnection': 'Custom offline message.',
      });
      expect(
        NetworkLocale.getErrorMessage('NoInternetConnection'),
        'Custom offline message.',
      );
      // Restore
      NetworkLocale.addTranslations('en', {
        'NoInternetConnection': 'No internet connection.',
      });
    });

    test('custom translations for new locale fall back to English for missing keys', () {
      NetworkLocale.addTranslations('fr', {
        'NoInternetConnection': 'Pas de connexion.',
      });
      NetworkLocale.setLocale('fr');
      expect(
        NetworkLocale.getErrorMessage('NoInternetConnection'),
        'Pas de connexion.',
      );
      // Key not in 'fr' → falls back to English
      expect(
        NetworkLocale.getErrorMessage('RequestCancelled'),
        'Request was cancelled.',
      );
    });
  });

  // ── ApiException ───────────────────────────────────────────────────────────

  group('ApiException', () {
    test('status helpers', () {
      expect(const ApiException('msg', 200).isClientError, isFalse);
      expect(const ApiException('msg', 400).isClientError, isTrue);
      expect(const ApiException('msg', 401).isUnauthorized, isTrue);
      expect(const ApiException('msg', 403).isForbidden, isTrue);
      expect(const ApiException('msg', 404).isNotFound, isTrue);
      expect(const ApiException('msg', 422).isValidationError, isTrue);
      expect(const ApiException('msg', 429).isRateLimited, isTrue);
      expect(const ApiException('msg', 500).isServerError, isTrue);
      expect(const ApiException('msg', 0).isNetworkError, isTrue);
    });

    test('hasApiErrorCode', () {
      const e = ApiException('msg', 400, apiErrorCode: 'UserExists');
      expect(e.hasApiErrorCode('UserExists'), isTrue);
      expect(e.hasApiErrorCode('Other'), isFalse);
    });

    test('getResponseField returns typed value', () {
      const e = ApiException(
        'msg',
        422,
        responseData: {'errors': ['field required']},
      );
      expect(e.getResponseField<List>('errors'), ['field required']);
      expect(e.getResponseField<String>('missing'), isNull);
    });

    test('toString includes apiErrorCode when present', () {
      const e = ApiException('Bad', 400, apiErrorCode: 'UserExists');
      expect(e.toString(), contains('Code: UserExists'));
    });
  });

  // ── Failures ───────────────────────────────────────────────────────────────

  group('ServerFailure', () {
    test('fromException maps fields correctly', () {
      const exception = ApiException(
        'Not found',
        404,
        apiErrorCode: 'ResourceMissing',
      );
      final failure = ServerFailure.fromException(exception);
      expect(failure.message, 'Not found');
      expect(failure.code, 404);
      expect(failure.apiErrorCode, 'ResourceMissing');
    });

    test('equality via Equatable', () {
      const a = ServerFailure(message: 'err', code: 500, apiErrorCode: 'E');
      const b = ServerFailure(message: 'err', code: 500, apiErrorCode: 'E');
      expect(a, equals(b));
    });
  });
}
