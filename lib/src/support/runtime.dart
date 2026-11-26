import 'runtime_stub.dart' if (dart.library.io) 'runtime_io.dart' if (dart.library.js_interop) 'runtime_web.dart'
    as impl;

/// Runtime description for the User-Agent, e.g. `Dart/3.5.0 (android)`.
String runtimeName() => impl.runtimeName();

/// True when running in a browser, where streamed HTTP responses are buffered.
bool get isWeb => impl.isWeb;
