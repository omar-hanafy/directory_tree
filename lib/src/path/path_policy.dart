import 'package:directory_tree/src/path/tree_path.dart';
import 'package:directory_tree/src/tree/node_id.dart';
import 'package:meta/meta.dart';

/// The rules that turn raw path strings into canonical [TreePath]s and
/// [TreePath]s into node identities.
///
/// A policy answers three questions for a tree: which characters separate
/// segments ([backslashIsSeparator]), whether `README.md` and `readme.md` are
/// the same node ([caseSensitive]), and how Unicode spellings are unified
/// ([unicodeNormalizer]). Every path in one tree is parsed by the same policy,
/// configured through `TreeOptions.paths`.
///
/// The default policy (`const PathPolicy()`) is case sensitive, like Linux
/// and most POSIX file systems. Use [PathPolicy.caseInsensitive] for trees
/// that mirror Windows or default macOS volumes.
///
/// Parsing never touches the file system and does not depend on the host
/// platform, so `C:\a` parses the same on Linux, Windows, and the web.
@immutable
final class PathPolicy {
  /// Creates a policy.
  ///
  /// [caseSensitive] defaults to true. [backslashIsSeparator] defaults to
  /// true, so Windows paths parse on every platform. [unicodeNormalizer]
  /// defaults to none.
  const PathPolicy({
    this.caseSensitive = true,
    this.backslashIsSeparator = true,
    this.unicodeNormalizer,
  });

  /// A case-insensitive policy that otherwise uses the defaults.
  ///
  /// Mixed-case spellings of one path (`/Repo/LIB` and `/repo/lib`) share a
  /// [NodeId], so a tree shows them as one node.
  static const PathPolicy caseInsensitive = PathPolicy(caseSensitive: false);

  /// Whether paths that differ only in letter case are different nodes.
  ///
  /// When false, [idOf] lowercases the canonical string with
  /// [String.toLowerCase]. Display spelling is always preserved; only
  /// identity is affected. Drive letters are uppercased by [parse] in every
  /// policy, so `c:/a` and `C:/a` are the same path even when this is true.
  final bool caseSensitive;

  /// Whether `\` separates segments in addition to `/`.
  ///
  /// Keep the default (true) unless your POSIX paths contain literal
  /// backslashes in file names. When false, `\` is an ordinary character,
  /// and `C:\a` is a relative path with the single segment `C:\a`.
  final bool backslashIsSeparator;

  /// A function applied to every raw path before parsing, typically Unicode
  /// NFC normalization from a package of your choice.
  ///
  /// Use it when the same name can arrive in different Unicode forms (names
  /// created on macOS are often NFD while most other sources use NFC);
  /// without it, `café` in NFC and NFD are different nodes.
  ///
  /// The function must be pure, deterministic, and idempotent: canonical
  /// strings are parsed again, for example by
  /// `tree.nodeAt(node.path.toString())`. It is compared with `==` by
  /// [operator ==], so pass the same function object (for example a
  /// top-level function tear-off) when policies should compare equal.
  final String Function(String path)? unicodeNormalizer;

