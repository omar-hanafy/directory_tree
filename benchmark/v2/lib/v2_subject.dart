/// The directory_tree 2.0.0 benchmark subject.
library;

import 'package:directory_tree/directory_tree.dart';
import 'package:directory_tree_bench_harness/harness.dart';

/// Creates the v2 subject. Sent to child isolates by the harness.
BenchSubject createV2Subject(Workload workload) => V2Subject(workload);

/// Measures directory_tree 2.0.0 through its public API with default
/// options, the way an application would call it.
class V2Subject extends BenchSubject {
  /// Creates a subject for [workload].
  V2Subject(this.workload);

  /// The workload under test.
  final Workload workload;

  /// One file entry per path, matching v1's entry-based build.
  late final List<TreeEntry<Never>> entries = [
    for (final path in workload.paths) TreeEntry<Never>.file(path),
  ];

  DirectoryTree<Never>? _tree;

  /// The built tree (built on first use, or kept from the first build run).
  DirectoryTree<Never> get tree => _tree ??= _build();

  /// The id of [Workload.toggleTarget].
  late final NodeId toggleId =
      tree.idOf(workload.toggleTarget) ??
      (throw StateError(
        'toggle target ${workload.toggleTarget} not found in the v2 tree',
      ));

  /// The expansion state after collapsing the toggle target.
  late final ExpansionState collapsedExpansion = const ExpansionState.expanded()
      .collapse(toggleId);

  /// The filter for [Workload.filterQuery].
  late final TreeQuery query = TreeQuery.parse(workload.filterQuery);

  /// Rows with everything expanded (the default expansion state).
  late final TreeRows<Never> fullRows = tree.flatten();

  /// Rows after the incremental collapse of the toggle target.
  late final TreeRows<Never> collapsedRows = fullRows.collapseNode(toggleId);

  DirectoryTree<Never> _build() => DirectoryTree<Never>.build(entries);

  @override
  void setUp(String operation) {
    switch (operation) {
      case 'build':
        entries;
      case 'flatten':
        tree;
      case 'toggle':
        // TreeRows is immutable, so every run collapses the same expanded
        // rows; no beforeRun reset is needed.
        toggleId;
        fullRows;
      case 'toggle_full':
        collapsedExpansion;
        fullRows;
      case 'filter':
        // Build the tree here, as v1's set-up does, so no timed run
        // includes the build (even with --warmup 0).
        tree;
        query;
      case 'diff':
        fullRows;
        collapsedRows;
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
        return {'nodes': data.length};
      case 'flatten':
        return {'rows': tree.flatten().length};
      case 'toggle':
        final rows = fullRows.collapseNode(toggleId);
        return {
          'rows': rows.length,
          'hidden_rows': fullRows.length - rows.length,
        };
      case 'toggle_full':
        final rows = tree.flatten(expansion: collapsedExpansion);
        return {
          'rows': rows.length,
          'hidden_rows': fullRows.length - rows.length,
        };
      case 'filter':
        return {'rows': tree.flatten(filter: query).length};
      case 'diff':
        final diff = ListDiff.compute(
          fullRows,
          collapsedRows,
          keyOf: (row) => row.id,
        );
        return {
          'removed': diff.removedIndices.length,
          'inserted': diff.insertedIndices.length,
        };
      default:
        throw ArgumentError.value(operation, 'operation');
    }
  }
}
