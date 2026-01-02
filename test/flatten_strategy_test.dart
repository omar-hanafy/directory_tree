import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

import 'helpers/test_tree.dart';

void main() {
  group('DefaultFlattenStrategy', () {
    test('respects expansion state when flattening', () {
      final tree = buildTestTreeData();
      const strategy = DefaultFlattenStrategy();

      final visible = strategy.flatten(
        data: tree,
        expandedIds: {'home', 'docs'},
      );

      expect(
        visible.map((n) => n.id).toList(),
        equals(['home', 'docs', 'notes', 'draft', 'pictures', 'readme']),
      );
      expect(visible.map((n) => n.depth).toList(), equals([0, 1, 2, 2, 1, 1]));
    });

    test('includes matches and ancestors when filtering', () {
      final tree = buildTestTreeData();
      const strategy = DefaultFlattenStrategy();

      final visible = strategy.flatten(
        data: tree,
        expandedIds: const {},
        filterQuery: 'vacation',
      );

      expect(
        visible.map((n) => n.id).toList(growable: false),
        equals(['home', 'pictures', 'vacation']),
      );
      expect(
        visible.map((n) => n.depth).toList(growable: false),
        equals([0, 1, 2]),
      );
    });

    test('honors extension and negation filters while hoisting ancestors', () {
      final tree = buildTestTreeData();
      const strategy = DefaultFlattenStrategy();

      final visible = strategy.flatten(
        data: tree,
        expandedIds: const {},
        filterQuery: 'ext:txt !draft',
      );

      expect(
        visible.map((n) => n.id).toList(growable: false),
        equals(['home', 'docs', 'notes']),
      );
      expect(
        visible.map((n) => n.depth).toList(growable: false),
        equals([0, 1, 2]),
      );
    });
  });

  group('SortedFlattenStrategy', () {
    test('sorts children using delegate order', () {
      final tree = buildTestTreeData();
      const strategy = SortedFlattenStrategy(AlphaSortDelegate());

      final visible = strategy.flatten(
        data: tree,
        expandedIds: {'home', 'docs'},
      );

      expect(
        visible.map((n) => n.id).toList(),
        equals(['home', 'docs', 'draft', 'notes', 'pictures', 'readme']),
      );
    });

    test('AlphaSortDelegate keeps folders before files ignoring case', () {
      final nodes = <String, TreeNode>{
        'root': TreeNode(
          id: 'root',
          name: 'Root',
          type: NodeType.root,
          parentId: '',
          virtualPath: '/',
          childIds: const ['visible'],
          isExpanded: true,
        ),
        'visible': TreeNode(
          id: 'visible',
          name: 'root',
          type: NodeType.folder,
          parentId: 'root',
          virtualPath: '/root',
          childIds: const ['folderB', 'foldera', 'fileA', 'fileb'],
          isExpanded: true,
        ),
        'folderB': TreeNode(
          id: 'folderB',
          name: 'Beta',
          type: NodeType.folder,
          parentId: 'visible',
          virtualPath: '/root/Beta',
          childIds: const [],
        ),
        'foldera': TreeNode(
          id: 'foldera',
          name: 'alpha',
          type: NodeType.folder,
          parentId: 'visible',
          virtualPath: '/root/alpha',
          childIds: const [],
        ),
        'fileA': TreeNode(
          id: 'fileA',
          name: 'App.dart',
          type: NodeType.file,
          parentId: 'visible',
          virtualPath: '/root/App.dart',
        ),
        'fileb': TreeNode(
          id: 'fileb',
          name: 'beta.dart',
          type: NodeType.file,
          parentId: 'visible',
          virtualPath: '/root/beta.dart',
        ),
      };

      final tree = TreeData(
        nodes: nodes,
        rootId: 'root',
        visibleRootId: 'visible',
      );

      const strategy = SortedFlattenStrategy(AlphaSortDelegate());
      final visible = strategy.flatten(
        data: tree,
        expandedIds: const {'visible'},
      );

      expect(
        visible.map((n) => n.id).toList(growable: false),
        equals(['visible', 'foldera', 'folderB', 'fileA', 'fileb']),
      );
      expect(
        visible.map((n) => n.name).toList(growable: false),
        equals(['root', 'alpha', 'Beta', 'App.dart', 'beta.dart']),
      );
    });
  });
}
