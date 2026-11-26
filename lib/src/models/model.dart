import 'dart:collection';

import '../errors.dart';

typedef RawData = Map<String, Object?>;

abstract class Model {
  Model(RawData data) : raw = UnmodifiableMapView(Map.of(data));

  final Map<String, Object?> raw;

  Object? get(String field) => raw[field];

  RawData toJson() => Map.of(raw);
}

/// Any API object the SDK does not model with typed fields (banks, countries...).
class MullaObject extends Model {
  MullaObject(super.data);

  @override
  String toString() => 'MullaObject$raw';
}

typedef ModelFactory<T extends Model> = T Function(RawData data);

T makeModel<T extends Model>(ModelFactory<T> factory, Object? data, String name) {
  if (data is! Map) {
    throw MullaException('Mulla returned an empty or unexpected response where a $name was expected.');
  }

  return factory(data.cast<String, Object?>());
}

List<T> makeModels<T extends Model>(ModelFactory<T> factory, Object? items) => items is List
    ? [
        for (final item in items)
          if (item is Map) factory(item.cast<String, Object?>())
      ]
    : <T>[];

String? str(RawData d, String key) {
  final v = d[key];

  return v is String || v is num || v is bool ? '$v' : null;
}

bool? boolean(RawData d, String key) {
  final v = d[key];
  if (v is bool) return v;
  if (v == 1 || v == '1' || v == 'true' || v == 'on' || v == 'yes') return true;
  if (v == 0 || v == '0' || v == 'false' || v == 'off' || v == 'no' || v == '') return false;

  return null;
}

num? money(RawData d, String key) {
  final v = d[key];
  if (v is num) return v.isFinite ? v : null;
  if (v is String && v.trim().isNotEmpty) {
    final n = num.tryParse(v.trim());

    return n != null && n.isFinite ? n : null;
  }

  return null;
}

int? integer(RawData d, String key) => money(d, key)?.truncate();

DateTime? date(RawData d, String key) {
  final v = d[key];

  return v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
}

Map<String, Object?>? obj(RawData d, String key) {
  final v = d[key];

  return v is Map ? v.cast<String, Object?>() : null;
}

List<String> strings(RawData d, String key) {
  final v = d[key];

  return v is List ? [for (final item in v) '$item'] : const [];
}

/// The id of a relation that may be inlined as an object or given as a plain id.
String? relationId(RawData d, String key) {
  final v = d[key];
  if (v is Map) {
    return str(v.cast<String, Object?>(), 'id');
  }

  return str(d, key);
}
