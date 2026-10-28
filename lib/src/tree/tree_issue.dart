import 'package:directory_tree/src/tree/directory_tree.dart';
import 'package:directory_tree/src/tree/tree_entry.dart';
import 'package:directory_tree/src/tree/tree_options.dart';
import 'package:meta/meta.dart';

/// Why an input was left out of a [DirectoryTree].
enum TreeIssueKind {
  /// A path could not be parsed (empty, NUL character, or a relative path
  /// escaping its root), or a file entry names a path root such as `/`.
  ///
  /// Also used for an unparseable path in [TreeRoots.fixed]; such issues
  /// have no [TreeIssue.entry].
  invalidPath,

  /// A file entry clashes with a directory at the same path: either another
  /// entry lies inside it (so the path must be a directory), or it equals a
  /// [TreeRoots.fixed] root. The directory wins and the file entry is
  /// dropped.
  conflict,

  /// With [TreeRoots.fixed], an entry lies outside every root and was
  /// dropped.
  outsideRoots,
}

/// A problem found while building a [DirectoryTree], describing an input
/// that was skipped.
///
/// Building never throws for bad input; it collects issues in
/// [DirectoryTree.issues] instead, in input order, so you can surface them
/// (for example as warnings next to a file picker) or ignore them.
@immutable
final class TreeIssue<T> {
  /// Creates an issue of [kind] about the raw [path].
  ///
  /// The builder creates issues; constructing one yourself is mainly useful
  /// for comparing against [DirectoryTree.issues] in tests.
  const TreeIssue({
    required this.kind,
    required this.path,
    required this.message,
    this.entry,
  });

  /// What went wrong.
  final TreeIssueKind kind;

  /// The raw path involved, exactly as it was given.
  final String path;

  /// The entry that was skipped, or `null` when the issue is about a
  /// [TreeRoots.fixed] path rather than an entry.
  final TreeEntry<T>? entry;

  /// A human-readable explanation in stable wording, suitable for logs and
  /// tooltips.
  final String message;

  /// Whether [other] is a [TreeIssue] with equal fields.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TreeIssue<Object?> &&
          other.kind == kind &&
          other.path == path &&
          other.entry == entry &&
          other.message == message;

  @override
  int get hashCode => Object.hash(kind, path, entry, message);

  @override
  String toString() => 'TreeIssue.${kind.name}($path): $message';
}
