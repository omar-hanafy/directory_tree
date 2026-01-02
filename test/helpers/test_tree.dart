import 'package:directory_tree/directory_tree.dart';

TreeData buildTestTreeData() {
  final nodes = <String, TreeNode>{
    'root': TreeNode(
      id: 'root',
      name: 'Root',
      type: NodeType.root,
      parentId: '',
      virtualPath: '/',
      childIds: const ['home'],
      isExpanded: true,
    ),
    'home': TreeNode(
      id: 'home',
      name: 'home',
      type: NodeType.folder,
      parentId: 'root',
      virtualPath: '/home',
      childIds: const ['docs', 'pictures', 'readme'],
      isExpanded: true,
    ),
    'docs': TreeNode(
      id: 'docs',
      name: 'docs',
      type: NodeType.folder,
      parentId: 'home',
      virtualPath: '/home/docs',
      childIds: const ['notes', 'draft'],
    ),
    'pictures': TreeNode(
      id: 'pictures',
      name: 'pictures',
      type: NodeType.folder,
      parentId: 'home',
      virtualPath: '/home/pictures',
      childIds: const ['vacation'],
    ),
    'readme': TreeNode(
      id: 'readme',
      name: 'README.md',
      type: NodeType.file,
      parentId: 'home',
      virtualPath: '/home/README.md',
      entryId: 'entry-readme',
    ),
    'notes': TreeNode(
      id: 'notes',
      name: 'notes.txt',
      type: NodeType.file,
      parentId: 'docs',
      virtualPath: '/home/docs/notes.txt',
      entryId: 'entry-notes',
    ),
    'draft': TreeNode(
      id: 'draft',
      name: 'draft.md',
      type: NodeType.file,
      parentId: 'docs',
      virtualPath: '/home/docs/draft.md',
      entryId: 'entry-draft',
    ),
    'vacation': TreeNode(
      id: 'vacation',
      name: 'vacation.png',
      type: NodeType.file,
      parentId: 'pictures',
      virtualPath: '/home/pictures/vacation.png',
      entryId: 'entry-vacation',
    ),
  };

  return TreeData(nodes: nodes, rootId: 'root', visibleRootId: 'home');
}
