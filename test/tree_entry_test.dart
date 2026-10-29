import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

void main() {
  group('TreeEntry', () {
    test('file and directory constructors set the kind', () {
      const file = TreeEntry<int>.file('/a/b.txt', data: 3);
      expect(file.path, '/a/b.txt');
      expect(file.kind, TreeNodeKind.file);
      expect(file.isFile, isTrue);
      expect(file.isDirectory, isFalse);
      expect(file.data, 3);

      const directory = TreeEntry<int>.directory('/a');
      expect(directory.kind, TreeNodeKind.directory);
      expect(directory.isDirectory, isTrue);
      expect(directory.isFile, isFalse);
      expect(directory.data, isNull);
    });

    test('keeps the raw path exactly as given', () {
      const entry = TreeEntry<void>.file(r' C:\a\..\b ');
      expect(entry.path, r' C:\a\..\b ');
    });

    test('equality covers path, kind, and data', () {
      expect(
        const TreeEntry<int>.file('/a', data: 1),
        const TreeEntry<int>.file('/a', data: 1),
      );
      expect(
        const TreeEntry<int>.file('/a', data: 1).hashCode,
        const TreeEntry<int>.file('/a', data: 1).hashCode,
      );
      expect(
        const TreeEntry<int>.file('/a'),
        isNot(const TreeEntry<int>.directory('/a')),
      );
      expect(
        const TreeEntry<int>.file('/a', data: 1),
        isNot(const TreeEntry<int>.file('/a', data: 2)),
      );
      expect(
        const TreeEntry<int>.file('/a'),
        isNot(const TreeEntry<int>.file('/A')),
      );
    });

    test('the type argument is not compared', () {
      expect(
        const TreeEntry<int>.file('/a'),
        const TreeEntry<String>.file('/a'),
      );
      expect(
        const TreeEntry<int>.file('/a').hashCode,
        const TreeEntry<String>.file('/a').hashCode,
      );
    });

    test('toString shows kind, path, and data', () {
      expect(const TreeEntry<int>.file('/a').toString(), 'TreeEntry.file(/a)');
      expect(
        const TreeEntry<int>.directory('/a', data: 7).toString(),
        'TreeEntry.directory(/a, data: 7)',
      );
    });
  });

  group('TreeIssue', () {
    const entry = TreeEntry<int>.file('');
    const issue = TreeIssue<int>(
      kind: TreeIssueKind.invalidPath,
      path: '',
      entry: entry,
      message: 'Path is empty; the entry was skipped.',
    );

    test('exposes its fields', () {
      expect(issue.kind, TreeIssueKind.invalidPath);
      expect(issue.path, '');
      expect(issue.entry, entry);
      expect(issue.message, contains('empty'));
    });

    test('has value equality', () {
      const same = TreeIssue<int>(
        kind: TreeIssueKind.invalidPath,
        path: '',
        entry: entry,
        message: 'Path is empty; the entry was skipped.',
      );
      expect(same, issue);
      expect(same.hashCode, issue.hashCode);
      expect(
        const TreeIssue<int>(
          kind: TreeIssueKind.conflict,
          path: '',
          entry: entry,
          message: 'Path is empty; the entry was skipped.',
        ),
        isNot(issue),
      );
    });

    test('matches what the builder reports', () {
      final tree = DirectoryTree<int>.build(const [entry]);
      expect(tree.issues, [issue]);
    });

    test('toString names the kind and path', () {
      expect(
        issue.toString(),
        'TreeIssue.invalidPath(): Path is empty; the entry was skipped.',
      );
    });
  });

  group('NodeId', () {
    test('wraps the policy key and compares as a string', () {
      const id = NodeId('/a/b');
      expect(id.value, '/a/b');
      expect(id, const NodeId('/a/b'));
      expect(id.hashCode, '/a/b'.hashCode);
      expect(<NodeId, int>{id: 1}[NodeId('/a/${'b'}')], 1);
    });

    test('is non-nullable and usable as an Object', () {
      const Object asObject = NodeId('/x');
      expect(asObject, const NodeId('/x'));
      final built = NodeId(['', 'x'].join('/'));
      expect(<Object>{const NodeId('/x'), built}, hasLength(1));
    });

    test('round trips through its value', () {
      final tree = DirectoryTree.fromPaths(['/a/b.txt']);
      final saved = tree.roots.single.value;
      expect(tree[NodeId(saved)], tree.rootNodes.single);
    });
  });
}
