import 'dart:io' show Platform;

String runtimeName() {
  final version = Platform.version.split(' ').first;

  return 'Dart/$version (${Platform.operatingSystem})';
}

const bool isWeb = false;
