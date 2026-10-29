/// Spellings of Linux and macOS paths that path parsing reads the way the
/// host does.
library;

import 'package:directory_tree/src/path/tree_path.dart' show isAsciiLetter;

/// [path], a Linux or macOS path, respelled so that `PathPolicy.parse`
/// reads it as the location the host does.
///
/// Parsing applies Windows rules to two spellings that are ordinary paths
/// on these hosts: it reads a leading `//` as a UNC root, where the host
/// reads `/`, and a relative first segment such as `C:` as a drive, where
/// the host reads a file name. So `//x` becomes `/x` (and `//` becomes
/// `/`), and a relative path whose first segment is a drive spec, such as
/// `C:` or `c:/x`, gets the prefix `./`. Every other path is returned
/// unchanged, including `///x`, which parsing already reads as `/x`, and
/// `C:x` or `C:\x`, which parsing already reads as relative names.
String posixTreeSpelling(String path) {
  if (path.startsWith('//') && !path.startsWith('///')) {
    return path.substring(1);
  }
  if (path.length >= 2 &&
      isAsciiLetter(path.codeUnitAt(0)) &&
      path.codeUnitAt(1) == 0x3A && // ':'
      (path.length == 2 || path.codeUnitAt(2) == 0x2F)) {
    return './$path';
  }
  return path;
}
