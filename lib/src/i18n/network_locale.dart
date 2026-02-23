/// Manages locale-aware error messages for the network package.
///
/// Call [setLocale] with your app locale (e.g. `'ar'`, `'en'`) to switch
/// the language of all network error messages. Built-in support for
/// **English** and **Arabic**. Extend with [addTranslations] for any
/// additional locale.
///
/// Usage:
/// ```dart
/// NetworkLocale.setLocale('ar');
/// print(NetworkLocale.getErrorMessage('NoInternetConnection'));
/// // لا يوجد اتصال بالإنترنت.
/// ```
class NetworkLocale {
  NetworkLocale._();

  static String _currentLocale = 'en';

  /// Currently active locale code (language only, e.g. `'en'`, `'ar'`).
  static String get current => _currentLocale;

  /// Sets the active locale. Accepts full locale tags like `'en-US'` or
  /// `'ar-SA'` – only the language part is used.
  static void setLocale(String locale) {
    _currentLocale = locale.split(RegExp(r'[-_]')).first.toLowerCase();
  }

  // Custom translations supplied by the app (override built-ins).
  static final Map<String, Map<String, String>> _custom = {};

  /// Registers additional translations or overrides for a [locale].
  ///
  /// ```dart
  /// NetworkLocale.addTranslations('fr', {
  ///   'NoInternetConnection': 'Pas de connexion internet.',
  /// });
  /// ```
  static void addTranslations(String locale, Map<String, String> messages) {
    _custom[locale] = {
      ...(_custom[locale] ?? {}),
      ...messages,
    };
  }

  /// Removes custom translations so lookups fall back to built-in messages.
  ///
  /// Pass a [locale] to clear only that language, or omit it to reset all
  /// custom translations at once.
  ///
  /// ```dart
  /// NetworkLocale.clearCustomTranslations('fr'); // clear French only
  /// NetworkLocale.clearCustomTranslations();     // clear everything
  /// ```
  static void clearCustomTranslations([String? locale]) {
    if (locale != null) {
      _custom.remove(locale);
    } else {
      _custom.clear();
    }
  }

  // ── Public lookup helpers ─────────────────────────────────────────────────

  /// Returns the translated message for [key], falling back to English,
  /// then [fallback], then [key] itself.
  static String getErrorMessage(String key, {String? fallback}) {
    return _lookup(key) ?? fallback ?? key;
  }

