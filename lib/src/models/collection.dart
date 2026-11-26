import 'model.dart';

typedef PageFetcher<T extends Model> = Future<Collection<T>> Function(int page);

/// Iterator: one page of results that can fetch the following pages.
///
///     final page = await mulla.charges.list(ChargeListFilters(limit: 20));
///     await for (final charge in mulla.charges.list().autoPaging()) { ... }
class Collection<T extends Model> {
  Collection({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
    PageFetcher<T>? fetchPage,
  }) : _fetchPage = fetchPage;

  factory Collection.fromResponse(ModelFactory<T> factory, Object? response, [PageFetcher<T>? fetchPage]) {
    if (response is List) {
      final items = makeModels(factory, response);

      return Collection(
          data: items, total: items.length, page: 1, limit: items.isEmpty ? 1 : items.length, totalPages: 1);
    }

    final body = response is Map ? response.cast<String, Object?>() : const <String, Object?>{};
    final items = makeModels(factory, body['data']);
    final limit = _toInt(body['limit'], items.length);
    final total = _toInt(body['total'], items.length);

    return Collection(
      data: List.unmodifiable(items),
      total: total,
      page: _toInt(body['page'], 1),
      limit: limit < 1 ? 1 : limit,
      totalPages: _toInt(body['total_pages'], limit > 0 ? (total / limit).ceil() : 1),
      fetchPage: fetchPage,
    );
  }

  final List<T> data;
  final int total;
  final int page;
  final int limit;
  final int totalPages;
  final PageFetcher<T>? _fetchPage;

  bool get hasMore => page < totalPages && _fetchPage != null;

  Future<Collection<T>?> nextPage() async {
    final fetch = _fetchPage;
    if (fetch == null || page >= totalPages) {
      return null;
    }

    return fetch(page + 1);
  }

  int get length => data.length;

  bool get isEmpty => data.isEmpty;

  T? get first => data.isEmpty ? null : data.first;

  /// Every item from this page onward; later pages are fetched as the stream is read.
  Stream<T> autoPaging() async* {
    yield* Stream.fromIterable(data);
    var next = await nextPage();
    while (next != null && !next.isEmpty) {
      yield* Stream.fromIterable(next.data);
      next = await next.nextPage();
    }
  }
}

/// `mulla.charges.list(...).autoPaging()` without awaiting the first page yourself.
extension CollectionFutureAutoPaging<T extends Model> on Future<Collection<T>> {
  Stream<T> autoPaging() => Stream.fromFuture(this).asyncExpand((page) => page.autoPaging());
}

int _toInt(Object? value, int fallback) {
  final n = value is num ? value : (value is String ? num.tryParse(value) : null);

  return n != null && n.isFinite ? n.truncate() : fallback;
}
