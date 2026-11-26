import 'dart:async';
import 'dart:convert';

/// One server-sent event.
class SseEvent {
  const SseEvent({this.event = 'message', required this.data, this.id});

  final String event;
  final String data;
  final String? id;

  @override
  String toString() => 'SseEvent($event, $data)';
}

/// Parses a `text/event-stream` body (https://html.spec.whatwg.org/#event-stream-interpretation).
///
/// Built from transformers (not `async*`) so cancelling the result cancels the
/// underlying connection right away instead of at the next event.
Stream<SseEvent> parseSse(Stream<List<int>> bytes) =>
    bytes.transform(utf8.decoder).transform(const LineSplitter()).transform(_SseDecoder());

class _SseDecoder extends StreamTransformerBase<String, SseEvent> {
  @override
  Stream<SseEvent> bind(Stream<String> lines) {
    var event = 'message';
    final data = StringBuffer();
    var hasData = false;
    String? id;

    void flush(EventSink<SseEvent> sink) {
      if (hasData) {
        sink.add(SseEvent(event: event, data: data.toString(), id: id));
      }
      event = 'message';
      data.clear();
      hasData = false;
    }

    return lines.transform(StreamTransformer.fromHandlers(
      handleData: (line, sink) {
        if (line.isEmpty) {
          flush(sink);

          return;
        }
        if (line.startsWith(':')) {
          return;
        }
        final colon = line.indexOf(':');
        final field = colon == -1 ? line : line.substring(0, colon);
        var value = colon == -1 ? '' : line.substring(colon + 1);
        if (value.startsWith(' ')) {
          value = value.substring(1);
        }
        switch (field) {
          case 'event':
            event = value;
          case 'data':
            if (hasData) data.write('\n');
            data.write(value);
            hasData = true;
          case 'id':
            id = value;
        }
      },
      handleDone: (sink) {
        flush(sink);
        sink.close();
      },
    ));
  }
}
