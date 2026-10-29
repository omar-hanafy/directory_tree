import 'package:directory_tree/src/path/case_folding.dart';
import 'package:directory_tree/src/path/path_policy.dart';
import 'package:directory_tree/src/path/tree_path.dart';
import 'package:directory_tree/src/tree/directory_tree.dart';
import 'package:directory_tree/src/tree/tree_issue.dart';
import 'package:meta/meta.dart';

/// Orders two sibling nodes: negative when [a] comes first, positive when
/// [b] does, zero when the comparator has no preference.
///
/// Used by [TreeOptions.order] to sort every directory's children and the
/// top-level nodes. The builder breaks ties (zero) by comparing node ids, so
/// sibling order is always total and deterministic. A comparator must be
/// consistent (a total preorder); an inconsistent one still yields a valid
/// tree, in an unspecified order.
///
/// The parameters are `TreeNode<Object?>` so one comparator works for trees
/// of any data type. To compare by typed data, wrap a typed function with
/// [TreeOrder.by].
typedef NodeComparator = int Function(TreeNode<Object?> a, TreeNode<Object?> b);

/// The settings that shape a [DirectoryTree]: how paths are parsed, which
/// nodes are top level, and how siblings are ordered.
///
/// Options are part of a tree's value: two trees are equal only when their
/// options are equal. Every field has a default, so `const TreeOptions()` is
/// a case-sensitive tree with [TreeRoots.minimal] roots and
/// [TreeOrder.directoriesFirst] ordering.
///
/// [TreeOptions] is not generic on purpose. A generic options class would
/// put the data type in the comparator's parameter types, and reading
/// `options.order` through a `DirectoryTree<Object?>` reference would then
/// throw at runtime. Typed comparators go through [TreeOrder.by] instead.
@immutable
final class TreeOptions {
  /// Creates options; every argument has a default.
  const TreeOptions({
    this.paths = const PathPolicy(),
    this.roots = const TreeRoots.minimal(),
    this.order = TreeOrder.directoriesFirst,
  });

  /// How raw entry paths are parsed and which spellings are the same node.
  ///
  /// Defaults to `const PathPolicy()` (case sensitive, `\` is a separator).
  final PathPolicy paths;

  /// How the top-level nodes are chosen. Defaults to [TreeRoots.minimal].
  final TreeRoots roots;

  /// How siblings (and top-level nodes) are ordered.
  ///
  /// Defaults to [TreeOrder.directoriesFirst]. Ties are broken by node id.
  /// Functions compare by identity, so reuse one comparator object (a
  /// static or top-level function, or a stored [TreeOrder.by] result) when
  /// options should compare equal.
  final NodeComparator order;

  /// Returns a copy with the given fields replaced.
  @useResult
  TreeOptions copyWith({
    PathPolicy? paths,
    TreeRoots? roots,
    NodeComparator? order,
  }) => TreeOptions(
    paths: paths ?? this.paths,
    roots: roots ?? this.roots,
    order: order ?? this.order,
  );

  /// Whether [other] is a [TreeOptions] with equal [paths], [roots], and
  /// [order] (functions compare by identity).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TreeOptions &&
          other.paths == paths &&
          other.roots == roots &&
          other.order == order;

  @override
  int get hashCode => Object.hash(paths, roots, order);

  @override
  String toString() {
    final String orderName;
    if (order == TreeOrder.directoriesFirst) {
      orderName = 'directoriesFirst';
    } else if (order == TreeOrder.alphabetical) {
      orderName = 'alphabetical';
    } else {
      orderName = 'custom';
    }
    return 'TreeOptions(paths: $paths, roots: $roots, order: $orderName)';
  }
}

/// The strategy that decides which directories are the top-level nodes of a
/// [DirectoryTree].
///
/// Each entry "contributes" a directory: a file entry its parent, a
/// directory entry itself. The strategies differ in how contributions become
/// roots:
///
/// * [TreeRoots.minimal] (default): the outermost contributions, so a tree
///   of `/repo/lib/a.dart` starts at `lib`, not at `/`.
/// * [TreeRoots.commonAncestor]: one root per path root, at the deepest
///   directory that contains everything.
/// * [TreeRoots.fixed]: exactly the directories you list.
/// * [TreeRoots.filesystem]: the path roots themselves (`/`, `C:`), with
///   every directory down to each entry.
@immutable
final class TreeRoots {
  /// Uses the outermost contributions as roots.
  ///
  /// Each file entry contributes its parent directory and each directory
  /// entry contributes itself; contributions inside another contribution
  /// are dropped, and the rest become the top-level nodes. Adding
  /// `/repo/lib/src/a.dart` to a tree rooted at `/repo/lib/src/x` moves the
  /// root up to `src`. This matches what a user expects from "show me these
  /// files": no empty chains of single directories above them.
  const TreeRoots.minimal()
    : _kind = TreeRootsKind.minimal,
      _paths = const <String>[];

