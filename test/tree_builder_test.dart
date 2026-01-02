import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

void main() {
  group('TreeBuilder', () {
    late TreeBuilder builder;
    late List<TreeEntry> entries;

    setUp(() {
      builder = TreeBuilder();
      entries = const [
        TreeEntry(
          id: 'main',
          name: 'main.dart',
          fullPath: '/repo/lib/main.dart',
        ),
        TreeEntry(id: 'readme', name: 'README.md', fullPath: '/repo/README.md'),
        TreeEntry(
          id: 'virtual',
          name: 'Scratch.txt',
          fullPath: '/virtual/Scratch.txt',
          isVirtual: true,
        ),
      ];
    });

    test('creates the synthetic root nodes', () {
      final data = builder.build(
        entries: entries,
        sourceRoots: const ['/repo'],
      );

      expect(data.rootId, TreeBuilder.rootId);
      expect(data.nodes.containsKey(TreeBuilder.rootId), isTrue);
      expect(data.nodes.containsKey(TreeBuilder.treeRootId), isTrue);

      final treeRoot = data.nodes[TreeBuilder.treeRootId]!;
      expect(treeRoot.parentId, TreeBuilder.rootId);
      expect(treeRoot.childIds, isNotEmpty);
      expect(treeRoot.type, NodeType.folder);
    });

    test('groups files beneath the matching source root folders', () {
      final data = builder.build(
        entries: entries,
        sourceRoots: const ['/repo'],
      );

      final repoFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'repo',
      );
      expect(repoFolder.parentId, TreeBuilder.treeRootId);

      final libFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'lib',
      );
      expect(libFolder.parentId, repoFolder.id);

      final mainNode = data.nodes['node_main'];
      expect(mainNode, isNotNull);
      expect(mainNode!.parentId, libFolder.id);
      expect(mainNode.sourcePath, '/repo/lib/main.dart');
    });

    test('places virtual entries under the tree root', () {
      final data = builder.build(
        entries: entries,
        sourceRoots: const ['/repo'],
      );

      final virtualNode = data.nodes['node_virtual'];
      expect(virtualNode, isNotNull);
      expect(virtualNode!.parentId, TreeBuilder.treeRootId);
      expect(virtualNode.isVirtual, isTrue);
    });

    test('materializes anchors even when entries are empty', () {
      final data = builder.build(
        entries: const [],
        sourceRoots: const ['/repo'],
        autoPickVisibleRoot: false,
      );

      expect(data.nodes.containsKey(TreeBuilder.rootId), isTrue);
      expect(data.nodes.containsKey(TreeBuilder.treeRootId), isTrue);

      final repoFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'repo',
      );
      expect(repoFolder.parentId, TreeBuilder.treeRootId);
      expect(repoFolder.childIds, isEmpty);
      expect(repoFolder.origin, SelectionOrigin.inferred);
    });

    test('does not duplicate file nodes with the same id', () {
      const duplicate = TreeEntry(
        id: 'main',
        name: 'main.dart',
        fullPath: '/repo/lib/main.dart',
      );

      final data = builder.build(
        entries: [...entries, duplicate],
        sourceRoots: const ['/repo'],
      );

      final mainChildren = data.nodes.values
          .where((node) => node.entryId == 'main')
          .toList();

      expect(mainChildren.length, 1);
    });

    test('folder ids remain stable across rebuilds', () {
      final initial = builder.build(
        entries: entries,
        sourceRoots: const ['/repo'],
      );

      final repoFolder = initial.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'repo',
      );
      final libFolder = initial.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'lib',
      );

      final updated = builder.build(
        entries: [
          ...entries,
          const TreeEntry(
            id: 'service',
            name: 'client.dart',
            fullPath: '/repo/lib/services/api/client.dart',
          ),
        ],
        sourceRoots: const ['/repo'],
      );

      final repoFolderUpdated = updated.nodes[repoFolder.id];
      final libFolderUpdated = updated.nodes[libFolder.id];

      expect(repoFolderUpdated, isNotNull);
      expect(libFolderUpdated, isNotNull);

      final servicesFolder = updated.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'services',
      );
      final apiFolder = updated.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'api',
      );

      expect(servicesFolder.parentId, libFolderUpdated!.id);
      expect(apiFolder.parentId, servicesFolder.id);
      expect(updated.nodes['node_service'], isNotNull);
    });

    test('respects expandFoldersByDefault for nested folders', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'service',
            name: 'client.dart',
            fullPath: '/repo/lib/src/services/client.dart',
          ),
        ],
        sourceRoots: const ['/repo'],
        expandFoldersByDefault: false,
      );

      final folderNodes = data.nodes.values.where(
        (node) =>
            node.type == NodeType.folder && node.id != TreeBuilder.treeRootId,
      );

      expect(folderNodes, isNotEmpty);
      expect(folderNodes.every((node) => !node.isExpanded), isTrue);
    });

    test('populates sourcePath for nested folders when available', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'deep',
            name: 'deep.dart',
            fullPath: '/repo/lib/src/services/deep.dart',
          ),
        ],
        sourceRoots: const ['/repo'],
      );

      final repoFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'repo',
      );
      expect(repoFolder.sourcePath, '/repo');

      final libFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'lib',
      );
      expect(libFolder.sourcePath, '/repo/lib');

      final srcFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'src',
      );
      expect(srcFolder.sourcePath, '/repo/lib/src');
    });

    test('prevents folder id collisions for similar names', () {
      final data = builder.build(
        entries: [
          ...entries,
          const TreeEntry(
            id: 'hyphen',
            name: 'one.txt',
            fullPath: '/repo/foo-bar/one.txt',
          ),
          const TreeEntry(
            id: 'underscore',
            name: 'two.txt',
            fullPath: '/repo/foo_bar/two.txt',
          ),
        ],
        sourceRoots: const ['/repo'],
      );

      final hyphenFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'foo-bar',
      );
      final underscoreFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'foo_bar',
      );

      expect(hyphenFolder.id, isNot(underscoreFolder.id));
      expect(data.nodes[hyphenFolder.id]!.childIds, contains('node_hyphen'));
      expect(
        data.nodes[underscoreFolder.id]!.childIds,
        contains('node_underscore'),
      );
    });

    test('applies stripPrefixes to roots and nested folders', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'main',
            name: 'main.dart',
            fullPath: '/Users/me/project/lib/main.dart',
          ),
        ],
        sourceRoots: const ['/Users/me/project'],
        stripPrefixes: const ['/Users/me'],
      );

      final projectFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'project',
      );
      expect(projectFolder.parentId, TreeBuilder.treeRootId);
      expect(projectFolder.sourcePath, '/project');

      final libFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'lib',
      );
      expect(libFolder.sourcePath, '/project/lib');

      final mainNode = data.nodes['node_main'];
      expect(mainNode, isNotNull);
      expect(mainNode!.virtualPath, '/tree/project/lib/main.dart');
    });

    test('prefers the shallowest matching source root when configured', () {
      const nestedEntry = TreeEntry(
        id: 'nested',
        name: 'service.dart',
        fullPath: '/repo/lib/src/services/service.dart',
      );

      final data = builder.build(
        entries: [nestedEntry],
        sourceRoots: const ['/repo', '/repo/lib', '/repo/lib/src'],
        preferDeepestRoot: false,
      );

      final repoFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'repo',
      );
      expect(repoFolder.parentId, TreeBuilder.treeRootId);

      final libFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'lib',
      );
      expect(libFolder.parentId, repoFolder.id);

      final srcFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'src',
      );
      expect(srcFolder.parentId, libFolder.id);
    });

    test('auto-picks a visible root for a single child chain', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'linux_pubspec',
            name: 'pubspec.yaml',
            fullPath:
                '/Users/me/packages/url_launcher/url_launcher_linux/pubspec.yaml',
          ),
        ],
        sourceRoots: const ['/Users/me/packages/url_launcher'],
        stripPrefixes: const ['/Users/me'],
      );

      final visibleRoot = data.nodes[data.visibleRootId]!;
      expect(visibleRoot.type, NodeType.folder);
      expect(visibleRoot.name, 'url_launcher_linux');
    });

    test('visible root becomes the common parent when siblings appear', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'linux_pubspec',
            name: 'pubspec.yaml',
            fullPath:
                '/Users/me/packages/url_launcher/url_launcher_linux/pubspec.yaml',
          ),
          TreeEntry(
            id: 'ios_pubspec',
            name: 'pubspec.yaml',
            fullPath:
                '/Users/me/packages/url_launcher/url_launcher_ios/pubspec.yaml',
          ),
        ],
        sourceRoots: const ['/Users/me/packages/url_launcher'],
        stripPrefixes: const ['/Users/me'],
      );

      final visibleRoot = data.nodes[data.visibleRootId]!;
      expect(visibleRoot.type, NodeType.folder);
      expect(visibleRoot.name, 'url_launcher');
    });

    test('virtual entries do not block hoisting the visible root', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'file',
            name: 'main.dart',
            fullPath: '/repo/lib/main.dart',
          ),
          TreeEntry(
            id: 'scratch',
            name: 'Scratch.txt',
            fullPath: '/virtual/Scratch.txt',
            isVirtual: true,
          ),
        ],
        sourceRoots: const ['/repo'],
      );

      final visibleRoot = data.nodes[data.visibleRootId]!;
      expect(visibleRoot.type, NodeType.folder);
      expect(visibleRoot.name, 'lib');
    });

    test('stripPrefixes picks the most specific match', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'a',
            name: 'a.dart',
            fullPath: '/Users/me/project/lib/a.dart',
          ),
        ],
        sourceRoots: const ['/Users/me/project'],
        stripPrefixes: const ['/Users/me', '/Users/me/project'],
      );

      final projectFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name.contains('project'),
      );
      expect(projectFolder.sourcePath, '/project');

      final libFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'lib',
      );
      expect(libFolder.sourcePath, '/project/lib');
    });

    test('handles Windows drive letters by canonicalizing to POSIX-like', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'main',
            name: 'main.dart',
            fullPath: r'C:\repo\lib\main.dart',
          ),
        ],
        sourceRoots: const [r'C:\repo'],
        stripPrefixes: const [r'C:\'],
      );

      final repoFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name.contains('repo'),
      );
      expect(repoFolder.parentId, TreeBuilder.treeRootId);

      final mainNode = data.nodes['node_main']!;
      expect(mainNode.virtualPath, startsWith('/tree/'));
      expect(
        mainNode.sourcePath!.toLowerCase(),
        contains(r'c:\repo\lib\main.dart'.toLowerCase()),
      );
    });

    test('handles UNC network paths by normalizing separators', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'network',
            name: 'file.dart',
            fullPath: r'\server\share\lib\file.dart',
          ),
        ],
        sourceRoots: const [r'\server\share'],
      );

      final shareFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'share',
      );
      expect(shareFolder.parentId, TreeBuilder.treeRootId);

      final libFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'lib',
      );
      expect(libFolder.parentId, shareFolder.id);

      final fileNode = data.nodes['node_network']!;
      expect(fileNode.virtualPath, '/tree/share/lib/file.dart');
      expect(fileNode.sourcePath, contains(r'\server\share\lib\file.dart'));
    });

    test('two roots with the same basename become unique siblings', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'a',
            name: 'main.dart',
            fullPath: '/work/foo/lib/main.dart',
          ),
          TreeEntry(
            id: 'b',
            name: 'main.dart',
            fullPath: '/work/bar/lib/main.dart',
          ),
        ],
        sourceRoots: const ['/work/foo/lib', '/work/bar/lib'],
      );

      final topLevel = data.nodes[TreeBuilder.treeRootId]!;
      final children = topLevel.childIds
          .map((id) => data.nodes[id]!)
          .where((node) => node.type == NodeType.folder)
          .toList();

      expect(children.length, 2);
      final names = children.map((node) => node.name).toSet();
      expect(names.length, 2);
    });

    test('nested folder ids stay stable when sibling roots are added', () {
      final first = builder.build(
        entries: const [
          TreeEntry(
            id: 'srcFile',
            name: 'main.dart',
            fullPath: '/work/foo/lib/src/main.dart',
          ),
        ],
        sourceRoots: const ['/work/foo/lib'],
      );

      final srcFolder = first.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'src',
      );

      final second = builder.build(
        entries: const [
          TreeEntry(
            id: 'srcFile',
            name: 'main.dart',
            fullPath: '/work/foo/lib/src/main.dart',
          ),
          TreeEntry(
            id: 'other',
            name: 'main.dart',
            fullPath: '/work/bar/lib/main.dart',
          ),
        ],
        sourceRoots: const ['/work/foo/lib', '/work/bar/lib'],
      );

      final srcFolderSecond = second.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'src',
      );

      expect(srcFolderSecond.id, srcFolder.id);
    });

    test('virtual entries can be grouped under virtual folders', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'v',
            name: 'Scratch.txt',
            fullPath: '/virtual/Scratch.txt',
            isVirtual: true,
            metadata: {'virtualParent': 'notes/daily'},
          ),
        ],
        sourceRoots: const ['/repo'],
      );

      final notesFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'notes',
      );
      final dailyFolder = data.nodes.values.firstWhere(
        (node) =>
            node.type == NodeType.folder &&
            node.name == 'daily' &&
            node.parentId == notesFolder.id,
      );

      final virtualNode = data.nodes['node_v']!;
      expect(virtualNode.parentId, dailyFolder.id);
      expect(virtualNode.isVirtual, isTrue);
    });

    test('virtual parents merge into existing real folders', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'real',
            name: 'story.md',
            fullPath: '/repo/notes/story.md',
          ),
          TreeEntry(
            id: 'virtual',
            name: 'scratch.txt',
            fullPath: '/virtual/scratch.txt',
            isVirtual: true,
            metadata: {'virtualParent': 'repo/notes'},
          ),
        ],
        sourceRoots: const ['/repo'],
      );

      final notesFolders = data.nodes.values.where(
        (node) => node.type == NodeType.folder && node.name == 'notes',
      );
      final notesFolderList = notesFolders.toList();
      expect(notesFolderList.length, 1);
      final notesFolder = notesFolderList.single;
      final childEntryIds = notesFolder.childIds
          .map((id) => data.nodes[id]!)
          .where((node) => node.type == NodeType.file)
          .map((node) => node.entryId)
          .toSet();

      expect(childEntryIds, containsAll({'real', 'virtual'}));
    });

    test('real folders merge into previously virtual folders', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'virtual',
            name: 'scratch.txt',
            fullPath: '/virtual/scratch.txt',
            isVirtual: true,
            metadata: {'virtualParent': 'repo/docs'},
          ),
          TreeEntry(
            id: 'real',
            name: 'notes.md',
            fullPath: '/repo/docs/notes.md',
          ),
        ],
        sourceRoots: const ['/repo'],
      );

      final docsFolders = data.nodes.values.where(
        (node) => node.type == NodeType.folder && node.name == 'docs',
      );
      final docsFolderList = docsFolders.toList();
      expect(docsFolderList.length, 1);
      final docsFolder = docsFolderList.single;

      expect(docsFolder.sourcePath, '/repo/docs');

      final childEntryIds = docsFolder.childIds
          .map((id) => data.nodes[id]!)
          .where((node) => node.type == NodeType.file)
          .map((node) => node.entryId)
          .toSet();

      expect(childEntryIds, containsAll({'real', 'virtual'}));
    });

    test('virtualParent normalization removes navigation segments', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'virtual',
            name: 'scratch.txt',
            fullPath: '/virtual/scratch.txt',
            isVirtual: true,
            metadata: {'virtualParent': 'notes/../today//./'},
          ),
        ],
        sourceRoots: const ['/repo'],
      );

      final todayFolder = data.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.name == 'today',
      );
      final virtualNode = data.nodes['node_virtual']!;

      expect(virtualNode.parentId, todayFolder.id);
    });

    test('respects selectNewFilesByDefault', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'sel',
            name: 'selected.dart',
            fullPath: '/repo/lib/selected.dart',
          ),
        ],
        sourceRoots: const ['/repo'],
        selectNewFilesByDefault: false,
      );

      final node = data.nodes['node_sel']!;
      expect(node.isSelected, isFalse);
    });

    test('visible root respects maxLevels constraint', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'deep',
            name: 'a.dart',
            fullPath: '/repo/lib/src/a.dart',
          ),
        ],
        sourceRoots: const ['/repo'],
        visibleRootMaxHoistLevels: 1,
      );

      final visibleRoot = data.nodes[data.visibleRootId]!;
      expect(visibleRoot.type, NodeType.folder);
      expect(visibleRoot.name, 'repo');
    });

    test('visible root stops hoisting when virtual files are considered', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'real',
            name: 'main.dart',
            fullPath: '/repo/lib/main.dart',
          ),
          TreeEntry(
            id: 'virtual',
            name: 'note.txt',
            fullPath: '/virtual/note.txt',
            isVirtual: true,
          ),
        ],
        sourceRoots: const ['/repo'],
        visibleRootIgnoreVirtualFiles: false,
      );

      expect(data.visibleRootId, TreeBuilder.treeRootId);
    });

    test('handles empty sourceRoots by grouping on directory', () {
      final data = builder.build(
        entries: const [
          TreeEntry(id: 'a', name: 'a.dart', fullPath: '/x/y/a.dart'),
          TreeEntry(id: 'b', name: 'b.dart', fullPath: '/x/z/b.dart'),
        ],
        sourceRoots: const [],
      );

      final visibleRoot = data.nodes[data.visibleRootId]!;
      final childFolders = visibleRoot.childIds
          .map((id) => data.nodes[id]!)
          .where((node) => node.type == NodeType.folder)
          .toList();

      expect(childFolders.length, 2);
      final names = childFolders.map((node) => node.name).toSet();
      expect(names, containsAll({'y', 'z'}));
    });

    test('normalizes mismatched drive letter casing on Windows paths', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'main',
            name: 'main.dart',
            fullPath: r'c:\Repo\lib\main.dart',
          ),
        ],
        sourceRoots: const [r'C:\Repo'],
      );

      final repoFolder = data.nodes.values.firstWhere(
        (node) =>
            node.type == NodeType.folder && node.name.toLowerCase() == 'repo',
      );

      expect(repoFolder.parentId, TreeBuilder.treeRootId);
      expect(data.nodes['node_main'], isNotNull);
    });

    test('stripPrefixes does not require matching case on Windows drive', () {
      final data = builder.build(
        entries: const [
          TreeEntry(
            id: 'file',
            name: 'main.dart',
            fullPath: r'C:\repo\lib\main.dart',
          ),
        ],
        sourceRoots: const [r'c:\repo'],
        stripPrefixes: const [r'c:\'],
      );

      final repoFolder = data.nodes.values.firstWhere(
        (node) =>
            node.type == NodeType.folder && node.name.toLowerCase() == 'repo',
      );

      expect(repoFolder.sourcePath, '/repo');
    });

    test('build handles large trees without regressing structure', () {
      final largeBuilder = TreeBuilder();
      const totalEntries = 10000;
      final entries = List<TreeEntry>.generate(totalEntries, (index) {
        final pkg = index ~/ 100;
        return TreeEntry(
          id: 'file_$index',
          name: 'file_$index.dart',
          fullPath: '/repo/lib/pkg_$pkg/src/file_$index.dart',
        );
      });

      final first = largeBuilder.build(
        entries: entries,
        sourceRoots: const ['/repo'],
      );
      final second = largeBuilder.build(
        entries: entries,
        sourceRoots: const ['/repo'],
      );

      final fileNodes = first.nodes.values
          .where((node) => node.type == NodeType.file)
          .map((node) => node.entryId)
          .whereType<String>()
          .toSet();

      expect(fileNodes.length, totalEntries);
      expect(first.nodes.length, greaterThan(totalEntries));
      expect(second.nodes.length, first.nodes.length);
      expect(second.visibleRootId, first.visibleRootId);

      const samplePath = '/repo/lib/pkg_42/src';
      final sampleFolder = first.nodes.values.firstWhere(
        (node) => node.type == NodeType.folder && node.sourcePath == samplePath,
      );
      final sameFolder = second.nodes[sampleFolder.id];

      expect(sameFolder, isNotNull);
      expect(sameFolder!.sourcePath, samplePath);
    });
  });
}
