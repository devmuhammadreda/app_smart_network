import 'package:app_smart_network/app_smart_network.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── NetworkLocale ──────────────────────────────────────────────────────────

  group('NetworkLocale', () {
    setUp(() {
      NetworkLocale.setLocale('en');
      // Start every test from a clean custom-translation state.
      NetworkLocale.clearCustomTranslations();
    });

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

    // ── custom translations ──────────────────────────────────────────────────

    test('custom translations override built-ins', () {
      NetworkLocale.addTranslations('en', {
        'NoInternetConnection': 'Custom offline message.',
      });
      expect(
        NetworkLocale.getErrorMessage('NoInternetConnection'),
        'Custom offline message.',
      );
    });

    test('clearCustomTranslations(locale) removes only that locale', () {
      NetworkLocale.addTranslations('en', {'NoInternetConnection': 'Custom.'});
      NetworkLocale.addTranslations('ar', {'NoInternetConnection': 'مخصص.'});

      NetworkLocale.clearCustomTranslations('en');

      // English custom is gone — falls back to built-in.
      expect(
        NetworkLocale.getErrorMessage('NoInternetConnection'),
        'No internet connection.',
      );

      // Arabic custom is still present.
      NetworkLocale.setLocale('ar');
      expect(NetworkLocale.getErrorMessage('NoInternetConnection'), 'مخصص.');
    });

    test('clearCustomTranslations() removes all locales', () {
      NetworkLocale.addTranslations('en', {'NoInternetConnection': 'Custom.'});
      NetworkLocale.addTranslations('fr', {'NoInternetConnection': 'Perso.'});

      NetworkLocale.clearCustomTranslations();

      expect(
        NetworkLocale.getErrorMessage('NoInternetConnection'),
        'No internet connection.',
      );
    });

    test(
        'custom translations for new locale fall back to English for missing keys',
        () {
      NetworkLocale.addTranslations('fr', {
        'NoInternetConnection': 'Pas de connexion.',
      });
      NetworkLocale.setLocale('fr');

      expect(
        NetworkLocale.getErrorMessage('NoInternetConnection'),
        'Pas de connexion.',
      );
      // Key not in 'fr' → falls back to English built-in.
      expect(
        NetworkLocale.getErrorMessage('RequestCancelled'),
        'Request was cancelled.',
      );
      // Key missing everywhere → returns the key itself.
      expect(
        NetworkLocale.getErrorMessage('NonexistentKey'),
        'NonexistentKey',
      );
    });
  });

  // ── ApiService ─────────────────────────────────────────────────────────────

  group('ApiService', () {
    tearDown(() {
      // Clean up any instance created during tests.
      if (ApiService.isInitialized) ApiService.instance.dispose();
    });

    test('instance throws StateError before initialize()', () {
      expect(() => ApiService.instance, throwsStateError);
    });

    test('isInitialized is false before initialize()', () {
      expect(ApiService.isInitialized, isFalse);
    });

    test('isInitialized is true after initialize()', () {
      ApiService.initialize(
          const NetworkConfig(baseUrl: 'https://example.com'));
      expect(ApiService.isInitialized, isTrue);
    });

    test('instance returns the same object after initialize()', () {
      ApiService.initialize(
          const NetworkConfig(baseUrl: 'https://example.com'));
      expect(ApiService.instance, same(ApiService.instance));
    });

    test('dispose() resets isInitialized to false', () {
      ApiService.initialize(
          const NetworkConfig(baseUrl: 'https://example.com'));
      ApiService.instance.dispose();
      expect(ApiService.isInitialized, isFalse);
    });

    test('initialize() with Accept-Language header sets NetworkLocale', () {
      ApiService.initialize(const NetworkConfig(
        baseUrl: 'https://example.com',
        defaultHeaders: {'Accept-Language': 'ar'},
      ));
      expect(NetworkLocale.current, 'ar');
      ApiService.instance.dispose();
      NetworkLocale.setLocale('en'); // restore
    });

    test('removeAppLocale() restores default locale, not always en', () {
      ApiService.initialize(const NetworkConfig(
        baseUrl: 'https://example.com',
        defaultHeaders: {'Accept-Language': 'ar'},
      ));
      ApiService.instance.setAppLocale('fr');
      expect(NetworkLocale.current, 'fr');

      ApiService.instance.removeAppLocale();
      // Should restore to 'ar' (the initialize default), not 'en'.
      expect(NetworkLocale.current, 'ar');

      ApiService.instance.dispose();
      NetworkLocale.setLocale('en'); // restore
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
        responseData: {
          'errors': ['field required']
        },
      );
      expect(e.getResponseField<List>('errors'), ['field required']);
      expect(e.getResponseField<String>('missing'), isNull);
    });

    test('toString includes apiErrorCode when present', () {
      const e = ApiException('Bad', 400, apiErrorCode: 'UserExists');
      expect(e.toString(), contains('Code: UserExists'));
    });
  });
}
