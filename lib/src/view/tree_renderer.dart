import 'package:directory_tree/src/filter/tree_filter.dart';
import 'package:directory_tree/src/tree/directory_tree.dart';
import 'package:directory_tree/src/view/expansion_state.dart';
import 'package:directory_tree/src/view/tree_rows.dart';
import 'package:meta/meta.dart';

/// The connector strings that [DirectoryTree.render] draws in front of each
/// row.
///
/// A row at depth `d >= 1` is prefixed, for each ancestor level `1` to
/// `d - 1`, with [pipe] when that ancestor has a later visible sibling and
/// [gap] otherwise, then with [lastBranch] when the row is the last of its
/// siblings and [branch] otherwise. Top-level rows get no prefix. All four
/// strings should have the same width so columns line up.
///
/// The presets render the same tree as follows:
///
/// ```text
/// unicode           ascii             indent
/// repo/             repo/             repo/
/// ├── lib/          |-- lib/            lib/
/// │   └── main.dart |   `-- main.dart     main.dart
/// └── README.md     `-- README.md       README.md
/// ```
///
/// Create your own style for other looks, for example
/// `TreeStyle(branch: '+-- ', lastBranch: "'-- ", pipe: '|   ', gap: '    ')`.
@immutable
final class TreeStyle {
  /// Creates a style from its four connector strings.
  ///
  /// The strings are used as given, without validation; empty strings are
  /// allowed and simply draw nothing.
  const TreeStyle({
    required this.branch,
    required this.lastBranch,
    required this.pipe,
    required this.gap,
  });

  /// Drawn before a row that has a later sibling, such as `├── `.
  final String branch;

  /// Drawn before the last row among its siblings, such as `└── `.
  final String lastBranch;

  /// Drawn in an ancestor column whose ancestor has a later sibling, so the
  /// vertical line continues, such as `│   `.
  final String pipe;

  /// Drawn in an ancestor column whose ancestor is the last of its
  /// siblings, where no line continues, such as four spaces.
  final String gap;

  /// Box-drawing connectors (`├── `, `└── `, `│   `), the look of the
  /// `tree` command. The default of [DirectoryTree.render].
  static const TreeStyle unicode = TreeStyle(
    branch: '├── ',
    lastBranch: '└── ',
    pipe: '│   ',
    gap: '    ',
  );

  /// Plain ASCII connectors (`|-- `, `` `-- ``, `|   `), for terminals and
  /// logs without Unicode support.
  static const TreeStyle ascii = TreeStyle(
    branch: '|-- ',
    lastBranch: '`-- ',
    pipe: '|   ',
    gap: '    ',
  );

  /// Two spaces per level and no lines, for a compact outline.
  static const TreeStyle indent = TreeStyle(
    branch: '  ',
    lastBranch: '  ',
    pipe: '  ',
    gap: '  ',
  );

  /// Whether [other] is a [TreeStyle] with the same four strings.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TreeStyle &&
          other.branch == branch &&
          other.lastBranch == lastBranch &&
          other.pipe == pipe &&
          other.gap == gap;

  @override
  int get hashCode => Object.hash(branch, lastBranch, pipe, gap);

  /// `TreeStyle.unicode`, `TreeStyle.ascii`, or `TreeStyle.indent` for the
  /// presets, otherwise the four strings, quoted.
  @override
  String toString() {
    if (this == unicode) return 'TreeStyle.unicode';
    if (this == ascii) return 'TreeStyle.ascii';
    if (this == indent) return 'TreeStyle.indent';
    return "TreeStyle(branch: '$branch', lastBranch: '$lastBranch', "
        "pipe: '$pipe', gap: '$gap')";
  }
}

