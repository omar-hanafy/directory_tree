import 'package:directory_tree/src/path/path_policy.dart';
import 'package:meta/meta.dart';

/// An immutable, canonical path: a [root] plus a list of [segments].
///
/// A [TreePath] is what a raw path string becomes after a [PathPolicy] parses
/// it: separators are unified to `/`, empty and `.` segments are gone, `..`
/// is resolved, and Windows drive letters are uppercased. The same file system
/// location written as `C:\work\a.txt`, `c:/work//a.txt`, or
/// `C:/work/./x/../a.txt` parses to one value, `C:/work/a.txt`.
///
/// Use [TreePath.parse] for one-off parsing with the default policy; use
/// [PathPolicy.parse] when you need a custom policy (for example
/// [PathPolicy.caseInsensitive]). A [TreePath] is case preserving: [==],
/// [hashCode], and [compareTo] are exact and case sensitive on the canonical
/// string from [toString]. Case-insensitive identity is a policy concern, see
/// [PathPolicy.idOf].
///
/// Four kinds of roots exist:
///
/// | Input              | [root]            | [name] | [name] of the root alone |
/// | ------------------ | ----------------- | ------ | ------------------------ |
/// | `a/b`              | `''` (relative)   | `b`    | `.`                      |
/// | `/a/b`             | `/`               | `b`    | `/`                      |
/// | `c:\a\b`           | `C:/`             | `b`    | `C:`                     |
/// | `\\server\share\b` | `//server/share/` | `b`    | `//server/share`         |
///
/// Every operation is pure; a [TreePath] never touches the file system.
@immutable
final class TreePath implements Comparable<TreePath> {
  TreePath._(this.root, this.segments) : _string = _format(root, segments);

  TreePath._raw(this.root, this.segments, this._string);

  /// Parses [path] with the default `const PathPolicy()`.
  ///
  /// The default policy is case sensitive and treats both `/` and `\` as
  /// separators. See [PathPolicy.parse] for the full parsing rules.
  ///
  /// Throws a [FormatException] when [path] is empty, contains a NUL
  /// character, or is relative and uses `..` to climb above its root. Use
  /// [tryParse] to get `null` instead.
  factory TreePath.parse(String path) => const PathPolicy().parse(path);

  /// Parses [path] like [TreePath.parse], returning `null` instead of
  /// throwing when the path is invalid.
  static TreePath? tryParse(String path) => const PathPolicy().tryParse(path);

  /// The path root: `''` for relative paths, `/` for POSIX absolute paths,
  /// `X:/` for Windows drives (letter always uppercase), and
  /// `//server/share/` for UNC shares (`//server/` when the share is
  /// missing).
  ///
  /// Two paths can only contain one another when their roots are equal.
  final String root;

  /// The path segments below [root], outermost first.
  ///
  /// The list is unmodifiable and never contains `''`, `.`, or `..`.
  /// Segments never contain `/`; they contain `\` only when the parsing
  /// policy did not treat `\` as a separator.
  final List<String> segments;

  final String _string;

  /// Whether this path has a root, that is, whether [root] is not empty.
  bool get isAbsolute => root.isNotEmpty;

  /// Whether this path is a path root itself, that is, has no [segments].
  ///
  /// Path roots have no [parent]. Not to be confused with
  /// `TreeNode.isRoot`, which marks top-level nodes of a tree.
  bool get isRoot => segments.isEmpty;

  /// The last segment, or a display name for a path root.
  ///
  /// Path roots are named `/` (POSIX), `C:` (drive), `//server/share` (UNC),
  /// and `.` (the relative root).
  String get name {
    if (segments.isNotEmpty) return segments.last;
    if (root.isEmpty) return '.';
    if (root == '/') return '/';
    return root.substring(0, root.length - 1);
  }