  /// Uses one root per path root: the deepest directory that contains every
  /// contribution from that path root.
  ///
  /// Paths are grouped by [TreePath.root]: POSIX `/`, each drive, each UNC
  /// share, and the relative root `.`. Entries `/a/b/x.txt` and `/a/c/y.txt`
  /// give the single root `/a`.
  const TreeRoots.commonAncestor()
    : _kind = TreeRootsKind.commonAncestor,
      _paths = const <String>[];

  /// Uses exactly the directories at [paths] as roots.
  ///
  /// The roots exist even when no entry is inside them. Paths are parsed by
  /// the tree's [PathPolicy]; duplicates merge, and a root inside another
  /// root collapses into the outer one. A path that fails to parse is
  /// reported as a [TreeIssueKind.invalidPath] issue without an entry.
  /// Entries outside every root are dropped as
  /// [TreeIssueKind.outsideRoots]; a directory entry may equal a root, while
  /// a file entry equal to a root is a [TreeIssueKind.conflict].
  ///
  /// Do not modify [paths] after passing it; the list is kept as is.
  const TreeRoots.fixed(List<String> paths)
    : _kind = TreeRootsKind.fixed,
      _paths = paths;

  /// Uses the path roots themselves (`/`, `C:/`, `//server/share/`, `.`) as
  /// roots, with every directory between a root and its entries present.
  ///
  /// Choose it for a file-manager style view that always starts at the top
  /// of the file system.
  const TreeRoots.filesystem()
    : _kind = TreeRootsKind.filesystem,
      _paths = const <String>[];

  final TreeRootsKind _kind;
  final List<String> _paths;

