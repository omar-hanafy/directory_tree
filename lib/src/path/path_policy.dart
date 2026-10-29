import 'package:directory_tree/src/path/case_folding.dart';
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
  /// When false, [idOf] folds the canonical string with Unicode simple case
  /// folding: the mappings with status C and S of CaseFolding.txt, pinned
  /// to Unicode 18.0.0 and applied one code point at a time by the
  /// package's own table. The result is identical on the VM, JavaScript,
  /// and WebAssembly and never follows the platform's
  /// [String.toLowerCase], whose tables differ between platforms and
  /// engine versions. So, in a case-insensitive tree:
  ///
  /// * `Σ`, `σ`, and the final sigma `ς` all fold to `σ`, wherever they
  ///   stand in a name, so `ΟΔΟΣ`, `οδος`, and `οδοσ` are one node.
  /// * `İ` (U+0130) has no simple folding: it stays as it is, so
  ///   `İstanbul` and `istanbul` are different nodes.
  /// * Cherokee lowercase letters fold to their uppercase forms.
  /// * The KELVIN SIGN (U+212A) folds to `k`, so `\u212Am` and `km` are one
  ///   node.
  /// * `ẞ` (U+1E9E) folds to `ß`; full foldings are not applied, so `ß` and
  ///   `ss` stay different.
  ///
  /// Display spelling is always preserved; only identity is affected.
  /// Drive letters are uppercased by [parse] in every policy, so `c:/a` and
  /// `C:/a` are the same path even when this is true.
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
  /// The function must be pure, deterministic, and idempotent, and it must
  /// normalize each segment on its own: for any `a` and `b`, normalizing
  /// `a/b` gives the normalized `a`, then `/`, then the normalized `b` (and
  /// likewise around `\` when it is a separator). Canonical strings are
  /// parsed again, for example by `tree.nodeAt(node.path.toString())`, and
  /// so are the paths of parents and inferred directories, which the
  /// function never saw on their own. The Unicode normalization forms (NFC,
  /// NFD, NFKC, NFKD) qualify, because nothing composes with `/` or `\`. A
  /// function that rewrites the ends of the whole string, such as `trim`,
  /// does not: it leaves `/a /b` as it is but turns its parent `/a ` into
  /// `/a`, another path.
  ///
  /// It is compared with `==` by [operator ==], so pass the same function
  /// object (for example a top-level function tear-off) when policies
  /// should compare equal.
  final String Function(String path)? unicodeNormalizer;

  /// Parses [path] into a canonical [TreePath].
  ///
  /// The input is used as is, without trimming. Rules, in order:
  ///
  /// 1. An empty string or any NUL character is a [FormatException].
  /// 2. [unicodeNormalizer], when set, is applied to the raw string; an empty
  ///    or NUL-containing result is also a [FormatException].
  /// 3. Separators are `/`, plus `\` when [backslashIsSeparator].
  /// 4. When [backslashIsSeparator], a Win32 file namespace prefix that
  ///    only respells a drive or UNC path is removed, because both forms
  ///    name the same file (APIs such as Rust's `canonicalize` return the
  ///    prefixed form): `\\?\C:\x` is read as `C:\x`, and
  ///    `\\?\UNC\server\share\x` (`UNC` in any case) as
  ///    `\\server\share\x`. The prefix may be spelled with either
  ///    separator, a run of separators after `\\?\` or after `UNC\`
  ///    counts as one (`\\?\\C:\x` is `C:\x`), and a result that
  ///    starts with such a prefix again is stripped again
  ///    (`\\?\UNC\?\C:\x` is `C:\x`). The rest follows the rules
  ///    below, so `..` is still resolved. Other `\\?\` paths (such as
  ///    volume GUID paths `\\?\Volume{...}\x`) and device paths
  ///    (`\\.\pipe\x`, `\\.\C:\x`) are not rewritten: they parse by
  ///    rule 6 as UNC roots such as `//?/Volume{...}/` and `//./pipe/`.
  /// 5. A drive letter followed by `:` and then a separator or the end of
  ///    the string becomes the root `X:/` with the letter uppercased.
  ///    `C:foo` (no separator) is a relative segment `C:foo`.
  /// 6. Exactly two leading separators followed by a non-separator start a
  ///    UNC root `//server/share/`, where server and share are the next two
  ///    segments taken literally (`//server/` when the share is missing).
  ///    Three or more leading separators collapse to the POSIX root `/`.
  /// 7. One leading separator gives the POSIX root `/`; anything else is
  ///    relative (root `''`).
  /// 8. The rest is split on separators. Empty segments and `.` are dropped;
  ///    `..` removes the previous segment. `..` at an absolute root stays at
  ///    the root; `..` that would climb above a relative root is a
  ///    [FormatException] (the path escapes its root).
  ///
  /// So `C:\work\..\repo\` parses to `C:/repo` and `a//./b/` to `a/b`.
  /// Parsing the [TreePath.toString] of a result with the same policy
  /// returns an equal path, given a [unicodeNormalizer] that meets its
  /// contract. Runs in O(path length).
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
    if (backslashIsSeparator) {
      if (input.contains(r'\')) input = input.replaceAll(r'\', '/');
      input = _stripFileNamespace(input);
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
  /// The key is the canonical [TreePath.toString], case-folded when
  /// [caseSensitive] is false with the package's Unicode 18.0.0 simple case
  /// folding (see [caseSensitive]), so the same path has the same id on
  /// every platform. Two paths are the same tree node exactly when their
  /// ids are equal. [path] should come from this policy's [parse]; the key
  /// is computed from its canonical string either way. Runs in O(path
  /// length).
  NodeId idOf(TreePath path) {
    final string = path.toString();
    return NodeId(caseSensitive ? string : foldCase(string));
  }

  static const int _slash = 0x2F;
  static const int _colon = 0x3A;
  static const int _dot = 0x2E;
  static const int _question = 0x3F;

  /// [input] (separators already `/`) without the Win32 file namespace
  /// prefixes that only spell a drive or UNC path differently: `//?/C:/x`
  /// becomes `C:/x` and `//?/UNC/server/share/x` becomes
  /// `//server/share/x`. Every other input is returned unchanged.
  ///
  /// The result is a fixed point, so a canonical string parses back to the
  /// same path. Separator runs after `//?/` and after `UNC/` are skipped
  /// like the run between a UNC server and its share, because parsing
  /// collapses them anyway: `//?///C:/x` is `C:/x`, not the UNC root
  /// `//?/C:/` that would print as the strippable `//?/C:/x`. A UNC
  /// prefix whose server is `?` again (`//?/UNC/?/C:/x`) is stripped
  /// again, for as long as the text keeps that form. The loop moves an
  /// index instead of building each intermediate string, so the whole
  /// strip runs in O(input length) and copies the text at most once.
  static String _stripFileNamespace(String input) {
    final length = input.length;
    if (length < 4 ||
        input.codeUnitAt(0) != _slash ||
        input.codeUnitAt(1) != _slash) {
      return input;
    }
    // The text so far is `//` followed by input.substring(server).
    var server = 2;
    while (server + 1 < length &&
        input.codeUnitAt(server) == _question &&
        input.codeUnitAt(server + 1) == _slash) {
      final index = _skipSeparators(input, server + 1);
      // `//?/X:` followed by a separator or the end: a drive path.
      if (index + 1 < length &&
          isAsciiLetter(input.codeUnitAt(index)) &&
          input.codeUnitAt(index + 1) == _colon &&
          (index + 2 == length || input.codeUnitAt(index + 2) == _slash)) {
        return input.substring(index);
      }
      // `//?/UNC/` followed by a server name: a UNC path. `UNC` is matched
      // without regard to case, as Windows does.
      if (index + 3 < length &&
          input.codeUnitAt(index) | 0x20 == 0x75 && // u
          input.codeUnitAt(index + 1) | 0x20 == 0x6E && // n
          input.codeUnitAt(index + 2) | 0x20 == 0x63 && // c
          input.codeUnitAt(index + 3) == _slash) {
        final next = _skipSeparators(input, index + 3);
        if (next < length) {
          server = next;
          continue;
        }
      }
      break;
    }
    return server == 2 ? input : '//${input.substring(server)}';
  }

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
