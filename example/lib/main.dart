import 'package:directory_tree/directory_tree.dart';

void main() {
  final builder = TreeBuilder();
  final entries = <TreeEntry>[
    const TreeEntry(
      id: 'app_main',
      name: 'main.dart',
      fullPath: '/Users/me/directory_tree_example/lib/main.dart',
    ),
    const TreeEntry(
      id: 'app_router',
      name: 'router.dart',
      fullPath: '/Users/me/directory_tree_example/lib/src/router.dart',
    ),
    const TreeEntry(
      id: 'app_service',
      name: 'auth_service.dart',
      fullPath:
          '/Users/me/directory_tree_example/lib/src/services/auth_service.dart',
    ),
    const TreeEntry(
      id: 'notes',
      name: 'ReleaseNotes.md',
      fullPath: '/virtual/ReleaseNotes.md',
      isVirtual: true,
    ),
  ];

  final tree = builder.build(
    entries: entries,
    sourceRoots: const ['/Users/me/directory_tree_example'],
    stripPrefixes: const ['/Users/me'],
    expandFoldersByDefault: true,
  );

  final visibleRoot = tree.nodes[tree.visibleRootId]!;
  print('Visible tree from "${visibleRoot.name}":\n');
  _printTree(tree, tree.visibleRootId, '');

  print('\nFull tree (including synthetic root):\n');
  _printTree(tree, TreeBuilder.treeRootId, '');

  // --- New: flatten + filter + diff in pure Dart ---------------------------
  final strategy = DefaultFlattenStrategy();
  final expandedIds = tree.nodes.values
      .where((n) => n.type != NodeType.file)
      .map((n) => n.id)
      .toSet();

  final baseline = strategy.flatten(data: tree, expandedIds: expandedIds);

  print('\nBaseline visible rows:');
  for (final node in baseline) {
    final indent = '  ' * node.depth;
    final marker = node.isVirtual ? ' (virtual)' : '';
    print('$indent- ${node.name}$marker');
  }

  final filtered = strategy.flatten(
    data: tree,
    expandedIds: expandedIds,
    filterQuery: 'service',
  );

  print('\nFiltered by "service":');
  for (final node in filtered) {
    final indent = '  ' * node.depth;
    print('$indent- ${node.name}');
  }

  final diff = diffVisibleNodes(baseline, filtered);
  print('\nDiff (baseline → filtered)');
  print('  remove indices (desc): ${diff.removeIndicesDesc}');
  print('  insert indices (asc): ${diff.insertIndicesAsc}');
}

void _printTree(TreeData tree, String nodeId, String indent) {
  final node = tree.nodes[nodeId]!;
  if (node.type != NodeType.root) {
    final suffix = switch (node.type) {
      NodeType.folder => '/',
      NodeType.file => node.isVirtual ? ' (virtual)' : '',
      NodeType.root => '',
    };
    print('$indent${node.name}$suffix');
    indent += '  ';
  }

  for (final childId in node.childIds) {
    _printTree(tree, childId, indent);
  }
}