  /// Whether [other] uses the same strategy (and, for [TreeRoots.fixed],
  /// the same paths in the same order).
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TreeRoots || other._kind != _kind) return false;
    final paths = other._paths;
    if (paths.length != _paths.length) return false;
    for (var i = 0; i < paths.length; i++) {
      if (paths[i] != _paths[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(_kind, Object.hashAll(_paths));

  @override
  String toString() => _kind == TreeRootsKind.fixed
      ? 'TreeRoots.fixed(${_paths.join(', ')})'
      : 'TreeRoots.${_kind.name}()';
}

/// The root strategy of a [TreeRoots]. Package-internal.
@internal
enum TreeRootsKind {
  /// See [TreeRoots.minimal].
  minimal,

  /// See [TreeRoots.commonAncestor].
  commonAncestor,

  /// See [TreeRoots.fixed].
  fixed,

  /// See [TreeRoots.filesystem].
  filesystem,
}

/// Read access to a [TreeRoots] configuration for the tree builder.
/// Package-internal.
@internal
extension TreeRootsInternals on TreeRoots {
  /// The strategy.
  TreeRootsKind get kind => _kind;

  /// The raw paths given to [TreeRoots.fixed]; empty for other strategies.
  List<String> get fixedPaths => _paths;
}

/// Built-in sibling orders and helpers for writing your own.
///
/// Every comparator here is consistent and, combined with the builder's
/// tie-break by node id, yields a total, deterministic order.
abstract final class TreeOrder {
  /// Directories before files, then by name with [compareNames].
  ///
  /// The default [TreeOptions.order], matching most file explorers.
  static int directoriesFirst(TreeNode<Object?> a, TreeNode<Object?> b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return compareNames(a.name, b.name);
  }

  /// Files and directories interleaved, by name with [compareNames].
  static int alphabetical(TreeNode<Object?> a, TreeNode<Object?> b) =>
      compareNames(a.name, b.name);

  /// Compares names in natural, case-insensitive order.
  ///
  /// Runs of ASCII digits compare by numeric value, so `file2` sorts before
  /// `file10`; numbers of any length work, with no integer parsing. Letters
  /// compare without regard to case (`alpha` before `Beta`). When two names
  /// are equal under those rules (`a` and `A`, or `x1` and `x01`), they
  /// compare by exact code units, so distinct names never compare equal and
  /// the result is a total order.
  ///
  /// Letters are compared after Unicode simple case folding (CaseFolding.txt
  /// statuses C and S, Unicode 18.0.0), one code point at a time, with the
  /// package's own table, so the order is identical on the VM, JavaScript,
  /// and WebAssembly, and does not follow the platform's
  /// [String.toLowerCase]. Folded code points compare in UTF-16 code unit
  /// order, the order [String.compareTo] uses. Consequences of the folding:
  ///
  /// * `Σ`, `σ`, and the final sigma `ς` all fold to `σ`.
  /// * `İ` (U+0130) has no simple folding, so it sorts by its own code point,
  ///   after every ASCII letter: `Jena` comes before `İzmir`.
  /// * Cherokee lowercase letters fold to their uppercase forms.
  /// * The KELVIN SIGN (U+212A) folds to `k` and `ẞ` (U+1E9E) to `ß`.
  /// * Full foldings are not applied, so `ß` does not equal `ss`.
  ///
  /// Runs in O(`a.length + b.length`) and allocates nothing.
  static int compareNames(String a, String b) {
    final natural = _compareNatural(a, b);
    return natural != 0 ? natural : a.compareTo(b);
  }

  /// Adapts [compare], which takes typed nodes, to a [NodeComparator].
  ///
  /// Use it to order by entry data, for example by size or date:
  ///
  /// ```dart
  /// final bySize = TreeOrder.by<int>(
  ///   (a, b) => (a.data ?? 0).compareTo(b.data ?? 0),
  /// );
  /// final tree = DirectoryTree<int>.build(
  ///   entries,
  ///   options: TreeOptions(order: bySize),
  /// );
  /// ```
  ///
  /// The returned comparator casts both nodes to `TreeNode<T>`; using it on
  /// a tree whose nodes are not `TreeNode<T>` throws a [TypeError] while
  /// building. Every call returns a new function, so store the result when
  /// options must compare equal.
  static NodeComparator by<T>(
    int Function(TreeNode<T> a, TreeNode<T> b) compare,
  ) =>
      (a, b) => compare(a as TreeNode<T>, b as TreeNode<T>);

  static int _compareNatural(String a, String b) {
    final aLength = a.length;
    final bLength = b.length;
    var i = 0;
    var j = 0;
    while (i < aLength && j < bLength) {
      final aUnit = a.codeUnitAt(i);
      final bUnit = b.codeUnitAt(j);
      if (_isDigit(aUnit) && _isDigit(bUnit)) {
        var aEnd = i;
        while (aEnd < aLength && _isDigit(a.codeUnitAt(aEnd))) {
          aEnd++;
        }
        var bEnd = j;
        while (bEnd < bLength && _isDigit(b.codeUnitAt(bEnd))) {
          bEnd++;
        }
        // Compare the runs as numbers without parsing them: skip leading
        // zeros, then the longer run is larger, then compare digit by digit.
        var aStart = i;
        while (aStart < aEnd && a.codeUnitAt(aStart) == _zero) {
          aStart++;
        }
        var bStart = j;
        while (bStart < bEnd && b.codeUnitAt(bStart) == _zero) {
          bStart++;
        }
        final aDigits = aEnd - aStart;
        final bDigits = bEnd - bStart;
        if (aDigits != bDigits) return aDigits < bDigits ? -1 : 1;
        for (var k = 0; k < aDigits; k++) {
          final aDigit = a.codeUnitAt(aStart + k);
          final bDigit = b.codeUnitAt(bStart + k);
          if (aDigit != bDigit) return aDigit < bDigit ? -1 : 1;
        }
        i = aEnd;
        j = bEnd;
        continue;
      }
      // A digit run against another character compares by the digit's code
      // unit. Non-digits never fold into the digit range, so every digit
      // run sorts at the same place relative to a given character, which
      // keeps the order transitive.
      if (aUnit < 0x80 && bUnit < 0x80) {
        final aFolded = _lowerAscii(aUnit);
        final bFolded = _lowerAscii(bUnit);
        if (aFolded != bFolded) return aFolded < bFolded ? -1 : 1;
        i++;
        j++;
        continue;
      }
      final aCodePoint = _codePointAt(a, i);
      final bCodePoint = _codePointAt(b, j);
      final aKey = _orderKey(foldCodePoint(aCodePoint));
      final bKey = _orderKey(foldCodePoint(bCodePoint));
      if (aKey != bKey) return aKey < bKey ? -1 : 1;
      i += aCodePoint > 0xFFFF ? 2 : 1;
      j += bCodePoint > 0xFFFF ? 2 : 1;
    }
    final aRest = i < aLength ? 1 : 0;
    final bRest = j < bLength ? 1 : 0;
    return aRest - bRest;
  }

  static const int _zero = 0x30;

  static bool _isDigit(int unit) => unit >= _zero && unit <= 0x39;

  static int _lowerAscii(int unit) =>
      unit >= 0x41 && unit <= 0x5A ? unit + 0x20 : unit;

  /// The code point at [index] of [text]: a decoded surrogate pair, or the
  /// code unit itself (including an unpaired surrogate).
  static int _codePointAt(String text, int index) {
    final unit = text.codeUnitAt(index);
    if (unit & 0xFC00 != 0xD800 || index + 1 >= text.length) return unit;
    final low = text.codeUnitAt(index + 1);
    if (low & 0xFC00 != 0xDC00) return unit;
    return 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
  }

  /// A sort key for a folded code point that orders code points the way
  /// their UTF-16 encodings compare, so non-ASCII names keep the code unit
  /// order of [String.compareTo]: a supplementary code point starts with a
  /// surrogate (U+D800 to U+DBFF), so it sorts after U+0000 to U+D7FF and
  /// before U+E000 to U+FFFF. Unpaired surrogates keep their value, which
  /// is still a consistent total order. The largest key is below 2^21.
  static int _orderKey(int codePoint) =>
      codePoint >= 0xE000 && codePoint <= 0xFFFF
      ? codePoint + 0x110000
      : codePoint;
}