  /// The extension of [name] including its leading dot, such as `.dart`.
  ///
  /// The extension starts at the last `.` of [name] and keeps its case. It is
  /// `''` when the name has no `.`, when its only `.` is the first character
  /// (`.env` has no extension), when the name ends with `.`, and for path
  /// roots. Only the last extension is returned: `archive.tar.gz` has the
  /// extension `.gz`.
  String get extension {
    if (segments.isEmpty) return '';
    final last = segments.last;
    final dot = last.lastIndexOf('.');
    if (dot <= 0 || dot == last.length - 1) return '';
    return last.substring(dot);
  }

  /// The path without its last segment, or `null` for path roots.
  ///
  /// The parent of `/a/b` is `/a`; the parent of `/a` is `/`; the parent of
  /// the relative path `a` is the relative root `.`. Runs in O(segments).
  TreePath? get parent {
    final count = segments.length;
    if (count == 0) return null;
    if (count == 1) return TreePath._(root, const <String>[]);
    // The canonical string ends with '/' and the last segment.
    return TreePath._raw(
      root,
      List<String>.unmodifiable(<String>[...segments]..removeLast()),
      _string.substring(0, _string.length - segments.last.length - 1),
    );
  }

  /// Returns the path of the entry [name] directly inside this path.
  ///
  /// The result has this path's [root] and one more segment, so
  /// `child(name).parent == this`. One exception mirrors parsing: on a UNC
  /// root without a share (`//server/`), [name] becomes the share and the
  /// result is the share root `//server/name/`.
  ///
  /// Throws an [ArgumentError] when [name] is empty, is `.` or `..`, or
  /// contains `/`, `\`, or a NUL character. Runs in O(segments).
  @useResult
  TreePath child(String name) {
    _checkSegmentName(name);
    if (segments.isEmpty && _isServerOnlyRoot(root)) {
      return TreePath._('$root$name/', const <String>[]);
    }
    return appendTreePathSegment(this, name);
  }

  /// Whether [ancestor] strictly contains this path.
  ///
  /// True when both paths have the same [root] and [ancestor]'s segments are
  /// a proper prefix of this path's segments. The comparison is exact and
  /// case sensitive; a path is not within itself. For policy-aware
  /// (case-insensitive) containment, compare ids from [PathPolicy.idOf].
  bool isWithin(TreePath ancestor) =>
      segments.length > ancestor.segments.length && _startsWith(ancestor);

  /// The relative path that leads from [ancestor] to this path.
  ///
  /// Returns a relative path (empty [root]) holding the remaining segments,
  /// the relative root `.` when this path equals [ancestor], and `null` when
  /// this path is neither equal to nor within [ancestor]. The comparison is
  /// exact and case sensitive, like [isWithin].
  @useResult
  TreePath? relativeTo(TreePath ancestor) {
    final start = ancestor.segments.length;
    if (segments.length < start || !_startsWith(ancestor)) return null;
    return TreePath._(
      '',
      List<String>.unmodifiable(<String>[...segments]..removeRange(0, start)),
    );
  }

  bool _startsWith(TreePath ancestor) {
    if (root != ancestor.root) return false;
    final prefix = ancestor.segments;
    for (var i = 0; i < prefix.length; i++) {
      if (segments[i] != prefix[i]) return false;
    }
    return true;
  }

  /// Orders paths by their canonical strings, by exact code units.
  ///
  /// This is a total order consistent with [==]. It is not a natural or
  /// case-insensitive order; sort display names with `TreeOrder.compareNames`
  /// instead.
  @override
  int compareTo(TreePath other) => _string.compareTo(other._string);

  /// Whether [other] is a [TreePath] with the same canonical string.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TreePath && other._string == _string;

  @override
  int get hashCode => _string.hashCode;

  /// The canonical string: [root] followed by [segments] joined with `/`.
  ///
  /// The relative root prints as `.`. A relative path whose first segment
  /// looks like a drive (`C:`) is prefixed with `./` so it cannot be read
  /// back as a drive path. Parsing the result with the same policy returns an
  /// equal path.
  @override
  String toString() => _string;

