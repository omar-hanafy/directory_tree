/// The directory_tree 1.0.0 benchmark subject.
library;

import 'package:directory_tree/directory_tree.dart';
import 'package:directory_tree_bench_harness/harness.dart';

/// Creates the v1 subject. Sent to child isolates by the harness.
BenchSubject createV1Subject(Workload workload) => V1Subject(workload);

/// Measures directory_tree 1.0.0 through its public API with default
/// options, the way an application would call it.
class V1Subject extends BenchSubject {
  /// Creates a subject for [workload].
  V1Subject(this.workload);

  /// The workload under test.
  final Workload workload;

  static const _strategy = DefaultFlattenStrategy();

  /// One non-virtual entry per path (id = path, name = basename).
  late final List<TreeEntry> entries = [
    for (final path in workload.paths)
      TreeEntry(
        id: path,
        name: path.substring(path.lastIndexOf('/') + 1),
        fullPath: path,
      ),
  ];

  TreeData? _tree;

  /// The built tree (built on first use, or kept from the first build run).
  TreeData get tree => _tree ??= _build();

  /// Every folder id, so flattening shows the whole tree.
  late final Set<String> allFolderIds = {
    for (final node in tree.nodes.values)
      if (node.type != NodeType.file) node.id,
  };

  /// The id of the folder whose source path is [Workload.toggleTarget].
  late final String toggleId = tree.nodes.values
      .firstWhere(
        (n) =>
            n.type == NodeType.folder && n.sourcePath == workload.toggleTarget,
        orElse: () => throw StateError(
          'toggle target ${workload.toggleTarget} not found in the v1 tree',
        ),
      )
      .id;

  /// [allFolderIds] without the toggle target: what the expansion set looks
  /// like after the user collapses it.
  late final Set<String> collapsedIds = {...allFolderIds}..remove(toggleId);

  /// Rows with everything expanded.
  late final List<VisibleNode> fullRows = _flatten(allFolderIds);

  /// Rows after collapsing the toggle target.
  late final List<VisibleNode> toggledRows = _flatten(collapsedIds);

  TreeData _build() => TreeBuilder().build(entries: entries);

  List<VisibleNode> _flatten(Set<String> expanded, {String? query}) =>
      _strategy.flatten(data: tree, expandedIds: expanded, filterQuery: query);

  @override
  void setUp(String operation) {
    _readEveryRowField();
    switch (operation) {
      case 'build':
        entries;
      case 'flatten':
      case 'filter':
        allFolderIds;
      case 'toggle':
      case 'toggle_full':
        collapsedIds;
        fullRows;
      case 'diff':
        fullRows;
        toggledRows;
      default:
        throw ArgumentError.value(operation, 'operation');
    }
  }

  @override
  Map<String, Object> run(String operation) {
    switch (operation) {
      case 'build':
        final data = _build();
        _tree ??= data;
        return {'nodes': data.nodes.length};
      case 'flatten':
        return {'rows': _flatten(allFolderIds).length};
      case 'toggle':
      case 'toggle_full':
        // v1 has no incremental API: collapsing always means a full
        // re-flatten, so both toggle operations measure the same call.
        final rows = _flatten(collapsedIds);
        return {
          'rows': rows.length,
          'hidden_rows': fullRows.length - rows.length,
        };
      case 'filter':
        final rows = _flatten(allFolderIds, query: workload.filterQuery);
        return {'rows': rows.length};
      case 'diff':
        final diff = diffVisibleNodes(fullRows, toggledRows);
        return {
          'removed': diff.removeIndicesDesc.length,
          'inserted': diff.insertIndicesAsc.length,
        };
      default:
        throw ArgumentError.value(operation, 'operation');
    }
  }
}

/// Reads every [VisibleNode] field once, on a tiny tree, so the compiled
/// benchmark keeps the rows an application gets.
///
/// AOT compilation drops object fields that the program never reads. The
/// timed operations read only `VisibleNode.id`, so without this read a v1
/// row would shrink from 96 to 16 bytes and `flatten` would allocate
/// several times less than in any application that draws rows. It runs in
/// the untimed set-up, and the checksum check keeps the reads alive.
void _readEveryRowField() {
  final data = TreeBuilder().build(
    entries: [
      TreeEntry(id: '/a/b.txt', name: 'b.txt', fullPath: '/a/b.txt'),
      TreeEntry(id: '/a/c/d.txt', name: 'd.txt', fullPath: '/a/c/d.txt'),
    ],
  );
  final rows = const DefaultFlattenStrategy().flatten(
    data: data,
    expandedIds: {for (final node in data.nodes.values) node.id},
  );
  var checksum = 0;
  for (final row in rows) {
    checksum ^=
        row.id.hashCode ^
        row.depth ^
        row.name.hashCode ^
        row.type.index ^
        (row.hasChildren ? 1 : 0) ^
        row.virtualPath.hashCode ^
        (row.entryId?.hashCode ?? 0) ^
        (row.isVirtual ? 2 : 0) ^
        (row.sourcePath?.hashCode ?? 0) ^
        row.origin.index;
  }
  if (checksum == -1) throw StateError('unreachable checksum');
}
