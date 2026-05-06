import 'native_model.dart' if (dart.library.html) 'web_model.dart';
import 'package:flutter_hbb/generated_bridge.dart'
    if (dart.library.html) 'package:flutter_hbb/web/bridge.dart';

final platformFFI = PlatformFFI.instance;

String _normalizeLocaleName(String value) {
  final lower = value.toLowerCase();
  if (lower.startsWith('vi')) {
    return 'vi';
  }
  return 'en';
}

final localeName = _normalizeLocaleName(PlatformFFI.localeName);

RustdeskImpl get bind => platformFFI.ffiBind;

String ffiGetByName(String name, [String arg = '']) {
  return PlatformFFI.getByName(name, arg);
}

void ffiSetByName(String name, [String value = '']) {
  PlatformFFI.setByName(name, value);
}
