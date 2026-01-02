// lib/src/ops/search_filter.dart
/// A function that returns true if a node matches the criteria.
typedef Predicate = bool Function(String name, String? ext);

/// Converts a user-typed query string into a testable predicate.
///
/// ### Behavior
/// *   **Syntax:** Supports `text`, `ext:json`, and `!exclusion` logic.
/// *   **Combination:** All terms must match (AND logic).
///
/// ### Example
/// `compileFilter("src !test ext:dart")` matches Dart files in "src" that are
/// not in "test".
Predicate compileFilter(String? query) {
  if (query == null) return _alwaysTrue;
  final raw = query.trim();
  if (raw.isEmpty) return _alwaysTrue;

  final tokens = raw.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  final checks = <Predicate>[];

  for (final t in tokens) {
    if (t.startsWith('ext:')) {
      final want = '.${t.substring(4).toLowerCase()}';
      checks.add((_, ext) => ext?.toLowerCase() == want);
    } else if (t.startsWith('!')) {
      final s = t.substring(1).toLowerCase();
      checks.add((name, _) => !name.toLowerCase().contains(s));
    } else {
      final s = t.toLowerCase();
      checks.add((name, _) => name.toLowerCase().contains(s));
    }
  }

  return (name, ext) => checks.every((c) => c(name, ext));
}

bool _alwaysTrue(String _, String? extensionName) => true;
