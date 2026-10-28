// A tour of package:directory_tree: build a tree, show it, search it,
// expand and collapse folders, select rows, and diff two row lists.
//
// Run it with `dart run example/example.dart`. It uses only the core
// library, so it also runs on the web.
import 'package:directory_tree/directory_tree.dart';

void main() {
  // Build a tree from paths. The order of the input does not matter, and
  // the directories in between (lib, src, test) are created automatically.
  final tree = DirectoryTree.fromPaths([
    '/repo/lib/src/tree.dart',
    '/repo/lib/src/tree.g.dart',
    '/repo/lib/main.dart',
    '/repo/test/tree_test.dart',
    '/repo/README.md',
  ]);
  print(tree); // DirectoryTree(roots: 1, nodes: 9, files: 5, issues: 0)

  // Render it like the `tree` command.
  print(tree.render());

  // Search: the rows keep the matches and the folders that lead to them,
  // and open those folders even when the view starts collapsed.
  final search = tree.flatten(
    expansion: const ExpansionState.collapsed(),
    filter: TreeQuery.parse('ext:dart !*.g.dart'),
  );
  print('search: ${search.map(_describe).join(', ')}');

  // Toggle a folder, as a click on its arrow does. Only the changed rows
  // are new objects; the others are reused.
  final rows = tree.flatten();
  final lib = tree.idOf('/repo/lib')!;
  final collapsed = rows.toggleNode(lib);
  print('collapsed lib: ${collapsed.map((row) => row.label).join(', ')}');
  print('last row reused: ${identical(collapsed.last, rows.last)}');

  // Select a range: a click on main.dart, then a shift-click on
  // tree_test.dart, in the order the rows show.
  var selection = const SelectionState.empty(mode: SelectionMode.multiple)
      .select(tree.idOf('/repo/lib/main.dart')!)
      .extendTo(
        tree.idOf('/repo/test/tree_test.dart')!,
        rows.map((row) => row.id),
      );
  print('range: ${selection.selected.map((id) => id.value).join(', ')}');

  // Check a folder with tri-state checkboxes: lib becomes checked and its
  // parent repo partial.
  selection = selection.clear().check(tree, lib);
  print('lib: ${selection.checkStateOf(tree, lib).name}');
  print('repo: ${selection.checkStateOf(tree, tree.roots.single).name}');

  // Diff two row lists, for an animated list: apply the removals, then the
  // insertions, in the order given.
  final diff = ListDiff.compute(rows, collapsed, keyOf: (row) => row.id);
  print('removed: ${diff.removedIndices}'); // removed: [5, 4, 3, 2]
  print('inserted: ${diff.insertedIndices}'); // inserted: []
  print('changed: ${diff.changedIndices}'); // changed: [1]
}

/// A row's label, with `*` after the labels that matched the search.
String _describe(TreeRow<Object?> row) =>
    row.isMatch ? '${row.label}*' : row.label;