  /// Parses [path] into a canonical [TreePath].
  ///
  /// The input is used as is, without trimming. Rules, in order:
  ///
  /// 1. An empty string or any NUL character is a [FormatException].
  /// 2. [unicodeNormalizer], when set, is applied to the raw string; an empty
  ///    or NUL-containing result is also a [FormatException].
  /// 3. Separators are `/`, plus `\` when [backslashIsSeparator].
  /// 4. A drive letter followed by `:` and then a separator or the end of
  ///    the string becomes the root `X:/` with the letter uppercased.
  ///    `C:foo` (no separator) is a relative segment `C:foo`.
  /// 5. Exactly two leading separators followed by a non-separator start a
  ///    UNC root `//server/share/`, where server and share are the next two
  ///    segments taken literally (`//server/` when the share is missing).
  ///    Three or more leading separators collapse to the POSIX root `/`.
  /// 6. One leading separator gives the POSIX root `/`; anything else is
  ///    relative (root `''`).
  /// 7. The rest is split on separators. Empty segments and `.` are dropped;
  ///    `..` removes the previous segment. `..` at an absolute root stays at
  ///    the root; `..` that would climb above a relative root is a
  ///    [FormatException] (the path escapes its root).
  ///
  /// So `C:\work\..\repo\` parses to `C:/repo` and `a//./b/` to `a/b`.
  /// Parsing the [TreePath.toString] of a result with the same policy
  /// returns an equal path. Runs in O(path length).
  ///
  /// See also [tryParse], which returns `null` instead of throwing.
  TreePath parse(String path) {
    _checkInput(path, path, normalized: false);
    var input = path;
    final normalizer = unicodeNormalizer;
    if (normalizer != null) {
      input = normalizer(path);
      _checkInput(input, path, normalized: true);
    }
    // Unify separators up front so the scan below can use the native
    // indexOf for '/' alone.
    if (backslashIsSeparator && input.contains(r'\')) {
      input = input.replaceAll(r'\', '/');
    }

    final length = input.length;
    var index = 0;
    final String root;
    if (length >= 2 &&
        isAsciiLetter(input.codeUnitAt(0)) &&
        input.codeUnitAt(1) == _colon &&
        (length == 2 || input.codeUnitAt(2) == _slash)) {
      root = '${input[0].toUpperCase()}:/';
      index = 2;
    } else {
      var leading = 0;
      while (leading < length && input.codeUnitAt(leading) == _slash) {
        leading++;
      }
      if (leading == 2 && length > 2) {
        // `leading` counts every leading separator, so index 2 holds the
        // first character of the server name.
        var end = _segmentEnd(input, 2);
        final server = input.substring(2, end);
        index = _skipSeparators(input, end);
        if (index < length) {
          end = _segmentEnd(input, index);
          root = '//$server/${input.substring(index, end)}/';
          index = end;
        } else {
          root = '//$server/';
        }
      } else if (leading > 0) {
        root = '/';
        index = leading;
      } else {
        root = '';
      }
    }

    final segments = <String>[];
    // When the segment text is already canonical (single separators and no
    // '.' or '..' once the first segment started), the canonical string is
    // one substring of the input, which saves joining the segments again.
    var firstStart = -1;
    var lastEnd = -1;
    var canonicalText = true;
    while (true) {
      index = _skipSeparators(input, index);
      if (index >= length) break;
      final end = _segmentEnd(input, index);
      final size = end - index;
      if (size <= 2 && input.codeUnitAt(index) == _dot) {
        if (size == 1) {
          if (firstStart >= 0) canonicalText = false;
          index = end;
          continue;
        }
        if (input.codeUnitAt(index + 1) == _dot) {
          if (firstStart >= 0) canonicalText = false;
          index = end;
          if (segments.isNotEmpty) {
            segments.removeLast();
          } else if (root.isEmpty) {
            throw FormatException('Relative path escapes its root', path);
          }
          continue;
        }
      }
      if (firstStart < 0) {
        firstStart = index;
      } else if (index != lastEnd + 1) {
        canonicalText = false;
      }
      segments.add(input.substring(index, end));
      lastEnd = end;
      index = end;
    }
    if (segments.isEmpty || !canonicalText) {
      return createTreePath(root, segments);
    }
    // An input that is already canonical (the common case for generated or
    // scanned paths) is its own canonical string. Reusing it, instead of an
    // equal copy, lets a tree share one string between an entry's path, its
    // node's id, and its node's path.
    if (lastEnd == length && firstStart == root.length) {
      if (root.isEmpty) {
        // canonicalPathString returns [input] itself unless the first
        // segment needs the './' prefix.
        return createTreePath(
          root,
          segments,
          canonical: canonicalPathString(root, segments.first, input),
        );
      }
      if (input.startsWith(root)) {
        return createTreePath(root, segments, canonical: input);
      }
    }
    return createTreePath(
      root,
      segments,
      canonical: canonicalPathString(
        root,
        segments.first,
        input.substring(firstStart, lastEnd),
      ),
    );
  }

  /// Parses [path] like [parse], returning `null` when it is invalid.
  ///
  /// Only [FormatException]s are caught; an exception thrown by
  /// [unicodeNormalizer] propagates.
  TreePath? tryParse(String path) {
    try {
      return parse(path);
    } on FormatException {
      return null;
    }
  }

  /// The identity key of [path] under this policy.
  ///
  /// The key is the canonical [TreePath.toString], lowercased with
  /// [String.toLowerCase] when [caseSensitive] is false. Two paths are the
  /// same tree node exactly when their ids are equal. [path] should come
  /// from this policy's [parse]; the key is computed from its canonical
  /// string either way. Runs in O(path length).
  NodeId idOf(TreePath path) {
    final string = path.toString();
    return NodeId(caseSensitive ? string : string.toLowerCase());
  }

  static const int _slash = 0x2F;
  static const int _colon = 0x3A;
  static const int _dot = 0x2E;

  /// The index of the next '/' at or after [start], or the input length.
  static int _segmentEnd(String input, int start) {
    final end = input.indexOf('/', start);
    return end < 0 ? input.length : end;
  }

  static int _skipSeparators(String input, int start) {
    var index = start;
    while (index < input.length && input.codeUnitAt(index) == _slash) {
      index++;
    }
    return index;
  }

  static void _checkInput(
    String input,
    String source, {
    required bool normalized,
  }) {
    final suffix = normalized ? ' after Unicode normalization' : '';
    if (input.isEmpty) throw FormatException('Path is empty$suffix', source);
    final nul = input.indexOf('\u0000');
    if (nul >= 0) {
      throw FormatException(
        'Path contains a NUL character$suffix',
        source,
        normalized ? null : nul,
      );
    }
  }

  /// Whether [other] is a [PathPolicy] with equal settings.
  ///
  /// [unicodeNormalizer]s are compared with `==`.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PathPolicy &&
          other.caseSensitive == caseSensitive &&
          other.backslashIsSeparator == backslashIsSeparator &&
          other.unicodeNormalizer == unicodeNormalizer;

  @override
  int get hashCode =>
      Object.hash(caseSensitive, backslashIsSeparator, unicodeNormalizer);

  @override
  String toString() =>
      'PathPolicy(caseSensitive: $caseSensitive, '
      'backslashIsSeparator: $backslashIsSeparator, '
      'unicodeNormalizer: ${unicodeNormalizer == null ? 'none' : 'custom'})';
}
