import '../enums.dart';

/// Drops nulls recursively and turns [DateTime]s into ISO-8601 strings.
Object? normalize(Object? value) {
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }
  if (value is ApiEnum) {
    return value.value;
  }
  if (value is List) {
    return [
      for (final item in value)
        if (item != null) normalize(item)
    ];
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.value != null) '${entry.key}': normalize(entry.value),
    };
  }

  return value;
}

/// Builds `?a=1&b=2` (RFC 3986 encoded), or an empty string.
String buildQuery(Map<String, Object?> query) {
  final normalized = normalize(query)! as Map<String, Object?>;
  if (normalized.isEmpty) {
    return '';
  }
  final parts = normalized.entries.map((e) => '${encodeRfc3986(e.key)}=${encodeRfc3986('${e.value}')}');

  return '?${parts.join('&')}';
}

/// Percent-encodes like JavaScript's encodeURIComponent plus `!'()*`.
String encodeRfc3986(String value) => Uri.encodeComponent(value).replaceAllMapped(RegExp(r"[!'()*]"), (m) {
      return '%${m[0]!.codeUnitAt(0).toRadixString(16).toUpperCase()}';
    });
