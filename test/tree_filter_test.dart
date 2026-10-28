import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

/// A filter with fixed answers that counts how often it is consulted.
class CountingFilter extends TreeFilter {
  CountingFilter({required this.result, this.all = false});

  final bool result;
  final bool all;
  int calls = 0;

  @override
  bool matches(TreeNode<Object?> node) {
    calls++;
    return result;
  }

  @override
  bool get matchesAll => all;
}

void main() {
  final tree = DirectoryTree<int>.build(const [
    TreeEntry.file('/r/a.dart', data: 1),
    TreeEntry.file('/r/b.md', data: 2),
    TreeEntry.directory('/r/lib'),
  ]);
  final file = tree.nodeAt('/r/a.dart')!;
  final markdown = tree.nodeAt('/r/b.md')!;
  final directory = tree.nodeAt('/r/lib')!;

  final dart = TreeFilter.where<Object?>(
    (node) => node.path.extension == '.dart',
  );
  final files = TreeFilter.where<Object?>((node) => node.isFile);

  group('TreeFilter.where', () {
    test('matches nodes for which the test returns true', () {
      expect(dart.matches(file), isTrue);
      expect(dart.matches(markdown), isFalse);
      expect(dart.matchesAll, isFalse);
    });

    test('typed tests see typed data', () {
      final small = TreeFilter.where<int>((node) => (node.data ?? 0) < 2);
      expect(small.matches(file), isTrue);
      expect(small.matches(markdown), isFalse);
    });

    test('nodes of another type never match and are not tested', () {
      var calls = 0;
      final strings = TreeFilter.where<String>((node) {
        calls++;
        return true;
      });
      expect(strings.matches(file), isFalse);
      expect(calls, 0);
      final other = DirectoryTree<String>.build(const [
        TreeEntry.file('/s/x', data: 'x'),
      ]);
      expect(strings.matches(other.files.single), isTrue);
      expect(calls, 1);
    });

    test('a test that accepts everything still does not report matchesAll', () {
      expect(TreeFilter.where<Object?>((node) => true).matchesAll, isFalse);
    });
  });

  group('TreeFilter.all', () {
    test('matches every node and reports matchesAll', () {
      for (final node in tree.nodes) {
        expect(TreeFilter.all.matches(node), isTrue);
      }
      expect(TreeFilter.all.matchesAll, isTrue);
    });
  });

  group('combinators', () {
    test('and matches when both match', () {
      final filter = dart.and(files);
      expect(filter.matches(file), isTrue);
      expect(filter.matches(markdown), isFalse);
      expect(filter.matches(directory), isFalse);
    });

    test('or matches when either matches', () {
      final filter = dart.or(TreeFilter.where<Object?>((n) => n.isDirectory));
      expect(filter.matches(file), isTrue);
      expect(filter.matches(directory), isTrue);
      expect(filter.matches(markdown), isFalse);
    });

    test('negate flips every answer', () {
      final notDart = dart.negate();
      expect(notDart.matches(file), isFalse);
      expect(notDart.matches(markdown), isTrue);
      expect(notDart.negate(), same(dart));
    });

    test('matchesAll propagates through and, or, and negate', () {
      final none = TreeFilter.where<Object?>((node) => false);
      const all = TreeFilter.all;
      expect(all.and(all).matchesAll, isTrue);
      expect(all.and(none).matchesAll, isFalse);
      expect(none.and(all).matchesAll, isFalse);
      expect(all.or(none).matchesAll, isTrue);
      expect(none.or(all).matchesAll, isTrue);
      expect(none.or(none).matchesAll, isFalse);
      expect(all.negate().matchesAll, isFalse);
      expect(none.negate().matchesAll, isFalse);
      expect(all.negate().negate().matchesAll, isTrue);
    });

    test('negating all matches nothing', () {
      final nothing = TreeFilter.all.negate();
      for (final node in tree.nodes) {
        expect(nothing.matches(node), isFalse);
      }
    });

    test('and short-circuits on a rejection', () {
      final first = CountingFilter(result: false);
      final second = CountingFilter(result: true);
      expect(first.and(second).matches(file), isFalse);
      expect(first.calls, 1);
      expect(second.calls, 0);
    });

    test('or short-circuits on a match', () {
      final first = CountingFilter(result: true);
      final second = CountingFilter(result: false);
      expect(first.or(second).matches(file), isTrue);
      expect(first.calls, 1);
      expect(second.calls, 0);
    });

    test('custom filters can report matchesAll', () {
      final everything = CountingFilter(result: true, all: true);
      expect(everything.and(TreeFilter.all).matchesAll, isTrue);
      expect(everything.and(dart).matchesAll, isFalse);
    });

    test('combinators have value equality', () {
      expect(dart.and(files), dart.and(files));
      expect(dart.and(files).hashCode, dart.and(files).hashCode);
      expect(dart.and(files), isNot(files.and(dart)));
      expect(dart.or(files), dart.or(files));
      expect(dart.and(files), isNot(dart.or(files)));
      expect(dart.negate(), dart.negate());
      expect(TreeFilter.all, same(TreeFilter.all));
    });

    test('toString describes the structure', () {
      expect(TreeFilter.all.toString(), 'TreeFilter.all');
      expect(
        TreeFilter.all.and(TreeFilter.all.negate()).toString(),
        '(TreeFilter.all and not TreeFilter.all)',
      );
    });
  });
}