/// Renders [tree] as text; the implementation of [DirectoryTree.render].
///
/// Package-internal: call [DirectoryTree.render] instead.
@internal
String renderTree<T>(
  DirectoryTree<T> tree, {
  required TreeStyle style,
  required ExpansionState expansion,
  required TreeFilter? filter,
  required bool compactFolders,
  required bool showRoots,
  required int? maxDepth,
  required String Function(TreeRow<T> row)? label,
}) {
  final rows = renderRows<T>(
    tree,
    expansion: expansion,
    filter: filter,
    compactFolders: compactFolders,
    showRoots: showRoots,
    maxDepth: maxDepth,
  );
  final buffer = StringBuffer();
  // prefixes[d] is the guide columns 1..d-1 shared by the rows at depth d.
  // Rows arrive in pre-order, so when a row is reached, prefixes[depth] was
  // last written by its own parent row. Building each prefix from the
  // parent's keeps the work proportional to the output, without
  // materializing TreeRow.guides for every row.
  final prefixes = <String>['', ''];
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index]!;
    final depth = row.depth;
    if (index > 0) buffer.write('\n');
    if (depth > 0) {
      buffer
        ..write(prefixes[depth])
        ..write(row.isLast ? style.lastBranch : style.branch);
    }
    buffer.write(label == null ? _defaultLabel(row) : label(row));
    final next = index + 1;
    if (depth > 0 && next < rows.length && rows[next]!.depth == depth + 1) {
      final childPrefix =
          prefixes[depth] + (row.isLast ? style.gap : style.pipe);
      if (depth + 1 < prefixes.length) {
        prefixes[depth + 1] = childPrefix;
      } else {
        prefixes.add(childPrefix);
      }
    }
  }
  return buffer.toString();
}

/// [TreeRow.label] with control characters escaped (see [_escapeLabel]),
/// plus `/` for directories unless the label already ends with one (the
/// POSIX root `/`).
String _defaultLabel(TreeRow<Object?> row) {
  final text = _escapeLabel(row.label);
  return row.node.isDirectory && !text.endsWith('/') ? '$text/' : text;
}

/// [label] with every character that could break a line or drive a
/// terminal replaced by a visible escape; [label] itself when it has none.
///
/// File names may contain any character except `/` and NUL, so a scanned
/// directory can hold a name with a line break (which would split one row
/// over two lines) or an ESC sequence (which a terminal would execute, for
/// example to recolor text or move the cursor). The escapes are C-like,
/// but `\x` always takes exactly two hex digits, so `\x1Bb` reads as ESC
/// followed by `b`:
///
/// * `\n`, `\r`, and `\t` for line feed, carriage return, and tab;
/// * `\xHH` (two uppercase hex digits) for the other C0 controls U+0000 to
///   U+001F, for DEL U+007F, and for the C1 controls U+0080 to U+009F,
///   such as `\x1B` for ESC and `\x9B` for CSI;
/// * `\u2028` and `\u2029` for the Unicode line and paragraph separators;
/// * `\\` for a backslash, so an escape in the output always stands for one
///   character: the name `a\nb` (with a backslash) renders as `a\\nb`, a
///   name with a line feed as `a\nb`.
///
/// Every other character, including non-ASCII letters, is kept as is. Runs
/// in O(length of [label]); returns [label] without copying when nothing
/// needs escaping.
String _escapeLabel(String label) {
  var index = 0;
  while (index < label.length && !_needsEscape(label.codeUnitAt(index))) {
    index++;
  }
  if (index == label.length) return label;
  final buffer = StringBuffer(label.substring(0, index));
  for (; index < label.length; index++) {
    final unit = label.codeUnitAt(index);
    if (!_needsEscape(unit)) {
      buffer.writeCharCode(unit);
      continue;
    }
    buffer.write(switch (unit) {
      0x0A => r'\n',
      0x0D => r'\r',
      0x09 => r'\t',
      0x5C => r'\\',
      0x2028 => r'\u2028',
      0x2029 => r'\u2029',
      _ => '\\x${unit.toRadixString(16).toUpperCase().padLeft(2, '0')}',
    });
  }
  return buffer.toString();
}

/// Whether [_escapeLabel] replaces the UTF-16 code unit [unit]. Surrogates
/// never match, so a character outside the BMP is copied unit by unit.
bool _needsEscape(int unit) =>
    unit < 0x20 ||
    (unit >= 0x7F && unit <= 0x9F) ||
    unit == 0x5C ||
    unit == 0x2028 ||
    unit == 0x2029;
