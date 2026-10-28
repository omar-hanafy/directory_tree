import 'package:directory_tree/src/path/path_policy.dart';
import 'package:directory_tree/src/tree/directory_tree.dart';
import 'package:directory_tree/src/tree/tree_issue.dart';
import 'package:meta/meta.dart';

/// Whether a tree node or entry is a file or a directory.
enum TreeNodeKind {
  /// A leaf that can never have children.
  file,

  /// A container whose children are listed in `DirectoryNode.children`.
  directory,
}

/// One input item for a [DirectoryTree]: a raw path, its kind, and optional
/// user data.
///
/// Entries are what you feed to [DirectoryTree.build] or a
/// [DirectoryTreeBuilder]. [path] stays exactly as you passed it; the tree's
/// [PathPolicy] parses it at build time. A path that fails to parse does not
/// throw: the build reports it as a [TreeIssue] and skips it.
///
/// Directories that are not listed as entries but contain entries are
/// created automatically (inferred), so listing only files is enough. Add a
/// directory entry to keep an empty directory, to attach [data] to a
/// directory, or to make it explicit (`TreeNode.isExplicit`).
///
/// ```dart
/// final tree = DirectoryTree.build([
///   TreeEntry.file('/repo/lib/main.dart', data: 1024),
///   TreeEntry.directory('/repo/assets'),
/// ]);
/// ```
@immutable
final class TreeEntry<T> {
  /// Creates a file entry for [path] carrying optional [data].
  ///
  /// A file entry whose path is a path root (`/`, `C:`) is reported as an
  /// invalid path, and one that is an ancestor of another entry is reported
  /// as a conflict (the directory wins).
  const TreeEntry.file(this.path, {this.data}) : kind = TreeNodeKind.file;

  /// Creates a directory entry for [path] carrying optional [data].
  ///
  /// The directory appears in the tree even when no other entry is inside
  /// it.
  const TreeEntry.directory(this.path, {this.data})
    : kind = TreeNodeKind.directory;

  /// The raw path as given, parsed by the tree's [PathPolicy] at build time.
  final String path;

  /// Whether this entry describes a file or a directory.
  final TreeNodeKind kind;

  /// Optional user data, exposed again as `TreeNode.data`.
  ///
  /// Data takes part in [operator ==], so give it value equality when you
  /// compare trees or entries.
  final T? data;

  /// Whether [kind] is [TreeNodeKind.file].
  bool get isFile => kind == TreeNodeKind.file;

  /// Whether [kind] is [TreeNodeKind.directory].
  bool get isDirectory => kind == TreeNodeKind.directory;

  /// Whether [other] is a [TreeEntry] with an equal [path], [kind], and
  /// [data].
  ///
  /// The type argument is not compared, so `TreeEntry<int>.file('a')` equals
  /// `TreeEntry<String>.file('a')`.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TreeEntry<Object?> &&
          other.path == path &&
          other.kind == kind &&
          other.data == data;

  @override
  int get hashCode => Object.hash(path, kind, data);

  @override
  String toString() {
    final name = isFile ? 'file' : 'directory';
    return data == null
        ? 'TreeEntry.$name($path)'
        : 'TreeEntry.$name($path, data: $data)';
  }
}
