import 'dart:convert';

import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

/// Hand-checked tree (directories first):
///
/// ```text
/// /r
///   a
///     b
///       deep.txt
///     a.txt
///   c
///     c.txt
///   top.txt
/// /s
///   s.txt
/// ```
DirectoryTree<Object?> sampleTree() => DirectoryTree.fromPaths([
  '/r/a/b/deep.txt',
  '/r/a/a.txt',
  '/r/c/c.txt',
  '/r/top.txt',
  '/s/s.txt',
]);

NodeId id(String value) => NodeId(value);

void main() {
  final tree = sampleTree();
  final r = id('/r');
  final a = id('/r/a');
  final b = id('/r/a/b');
  final c = id('/r/c');
  final s = id('/s');
  final deep = id('/r/a/b/deep.txt');
  final topFile = id('/r/top.txt');
  final unknown = id('/nowhere');

  test('the sample tree has the expected directories', () {
    expect(tree.directories.map((node) => node.id), [r, a, b, c, s]);
  });

  group('defaults', () {
    test('collapsed expands nothing', () {
      const state = ExpansionState.collapsed();
      expect(state.expandsByDefault, isFalse);
      expect(state.exceptions, isEmpty);
      expect(state.isExpanded(r), isFalse);
      expect(state.isExpanded(unknown), isFalse);
    });

    test('expanded expands everything', () {
      const state = ExpansionState.expanded();
      expect(state.expandsByDefault, isTrue);
      expect(state.exceptions, isEmpty);
      expect(state.isExpanded(r), isTrue);
      expect(state.isExpanded(unknown), isTrue);
    });

    test('withExpanded is collapsed by default with exceptions', () {
      final state = ExpansionState.withExpanded([r, a, r]);
      expect(state.expandsByDefault, isFalse);
      expect(state.exceptions, {r, a});
      expect(state.isExpanded(r), isTrue);
      expect(state.isExpanded(a), isTrue);
      expect(state.isExpanded(b), isFalse);
    });

    test('withCollapsed is expanded by default with exceptions', () {
      final state = ExpansionState.withCollapsed([b]);
      expect(state.expandsByDefault, isTrue);
      expect(state.exceptions, {b});
      expect(state.isExpanded(b), isFalse);
      expect(state.isExpanded(a), isTrue);
    });

    test('empty exception lists equal the plain defaults', () {
      expect(
        ExpansionState.withExpanded(const []),
        const ExpansionState.collapsed(),
      );
      expect(
        ExpansionState.withCollapsed(const []),
        const ExpansionState.expanded(),
      );
    });

    test('the input iterable is copied', () {
      final ids = [r];
      final state = ExpansionState.withExpanded(ids);
      ids.add(a);
      expect(state.exceptions, {r});
    });

    test('exceptions are unmodifiable', () {
      final state = ExpansionState.withExpanded([r]);
      expect(() => state.exceptions.add(a), throwsUnsupportedError);
      expect(
        () => const ExpansionState.collapsed().exceptions.add(a),
        throwsUnsupportedError,
      );
      expect(
        () => state.expand(a).exceptions.remove(r),
        throwsUnsupportedError,
      );
    });
  });

  group('single-id operations', () {
    for (final base in const [
      ExpansionState.collapsed(),
      ExpansionState.expanded(),
    ]) {
      final mode = base.expandsByDefault ? 'expanded' : 'collapsed';

      test('expand and collapse ($mode default)', () {
        final expanded = base.expand(a);
        expect(expanded.isExpanded(a), isTrue);
        expect(identical(expanded.expand(a), expanded), isTrue);
        final collapsed = expanded.collapse(a);
        expect(collapsed.isExpanded(a), isFalse);
        expect(identical(collapsed.collapse(a), collapsed), isTrue);
        // Other ids keep the default.
        expect(collapsed.isExpanded(b), base.expandsByDefault);
        expect(expanded.isExpanded(b), base.expandsByDefault);
      });

      test('returning to the default removes the exception ($mode)', () {
        final changed = base.toggle(a);
        expect(changed.exceptions, {a});
        final back = changed.toggle(a);
        expect(back.exceptions, isEmpty);
        expect(back, base);
      });

      test('toggle always changes the state ($mode default)', () {
        final once = base.toggle(c);
        expect(identical(once, base), isFalse);
        expect(once.isExpanded(c), !base.expandsByDefault);
        expect(once.toggle(c).isExpanded(c), base.expandsByDefault);
      });

      test('setExpanded ($mode default)', () {
        final current = base.isExpanded(a);
        expect(identical(base.setExpanded(a, expanded: current), base), isTrue);
        final flipped = base.setExpanded(a, expanded: !current);
        expect(flipped.isExpanded(a), !current);
        expect(flipped.exceptions, {a});
      });

      test('operations never change the receiver ($mode default)', () {
        final start = base.expand(b).expand(unknown);
        final copy = ExpansionState.fromJson(start.toJson());
        final derived = [
          start.expand(c),
          start.collapse(b),
          start.toggle(r),
          start.setExpanded(a, expanded: !start.isExpanded(a)),
          start.expandAll([a, s]),
          start.collapseAll([b]),
          start.reveal(tree, deep),
          start.expandSubtree(tree, r),
          start.collapseSubtree(tree, r),
          start.prune(tree),
        ];
        expect(derived, everyElement(isA<ExpansionState>()));
        expect(start, copy);
        expect(start.exceptions, copy.exceptions);
      });
    }

    test('ids are not checked against any tree', () {
      final state = const ExpansionState.collapsed()
          .expand(unknown)
          .expand(deep);
      expect(state.isExpanded(unknown), isTrue);
      expect(state.isExpanded(deep), isTrue);
    });
  });

  group('bulk operations', () {
    test('expandAll and collapseAll in a collapsed-default state', () {
      const base = ExpansionState.collapsed();
      final expanded = base.expandAll([r, a, b]);
      expect(expanded.exceptions, {r, a, b});
      expect(identical(expanded.expandAll([r, a]), expanded), isTrue);
      expect(identical(expanded.expandAll(const []), expanded), isTrue);
      final collapsed = expanded.collapseAll([a, c]);
      expect(collapsed.exceptions, {r, b});
      expect(identical(collapsed.collapseAll([a, c]), collapsed), isTrue);
    });

    test('expandAll and collapseAll in an expanded-default state', () {
      const base = ExpansionState.expanded();
      final collapsed = base.collapseAll([r, a]);
      expect(collapsed.exceptions, {r, a});
      expect(identical(collapsed.collapseAll([r]), collapsed), isTrue);
      final expanded = collapsed.expandAll([a, b, a]);
      expect(expanded.exceptions, {r});
      expect(identical(expanded.expandAll([b]), expanded), isTrue);
    });

    test('a repeated id in one call is handled once', () {
      final state = const ExpansionState.collapsed().expandAll([a, a, a]);
      expect(state.exceptions, {a});
    });
  });

  group('tree-aware operations', () {
    test('reveal expands every ancestor, not the node', () {
      final state = const ExpansionState.collapsed().reveal(tree, deep);
      expect(state.exceptions, {r, a, b});
      expect(state.isExpanded(deep), isFalse);
      final directory = const ExpansionState.collapsed().reveal(tree, b);
      expect(directory.exceptions, {r, a});
      expect(directory.isExpanded(b), isFalse);
    });

    test('reveal in an expanded-default state removes collapsed ancestors', () {
      final state = ExpansionState.withCollapsed([r, b, c]);
      final revealed = state.reveal(tree, deep);
      expect(revealed.exceptions, {c});
    });

    test('reveal returns this when nothing changes', () {
      const collapsed = ExpansionState.collapsed();
      expect(identical(collapsed.reveal(tree, r), collapsed), isTrue);
      expect(identical(collapsed.reveal(tree, unknown), collapsed), isTrue);
      const expanded = ExpansionState.expanded();
      expect(identical(expanded.reveal(tree, deep), expanded), isTrue);
      final revealed = collapsed.reveal(tree, deep);
      expect(identical(revealed.reveal(tree, deep), revealed), isTrue);
    });

    test('expandSubtree in a collapsed-default state', () {
      final state = const ExpansionState.collapsed().expandSubtree(tree, a);
      expect(state.exceptions, {a, b});
      expect(identical(state.expandSubtree(tree, a), state), isTrue);
      final all = state.expandSubtree(tree, r);
      expect(all.exceptions, {r, a, b, c});
    });

    test('expandSubtree in an expanded-default state removes exceptions', () {
      // Fewer exceptions (3) than subtree nodes (4): the exceptions are
      // scanned.
      final few = ExpansionState.withCollapsed([a, b, s]);
      final opened = few.expandSubtree(tree, a);
      expect(opened.exceptions, {s});
      expect(identical(opened.expandSubtree(tree, a), opened), isTrue);
      // More exceptions than subtree nodes: the subtree is walked.
      final many = ExpansionState.withCollapsed([
        b,
        r,
        a,
        c,
        s,
        unknown,
        deep,
        topFile,
      ]);
      final reopened = many.expandSubtree(tree, b);
      expect(reopened.exceptions, {r, a, c, s, unknown, deep, topFile});
      expect(identical(reopened.expandSubtree(tree, b), reopened), isTrue);
    });

    test('collapseSubtree in an expanded-default state', () {
      final state = const ExpansionState.expanded().collapseSubtree(tree, r);
      expect(state.exceptions, {r, a, b, c});
      expect(identical(state.collapseSubtree(tree, r), state), isTrue);
    });

    test('collapseSubtree in a collapsed-default state removes exceptions', () {
      final state = ExpansionState.withExpanded([r, a, b, c, s]);
      final closed = state.collapseSubtree(tree, a);
      expect(closed.exceptions, {r, c, s});
      expect(identical(closed.collapseSubtree(tree, a), closed), isTrue);
      final many = ExpansionState.withExpanded([r, a, b, c, s, unknown]);
      expect(many.collapseSubtree(tree, b).exceptions, {r, a, c, s, unknown});
      // Fewer exceptions than subtree nodes: the exceptions are scanned.
      final few = ExpansionState.withExpanded([a, s]);
      expect(few.collapseSubtree(tree, r).exceptions, {s});
      final none = ExpansionState.withExpanded([s]);
      expect(identical(none.collapseSubtree(tree, r), none), isTrue);
    });

    test('subtree operations ignore files, unknown ids, and outside ids', () {
      for (final base in const [
        ExpansionState.collapsed(),
        ExpansionState.expanded(),
      ]) {
        expect(identical(base.expandSubtree(tree, deep), base), isTrue);
        expect(identical(base.collapseSubtree(tree, deep), base), isTrue);
        expect(identical(base.expandSubtree(tree, unknown), base), isTrue);
        expect(identical(base.collapseSubtree(tree, unknown), base), isTrue);
      }
      final state = ExpansionState.withExpanded([s, c]).expandSubtree(tree, a);
      expect(state.exceptions, {s, c, a, b});
    });

    test('subtree operations leave file ids inside the subtree alone', () {
      final state = ExpansionState.withCollapsed([deep]);
      expect(identical(state.expandSubtree(tree, r), state), isTrue);
      final withFile = ExpansionState.withCollapsed([deep, b]);
      expect(withFile.expandSubtree(tree, r).exceptions, {deep});
    });

    test('prune drops ids that are not directories of the tree', () {
      final state = ExpansionState.withExpanded([r, b, deep, unknown]);
      final pruned = state.prune(tree);
      expect(pruned.exceptions, {r, b});
      expect(pruned.expandsByDefault, isFalse);
      expect(identical(pruned.prune(tree), pruned), isTrue);
      const plain = ExpansionState.expanded();
      expect(identical(plain.prune(tree), plain), isTrue);
      final collapsed = ExpansionState.withCollapsed([unknown]).prune(tree);
      expect(collapsed, const ExpansionState.expanded());
    });

    test('prune keeps answers for directories of the tree', () {
      final state = ExpansionState.withCollapsed([a, deep, unknown]);
      final pruned = state.prune(tree);
      for (final directory in tree.directories) {
        expect(
          pruned.isExpanded(directory.id),
          state.isExpanded(directory.id),
          reason: '${directory.id}',
        );
      }
    });

    test('works with trees of any data type', () {
      final typed = DirectoryTree<int>.build(const [
        TreeEntry.file('/t/x/y.txt', data: 1),
        TreeEntry.directory('/t', data: 2),
      ]);
      final state = const ExpansionState.collapsed().reveal(
        typed,
        id('/t/x/y.txt'),
      );
      expect(state.exceptions, {id('/t'), id('/t/x')});
      expect(state.prune(typed), state);
    });
  });

  group('JSON', () {
    test('toJson writes the default and sorted exceptions', () {
      final state = ExpansionState.withExpanded([s, a, r]);
      expect(state.toJson(), {
        'default': 'collapsed',
        'exceptions': ['/r', '/r/a', '/s'],
      });
      expect(const ExpansionState.expanded().toJson(), {
        'default': 'expanded',
        'exceptions': <String>[],
      });
    });

    test('round trips through jsonEncode and jsonDecode', () {
      for (final state in [
        const ExpansionState.collapsed(),
        const ExpansionState.expanded(),
        ExpansionState.withExpanded([r, b, unknown]),
        ExpansionState.withCollapsed([a, deep]),
      ]) {
        final decoded =
            jsonDecode(jsonEncode(state.toJson())) as Map<String, Object?>;
        final restored = ExpansionState.fromJson(decoded);
        expect(restored, state);
        expect(restored.expandsByDefault, state.expandsByDefault);
        expect(restored.exceptions, state.exceptions);
      }
    });

    test('equal states encode identically whatever the insertion order', () {
      final first = ExpansionState.withExpanded([r, a, b]);
      final second = ExpansionState.withExpanded([b, r, a]);
      expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    });

    test('fromJson ignores extra keys and duplicate ids', () {
      final state = ExpansionState.fromJson({
        'default': 'expanded',
        'exceptions': ['/r', '/r'],
        'version': 3,
      });
      expect(state, ExpansionState.withCollapsed([r]));
    });

    test('fromJson restores exceptions as unmodifiable', () {
      final state = ExpansionState.fromJson({
        'default': 'collapsed',
        'exceptions': ['/r'],
      });
      expect(() => state.exceptions.clear(), throwsUnsupportedError);
    });

    final malformed = <String, Map<String, Object?>>{
      'missing default': {'exceptions': <Object?>[]},
      'null default': {'default': null, 'exceptions': <Object?>[]},
      'numeric default': {'default': 1, 'exceptions': <Object?>[]},
      'boolean default': {'default': true, 'exceptions': <Object?>[]},
      'list default': {
        'default': ['expanded'],
        'exceptions': <Object?>[],
      },
      'unknown default': {'default': 'open', 'exceptions': <Object?>[]},
      'default in the wrong case': {
        'default': 'Expanded',
        'exceptions': <Object?>[],
      },
      'missing exceptions': {'default': 'collapsed'},
      'null exceptions': {'default': 'collapsed', 'exceptions': null},
      'string exceptions': {'default': 'collapsed', 'exceptions': '/r'},
      'map exceptions': {
        'default': 'collapsed',
        'exceptions': {'/r': true},
      },
      'numeric exception': {
        'default': 'collapsed',
        'exceptions': ['/r', 1],
      },
      'null exception': {
        'default': 'expanded',
        'exceptions': ['/r', null],
      },
      'nested list exception': {
        'default': 'expanded',
        'exceptions': [
          ['/r'],
        ],
      },
    };
    malformed.forEach((name, json) {
      test('fromJson throws FormatException for $name', () {
        expect(() => ExpansionState.fromJson(json), throwsFormatException);
      });
    });
  });

  test('the class documentation example', () {
    final tree = DirectoryTree.fromPaths([
      '/repo/lib/main.dart',
      '/repo/README.md',
    ]);
    final lib = tree.idOf('/repo/lib')!;
    var state = const ExpansionState.collapsed();
    state = state.reveal(tree, lib).expand(lib);
    expect(state.isExpanded(lib), isTrue);
    expect(
      state.toJson().toString(),
      '{default: collapsed, exceptions: [/repo, /repo/lib]}',
    );
  });

  group('equality and toString', () {
    test('equality ignores exception order and compares the default', () {
      final first = ExpansionState.withExpanded([r, a]);
      final second = ExpansionState.withExpanded([a, r]);
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first == ExpansionState.withCollapsed([r, a]), isFalse);
      expect(first == ExpansionState.withExpanded([r]), isFalse);
      expect(first == ExpansionState.withExpanded([r, b]), isFalse);
      expect(
        const ExpansionState.collapsed() == const ExpansionState.expanded(),
        isFalse,
      );
      expect(
        const ExpansionState.collapsed().expand(a).collapse(a),
        const ExpansionState.collapsed(),
      );
      expect(
        const ExpansionState.collapsed().expand(a).collapse(a).hashCode,
        const ExpansionState.collapsed().hashCode,
      );
    });

    test('toString reads like the constructor that recreates the state', () {
      expect(
        const ExpansionState.collapsed().toString(),
        'ExpansionState.collapsed()',
      );
      expect(
        const ExpansionState.expanded().toString(),
        'ExpansionState.expanded()',
      );
      expect(
        ExpansionState.withExpanded([s, r]).toString(),
        'ExpansionState.withExpanded([/r, /s])',
      );
      expect(
        ExpansionState.withCollapsed([a]).toString(),
        'ExpansionState.withCollapsed([/r/a])',
      );
    });

    test('toString summarizes long exception lists', () {
      final ids = [for (var i = 0; i < 25; i++) id('/d${i + 10}')];
      final text = ExpansionState.withExpanded(ids).toString();
      expect(text, startsWith('ExpansionState.withExpanded([/d10, /d11, '));
      expect(text, endsWith(', /d29, ... 5 more])'));
    });
  });
}
