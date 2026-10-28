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
  // A path is stored in one of two forms, chosen by whoever creates it:
  //
  // * List form: [_link] is the full, unmodifiable segment list (empty for
  //   path roots). Parsing, [child], [relativeTo], and [parent] of a parsed
  //   path create this form; it owns its list and keeps nothing else alive.
  // * Chain form: [_link] is the parent path and [_name] the last segment.
  //   The tree builder creates the paths of tree nodes in this form, where
  //   every parent is the path of the parent node and is kept alive by the
  //   tree anyway, so a node path costs one small object instead of a copy
  //   of all its ancestors' segments. [segments] is computed on first use.
  //
  // Both forms keep the canonical string, so equality, hashing, and order
  // never depend on the form.

  TreePath._(this.root, List<String> segments, this._string)
    : _link = segments,
      _name = segments.isEmpty ? '' : segments.last;

  TreePath._child(TreePath parent, String name, this._string)
    : root = parent.root,
      _link = parent,
      _name = name;

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

  /// The segment list (list form) or the parent path (chain form).
  final Object _link;

  /// The last segment, or `''` for a path root.
  final String _name;

  final String _string;

  /// The path segments below [root], outermost first.
  ///
  /// The list is unmodifiable and never contains `''`, `.`, or `..`.
  /// Segments never contain `/`; they contain `\` only when the parsing
  /// policy did not treat `\` as a separator.
  ///
  /// The paths of tree nodes build this list on first access, in
  /// O(segments), and keep it; every later access is O(1).
  late final List<String> segments = _segmentList();

  /// Whether this path has a root, that is, whether [root] is not empty.
  bool get isAbsolute => root.isNotEmpty;

  /// Whether this path is a path root itself, that is, has no [segments].
  ///
  /// Path roots have no [parent]. Not to be confused with
  /// `TreeNode.isRoot`, which marks top-level nodes of a tree.
  // Segment names are never empty, so only a path root has an empty name.
  bool get isRoot => _name.isEmpty;

  /// The last segment, or a display name for a path root.
  ///
  /// Path roots are named `/` (POSIX), `C:` (drive), `//server/share` (UNC),
  /// and `.` (the relative root).
  String get name {
    if (_name.isNotEmpty) return _name;
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
    final last = _name;
    final dot = last.lastIndexOf('.');
    if (dot <= 0 || dot == last.length - 1) return '';
    return last.substring(dot);
  }

  /// The path without its last segment, or `null` for path roots.
  ///
  /// The parent of `/a/b` is `/a`; the parent of `/a` is `/`; the parent of
  /// the relative path `a` is the relative root `.`. Runs in O(1) for the
  /// paths of tree nodes and in O(segments) at most otherwise.
  TreePath? get parent {
    final link = _link;
    if (link is TreePath) return link;
    final list = link as List<String>;
    final count = list.length;
    if (count == 0) return null;
    if (count == 1) {
      return TreePath._(root, const <String>[], root.isEmpty ? '.' : root);
    }
    // The canonical string ends with '/' and the last segment.
    return TreePath._(
      root,
      List<String>.unmodifiable(list.sublist(0, count - 1)),
      _string.substring(0, _string.length - _name.length - 1),
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
    if (isRoot && _isServerOnlyRoot(root)) {
      return TreePath._('$root$name/', const <String>[], '$root$name/');
    }
    // List form: a chain would keep every intermediate path of repeated
    // child calls alive. Reading the segments without [segments] leaves
    // this path's lazy list unbuilt.
    return TreePath._(
      root,
      List<String>.unmodifiable(<String>[..._segmentList(), name]),
      _childString(this, name),
    );
  }

  /// Whether [ancestor] strictly contains this path.
  ///
  /// True when both paths have the same [root] and [ancestor]'s segments are
  /// a proper prefix of this path's segments. The comparison is exact and
  /// case sensitive; a path is not within itself. For policy-aware
  /// (case-insensitive) containment, compare ids from [PathPolicy.idOf].
  bool isWithin(TreePath ancestor) {
    if (isRoot || root != ancestor.root) return false;
    if (ancestor.isRoot) return true;
    // Segments never contain '/', so the segments of [ancestor] are a
    // prefix of this path's exactly when its canonical string is a prefix
    // of this one's that ends at a '/'. Both strings start with the same
    // root, and a relative path gets its './' prefix from its first
    // segment, which a contained path shares.
    final prefix = ancestor._string;
    final string = _string;
    return string.length > prefix.length &&
        string.codeUnitAt(prefix.length) == _slash &&
        string.startsWith(prefix);
  }

  /// The relative path that leads from [ancestor] to this path.
  ///
  /// Returns a relative path (empty [root]) holding the remaining segments,
  /// the relative root `.` when this path equals [ancestor], and `null` when
  /// this path is neither equal to nor within [ancestor]. The comparison is
  /// exact and case sensitive, like [isWithin].
  @useResult
  TreePath? relativeTo(TreePath ancestor) {
    if (this == ancestor) return TreePath._('', const <String>[], '.');
    if (!isWithin(ancestor)) return null;
    return createTreePath('', _segmentList().sublist(ancestor._segmentCount()));
  }

  /// [segments] without storing it in the lazy field: the list of a list
  /// form path, or a new list for a chain form path, in O(segments).
  List<String> _segmentList() {
    final names = <String>[];
    var path = this;
    for (;;) {
      final link = path._link;
      if (link is! TreePath) {
        // A list form path: a parsed path or a path root. Its list is
        // already unmodifiable.
        final prefix = link as List<String>;
        if (names.isEmpty) return prefix;
        return List<String>.unmodifiable(<String>[
          ...prefix,
          ...names.reversed,
        ]);
      }
      names.add(path._name);
      path = link;
    }
  }

  /// The number of [segments], without building the list. O(segments).
  int _segmentCount() {
    var count = 0;
    var path = this;
    for (;;) {
      final link = path._link;
      if (link is! TreePath) return count + (link as List<String>).length;
      count++;
      path = link;
    }
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
  return TreePath._(root, copy, canonical ?? TreePath._format(root, copy));
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
/// validation, as a path that refers to [parent] instead of copying its
/// segments.
///
/// Package-internal: the tree builder uses it for the path of every node
/// below a top-level node, whose parent path the tree keeps anyway. The
/// segments are names a policy parsed, which may legitimately contain `\`
/// when the policy does not treat `\` as a separator. [parent] must not be a
/// server-only UNC root. Pass [canonical] only when it equals the canonical
/// string of the result (see [isChildString]), so an existing string, such
/// as the parsed path of the node's entry, is shared instead of copied.
@internal
TreePath appendTreePathSegment(
  TreePath parent,
  String name, {
  String? canonical,
}) {
  assert(
    canonical == null || canonical == _childString(parent, name),
    'The canonical string must be the one of the appended path.',
  );
  return TreePath._child(parent, name, canonical ?? _childString(parent, name));
}

/// Whether [string] is the canonical string of [parent] with the segment
/// [name] appended, checked without building that string.
///
/// Package-internal: lets the tree builder reuse an entry's canonical string
/// for its node. Runs in O(length of [string]).
@internal
bool isChildString(TreePath parent, String name, String string) {
  final String prefix;
  if (!parent.isRoot) {
    prefix = parent._string;
    if (string.length != prefix.length + 1 + name.length ||
        string.codeUnitAt(prefix.length) != _slash) {
      return false;
    }
  } else if (parent.root.isNotEmpty) {
    prefix = parent.root;
    if (string.length != prefix.length + name.length) return false;
  } else {
    prefix = _isDriveLike(name) ? './' : '';
    if (string.length != prefix.length + name.length) return false;
  }
  return string.startsWith(prefix) && string.endsWith(name);
}

/// The canonical string of [parent] with the segment [name] appended.
String _childString(TreePath parent, String name) {
  if (!parent.isRoot) return '${parent._string}/$name';
  if (parent.root.isEmpty) return _isDriveLike(name) ? './$name' : name;
  return '${parent.root}$name';
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