  static String _format(String root, List<String> segments) {
    if (segments.isEmpty) return root.isEmpty ? '.' : root;
    return canonicalPathString(root, segments.first, segments.join('/'));
  }

  static void _checkSegmentName(String name) {
    if (name.isEmpty || name == '.' || name == '..') {
      throw ArgumentError.value(name, 'name', 'Must be a real segment name');
    }
    for (var i = 0; i < name.length; i++) {
      final unit = name.codeUnitAt(i);
      if (unit == _slash || unit == _backslash || unit == 0) {
        throw ArgumentError.value(
          name,
          'name',
          'Must not contain "/", "\\", or a NUL character',
        );
      }
    }
  }
}

/// Creates a [TreePath] from already canonical parts without validation.
///
/// Package-internal: the parser and the tree builder use it to build paths
/// from parts they produced themselves. [root] must be one of the canonical
/// root forms and [segments] must follow the [TreePath.segments] rules. The
/// list is copied. Pass [canonical] only when it is exactly the string
/// [TreePath.toString] would produce (see [canonicalPathString]).
@internal
TreePath createTreePath(
  String root,
  List<String> segments, {
  String? canonical,
}) {
  final copy = List<String>.unmodifiable(segments);
  return canonical == null
      ? TreePath._(root, copy)
      : TreePath._raw(root, copy, canonical);
}

/// The canonical string of a non-root path from its [root], its [first]
/// segment, and [joined], all segments already joined with single `/`.
///
/// Package-internal; mirrors [TreePath.toString], including the `./` prefix
/// for a relative path whose first segment looks like a drive.
@internal
String canonicalPathString(String root, String first, String joined) {
  if (root.isNotEmpty) return '$root$joined';
  return _isDriveLike(first) ? './$joined' : joined;
}

/// Returns [parent] with [name] appended, skipping [TreePath.child]'s name
/// validation.
///
/// Package-internal: the tree builder uses it for segments that a policy
/// parsed, which may legitimately contain `\` when the policy does not treat
/// `\` as a separator. [parent] must not be a server-only UNC root.
@internal
TreePath appendTreePathSegment(TreePath parent, String name) {
  final segments = parent.segments;
  final String string;
  if (segments.isNotEmpty) {
    string = '${parent._string}/$name';
  } else if (parent.root.isEmpty) {
    string = _isDriveLike(name) ? './$name' : name;
  } else {
    string = '${parent.root}$name';
  }
  // A spread copy is several times faster than copying through an iterator
  // (followedBy, getRange), and the builder appends once per node.
  return TreePath._raw(
    parent.root,
    List<String>.unmodifiable(<String>[...segments, name]),
    string,
  );
}

const int _slash = 0x2F;
const int _backslash = 0x5C;
const int _colon = 0x3A;

/// Whether [segment] is exactly a drive spec such as `C:` or `d:`.
///
/// A relative path that starts with such a segment would read back as a
/// drive path, so [TreePath.toString] prefixes it with `./`.
bool _isDriveLike(String segment) =>
    segment.length == 2 &&
    segment.codeUnitAt(1) == _colon &&
    isAsciiLetter(segment.codeUnitAt(0));

/// Whether [root] is a UNC root without a share, such as `//server/`.
bool _isServerOnlyRoot(String root) =>
    root.length > 3 &&
    root.startsWith('//') &&
    root.indexOf('/', 2) == root.length - 1;

/// Whether [unit] is `/` or, when [backslashIsSeparator], `\`.
@internal
bool isPathSeparator(int unit, {required bool backslashIsSeparator}) =>
    unit == _slash || (backslashIsSeparator && unit == _backslash);

/// Whether [unit] is an ASCII letter (`A`-`Z` or `a`-`z`).
@internal
bool isAsciiLetter(int unit) =>
    (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
