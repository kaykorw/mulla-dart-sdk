final RegExp _secretQuery = RegExp(r'([?&](?:token)=)[^&#]*', caseSensitive: false);

/// Hides secret query parameters (checkout `token`) so URLs are safe to log.
String redactUrl(String url) => url.replaceAllMapped(_secretQuery, (m) => '${m[1]}***');
