/// Windows extended-length paths, for directories that `dart:io` cannot list
/// through their ordinary path.
library;

/// The longest Windows path, in UTF-16 code units including the terminating
/// NUL, that the Win32 file APIs accept without the `\\?\` prefix
/// (`MAX_PATH`).
const int windowsMaxPath = 260;

/// The extended-length form of the absolute Windows path [path], or `null`
/// when [path] has none.
///
/// Forward slashes become backslashes, empty and `.` segments are dropped,
/// and `..` removes the previous segment (never the drive or the share),
/// because Windows applies none of these rules to a `\\?\` path. A drive
/// path `C:\a\b` becomes `\\?\C:\a\b` and a UNC path `\\server\share\a`
/// becomes `\\?\UNC\server\share\a`.
///
/// Returns `null` for relative paths, drive-relative paths (`C:a`, `\a`),
/// UNC paths without a share, and paths that already use a device prefix
/// (`\\?\` or `\\.\`). Pure string work; never touches the file system.
String? windowsExtendedLengthPath(String path) {
  final normalized = path.replaceAll('/', r'\');
  if (normalized.startsWith(r'\\?\') || normalized.startsWith(r'\\.\')) {
    return null;
  }
  final String root;
  final Iterable<String> rest;
  if (_isDriveRoot(normalized)) {
    root = '\\\\?\\${normalized.substring(0, 3)}';
    rest = normalized.substring(3).split(r'\');
  } else if (normalized.startsWith(r'\\')) {
    final parts = normalized.substring(2).split(r'\');
    if (parts.length < 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
    root = '\\\\?\\UNC\\${parts[0]}\\${parts[1]}';
    rest = parts.skip(2);
  } else {
    return null;
  }
  final segments = <String>[];
  for (final segment in rest) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isNotEmpty) segments.removeLast();
    } else {
      segments.add(segment);
    }
  }
  if (segments.isEmpty) return root.endsWith(r'\') ? root : '$root\\';
  final separator = root.endsWith(r'\') ? '' : r'\';
  return '$root$separator${segments.join(r'\')}';
}

/// The ordinary form of the Windows extended-length path [path]: the
/// inverse of [windowsExtendedLengthPath] for drive and UNC paths.
///
/// `\\?\C:\a` becomes `C:\a` and `\\?\UNC\server\share\a` becomes
/// `\\server\share\a`. Every other string, including other device paths
/// such as `\\?\Volume{...}\` and paths without the prefix, is returned
/// unchanged. The result can be longer than `MAX_PATH`; it is meant for
/// comparing paths, not for passing to Win32. Pure string work; never
/// touches the file system.
String windowsOrdinaryPath(String path) {
  if (path.startsWith(r'\\?\UNC\')) return '\\\\${path.substring(8)}';
  if (path.startsWith(r'\\?\') && _isDriveRoot(path.substring(4))) {
    return path.substring(4);
  }
  return path;
}

/// Whether [path] starts with a drive letter, a colon, and a backslash.
bool _isDriveRoot(String path) {
  if (path.length < 3) return false;
  final letter = path.codeUnitAt(0) | 0x20; // Lowercases ASCII letters.
  return letter >= 0x61 && // a
      letter <= 0x7A && // z
      path.codeUnitAt(1) == 0x3A && // :
      path.codeUnitAt(2) == 0x5C; // \
}
