import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final Random _random = Random.secure();
final RegExp _v4 =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', caseSensitive: false);
final RegExp _any = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

/// A random UUID v4 from a cryptographically secure source.
String uuidV4() => _format(Uint8List.fromList(List<int>.generate(16, (_) => _random.nextInt(256))));

/// A stable UUID v4-shaped value derived from [seed] (SHA-256), same output as the other Mulla SDKs.
String uuidFromSeed(String seed) => _format(Uint8List.fromList(sha256.convert(utf8.encode(seed)).bytes.sublist(0, 16)));

bool isUuidV4(String value) => _v4.hasMatch(value);

bool isUuid(String value) => _any.hasMatch(value);

String _format(Uint8List bytes) {
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}
