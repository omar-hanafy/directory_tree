import 'package:path/path.dart' as p;

/// Defines a single item to be placed in the tree.
///
/// [TreeEntry] is the atomic unit of input for the [TreeBuilder]. It represents
/// a file or entity that needs to be positioned within the hierarchy based on its path.
///
/// ### Behavior
/// *   **Identity:** The [id] must be stable (e.g., a database PK or file path) to
///     persist selection states across tree rebuilds.
/// *   **Positioning:** [fullPath] determines where this item appears in the
///     generated [TreeData].
/// *   **Virtualization:** If [isVirtual] is true, the builder treats it as an
///     in-memory entity, useful for "New File" placeholders.
class TreeEntry {
  /// Creates a new [TreeEntry].
  const TreeEntry({
    required this.id,
    required this.name,
    required this.fullPath,
    this.isVirtual = false,
    this.metadata,
  });

  /// Stable id (e.g., your ScannedFile.id).
  final String id;

  /// Display name (basename).
  final String name;

  /// Absolute or canonical source path.
  final String fullPath;

  /// Created in-app, not a physical file.
  final bool isVirtual;

  /// Arbitrary key-value data to attach to this entry.
  ///
  /// Useful for storing auxiliary information like file sizes, error states,
  /// SCM status (e.g., modified/added), or custom icons. The builder does not
  /// inspect these values except for `virtualParent` (used to place virtual files).
  final Map<String, Object?>? metadata;

  /// Returns the file extension in lowercase.
  String get extension => p.extension(name).toLowerCase();
}
