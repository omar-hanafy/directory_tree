// lib/src/ops/path_utils.dart
import 'package:path/path.dart' as p;

/// Returns the last part of a path (the filename).
String basename(String pathOrName) => p.basename(pathOrName);

/// Returns the file extension in lowercase (e.g., `.dart`).
String extensionLower(String pathOrName) =>
    p.extension(pathOrName).toLowerCase();

/// Checks if [candidate] has one of the provided [extensions].
///
/// Comparison is case-insensitive.
///
/// ### Example
/// ```dart
/// hasAnyExtension('image.JPG', ['.jpg', '.png']) // true
/// ```
bool hasAnyExtension(String candidate, Iterable<String> extensions) {
  final ext = extensionLower(candidate);
  for (final e in extensions) {
    if (ext == e.toLowerCase()) return true;
  }
  return false;
}