  /// Returns the translated message for an HTTP [statusCode].
  static String getStatusMessage(int statusCode, {String? fallback}) {
    final key = 'status_$statusCode';
    return _lookup(key) ?? fallback ?? _buildDefaultStatusMessage(statusCode);
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  static String? _lookup(String key) {
    // 1. Custom translation for current locale
    final customMsg = _custom[_currentLocale]?[key];
    if (customMsg != null) return customMsg;

    // 2. Built-in translation for current locale
    final builtMsg = _builtIn[_currentLocale]?[key];
    if (builtMsg != null) return builtMsg;

    // 3. Fallback to English built-in
    if (_currentLocale != 'en') return _builtIn['en']?[key];

    return null;
  }

  static String _buildDefaultStatusMessage(int statusCode) {
    String template;
    if (statusCode >= 400 && statusCode < 500) {
      template = getErrorMessage('status_default_4xx');
    } else if (statusCode >= 500 && statusCode < 600) {
      template = getErrorMessage('status_default_5xx');
    } else {
      template = getErrorMessage('status_default_unknown');
    }
    return template.replaceAll('{code}', '$statusCode');
  }

  // ── Built-in translations ─────────────────────────────────────────────────

  static const Map<String, Map<String, String>> _builtIn = {
    'en': _en,
    'ar': _ar,
  };

  static const Map<String, String> _en = {
    // Network / client errors
    'ConnectionTimeout': 'Connection timeout. Please try again.',
    'SendTimeout': 'Request send timeout. Please try again.',
    'ReceiveTimeout': 'Response timeout. Please try again.',
    'RequestCancelled': 'Request was cancelled.',
    'NetworkError': 'Network error. Please check your connection.',
    'BadCertificate': 'SSL certificate error.',
    'ConnectionError': 'Connection failed. Please check your network.',
    'NoInternetConnection': 'No internet connection.',
    'UnexpectedError': 'An unexpected error occurred.',
    'error_message': 'An error occurred. Please try again.',
    // Default status templates  ({code} is replaced at runtime)
    'status_default_4xx': 'Request error ({code}). Please try again.',
    'status_default_5xx': 'Server error ({code}). Please try again later.',
    'status_default_unknown': 'Unknown error ({code}).',
    // 1xx
    'status_100': 'Continue.',
    'status_101': 'Switching protocols.',
    'status_102': 'Processing.',
    'status_103': 'Early hints.',
    // 2xx
    'status_200': 'Success.',
    'status_201': 'Created successfully.',
    'status_202': 'Accepted.',
    'status_204': 'No content.',
    // 3xx
    'status_300': 'Multiple choices.',
    'status_301': 'Moved permanently.',
    'status_302': 'Found.',
    'status_303': 'See other.',
    'status_304': 'Not modified.',
    'status_307': 'Temporary redirect.',
    'status_308': 'Permanent redirect.',
    // 4xx
    'status_400': 'Bad request.',
    'status_401': 'Unauthorized. Please log in.',
    'status_402': 'Payment required.',
    'status_403': 'Access denied.',
    'status_404': 'Resource not found.',
    'status_405': 'Method not allowed.',
    'status_406': 'Not acceptable.',
    'status_407': 'Proxy authentication required.',
    'status_408': 'Request timeout.',
    'status_409': 'Conflict.',
    'status_410': 'Resource no longer available.',
    'status_411': 'Length required.',
    'status_412': 'Precondition failed.',
    'status_413': 'Request too large.',
    'status_414': 'URI too long.',
    'status_415': 'Unsupported media type.',
    'status_416': 'Range not satisfiable.',
    'status_417': 'Expectation failed.',
    'status_418': "I'm a teapot.",
    'status_419': 'Authentication timeout.',
    'status_421': 'Misdirected request.',
    'status_422': 'Validation failed.',
    'status_423': 'Resource is locked.',
    'status_424': 'Failed dependency.',
    'status_425': 'Too early.',
    'status_426': 'Upgrade required.',
    'status_428': 'Precondition required.',
    'status_429': 'Too many requests. Please slow down.',
    'status_431': 'Request header fields too large.',
    'status_451': 'Unavailable for legal reasons.',
    // 5xx
    'status_500': 'Internal server error.',
    'status_501': 'Not implemented.',
    'status_502': 'Bad gateway.',
    'status_503': 'Service unavailable.',
    'status_504': 'Gateway timeout.',
    'status_505': 'HTTP version not supported.',
    'status_506': 'Variant also negotiates.',
    'status_507': 'Insufficient storage.',
    'status_508': 'Loop detected.',
    'status_510': 'Not extended.',
    'status_511': 'Network authentication required.',
  };

  static const Map<String, String> _ar = {
    // Network / client errors
    'ConnectionTimeout': 'انتهت مهلة الاتصال. يرجى المحاولة مرة أخرى.',
    'SendTimeout': 'انتهت مهلة إرسال الطلب. يرجى المحاولة مرة أخرى.',
    'ReceiveTimeout': 'انتهت مهلة استقبال الرد. يرجى المحاولة مرة أخرى.',
    'RequestCancelled': 'تم إلغاء الطلب.',
    'NetworkError': 'خطأ في الشبكة. يرجى التحقق من اتصالك.',
    'BadCertificate': 'خطأ في شهادة SSL.',
    'ConnectionError': 'فشل الاتصال. يرجى التحقق من شبكتك.',
    'NoInternetConnection': 'لا يوجد اتصال بالإنترنت.',
    'UnexpectedError': 'حدث خطأ غير متوقع.',
    'error_message': 'حدث خطأ. يرجى المحاولة مرة أخرى.',
    // Default status templates
    'status_default_4xx': 'خطأ في الطلب ({code}). يرجى المحاولة مرة أخرى.',
    'status_default_5xx': 'خطأ في الخادم ({code}). يرجى المحاولة لاحقاً.',
    'status_default_unknown': 'خطأ غير معروف ({code}).',
    // 1xx
    'status_100': 'استمرار.',
    'status_101': 'تبديل البروتوكولات.',
    'status_102': 'قيد المعالجة.',
    'status_103': 'تلميحات مبكرة.',
    // 2xx
    'status_200': 'نجاح.',
    'status_201': 'تم الإنشاء بنجاح.',
    'status_202': 'تم القبول.',
    'status_204': 'لا يوجد محتوى.',
    // 3xx
    'status_300': 'خيارات متعددة.',
    'status_301': 'نقل دائم.',
    'status_302': 'وُجد.',
    'status_303': 'انظر إلى موقع آخر.',
    'status_304': 'لم يتعدل.',
    'status_307': 'إعادة توجيه مؤقتة.',
    'status_308': 'إعادة توجيه دائمة.',
    // 4xx
    'status_400': 'طلب غير صالح.',
    'status_401': 'غير مصرح. يرجى تسجيل الدخول.',
    'status_402': 'الدفع مطلوب.',
    'status_403': 'تم رفض الوصول.',
    'status_404': 'المورد غير موجود.',
    'status_405': 'الطريقة غير مسموح بها.',
    'status_406': 'غير مقبول.',
    'status_407': 'مصادقة الوكيل مطلوبة.',
    'status_408': 'انتهت مهلة الطلب.',
    'status_409': 'تعارض.',
    'status_410': 'المورد لم يعد متاحاً.',
    'status_411': 'الطول مطلوب.',
    'status_412': 'فشل الشرط المسبق.',
    'status_413': 'الطلب كبير جداً.',
    'status_414': 'عنوان URL طويل جداً.',
    'status_415': 'نوع وسائط غير مدعوم.',
    'status_416': 'النطاق غير مُرضٍ.',
    'status_417': 'فشلت التوقعات.',
    'status_418': 'أنا إبريق شاي.',
    'status_419': 'انتهت مهلة المصادقة.',
    'status_421': 'طلب موجَّه بشكل خاطئ.',
    'status_422': 'فشل التحقق من البيانات.',
    'status_423': 'المورد مقفل.',
    'status_424': 'تبعية فاشلة.',
    'status_425': 'مبكر جداً.',
    'status_426': 'الترقية مطلوبة.',
    'status_428': 'الشرط المسبق مطلوب.',
    'status_429': 'طلبات كثيرة جداً. يرجى التباطؤ.',
    'status_431': 'حقول رأس الطلب كبيرة جداً.',
    'status_451': 'غير متاح لأسباب قانونية.',
    // 5xx
    'status_500': 'خطأ داخلي في الخادم.',
    'status_501': 'غير مُنفَّذ.',
    'status_502': 'بوابة سيئة.',
    'status_503': 'الخدمة غير متاحة.',
    'status_504': 'انتهت مهلة البوابة.',
    'status_505': 'إصدار HTTP غير مدعوم.',
    'status_506': 'المتغير يتفاوض أيضاً.',
    'status_507': 'مساحة التخزين غير كافية.',
    'status_508': 'تم اكتشاف حلقة.',
    'status_510': 'غير مُمتَد.',
    'status_511': 'مصادقة الشبكة مطلوبة.',
  };
}
