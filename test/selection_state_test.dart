import 'dart:convert';
import 'dart:math';

import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

const single = SelectionMode.single;
const multiple = SelectionMode.multiple;

NodeId id(String value) => NodeId(value);

List<NodeId> ids(List<String> values) => [for (final v in values) NodeId(v)];

Set<NodeId> idSet(List<String> values) => ids(values).toSet();

/// An iterable that fails when iterated twice and records how many elements
/// were pulled, to prove single-pass and early-exit behavior.
class OnePass<E> extends Iterable<E> {
  OnePass(this._source);

  final List<E> _source;
  var _iterated = false;
  int pulled = 0;

  @override
  Iterator<E> get iterator {
    if (_iterated) throw StateError('iterated twice');
    _iterated = true;
    return _source.map((element) {
      pulled++;
      return element;
    }).iterator;
  }
}

/// Leaves of [nodeId] computed by recursion over [DirectoryTree.childrenOf],
/// independent of the pre-order layout the implementation uses.
List<NodeId> oracleLeaves(DirectoryTree<Object?> tree, NodeId nodeId) {
  final children = tree.childrenOf(nodeId);
  if (children.isEmpty) return [nodeId];
  return [for (final child in children) ...oracleLeaves(tree, child.id)];
}

CheckState oracleState(
  DirectoryTree<Object?> tree,
  Set<NodeId> selected,
  NodeId nodeId,
) {
  if (!tree.contains(nodeId)) return CheckState.unchecked;
  final leaves = oracleLeaves(tree, nodeId);
  final count = leaves.where(selected.contains).length;
  if (count == 0) return CheckState.unchecked;
  if (count == leaves.length) return CheckState.checked;
  return CheckState.partial;
}

/// A random tree with several top-level nodes, empty directories, and files
/// at random depths.
DirectoryTree<Object?> randomTree(Random random) {
  const tops = ['/a', '/b', '/c'];
  const names = ['x', 'y', 'z', 'w'];
  final entries = <TreeEntry<Object?>>[];
  final count = 1 + random.nextInt(25);
  for (var i = 0; i < count; i++) {
    final buffer = StringBuffer(tops[random.nextInt(tops.length)]);
    final depth = 1 + random.nextInt(4);
    for (var d = 0; d < depth; d++) {
      buffer.write('/${names[random.nextInt(names.length)]}');
    }
    if (random.nextInt(4) == 0) {
      entries.add(TreeEntry<Object?>.directory(buffer.toString()));
    } else {
      buffer.write('.f${random.nextInt(3)}');
      entries.add(TreeEntry<Object?>.file(buffer.toString(), data: i));
    }
  }
  return DirectoryTree<Object?>.build(entries);
}

Set<NodeId> randomSelection(Random random, DirectoryTree<Object?> tree) => {
  for (final node in tree.nodes)
    if (random.nextBool()) node.id,
  if (random.nextBool()) id('/not/in/tree'),
};

void main() {
  group('construction', () {
    test('empty defaults to single mode with nothing selected', () {
      const state = SelectionState.empty();
      expect(state.mode, single);
      expect(state.selected, isEmpty);
      expect(state.isEmpty, isTrue);
      expect(state.length, 0);
      expect(state.anchor, isNull);
      expect(const SelectionState.empty(mode: multiple).mode, multiple);
    });

    test('the default constructor dedupes and keeps first order', () {
      final state = SelectionState(
        mode: multiple,
        selected: ids(['/b', '/a', '/b']),
        anchor: id('/z'),
      );
      expect(state.selected.toList(), ids(['/b', '/a']));
      expect(state.length, 2);
      expect(state.anchor, id('/z'));
      expect(state.isSelected(id('/a')), isTrue);
      expect(state.isSelected(id('/z')), isFalse);
    });

    test('single mode rejects more than one distinct id', () {
      expect(
        () => SelectionState(selected: ids(['/a', '/b'])),
        throwsArgumentError,
      );
      expect(SelectionState(selected: ids(['/a', '/a'])).length, 1);
      expect(SelectionState().isEmpty, isTrue);
    });

    test('selected is unmodifiable', () {
      final state = SelectionState(mode: multiple, selected: ids(['/a']));
      expect(() => state.selected.add(id('/b')), throwsUnsupportedError);
      expect(
        () => const SelectionState.empty().selected.add(id('/b')),
        throwsUnsupportedError,
      );
    });
  });

  group('select', () {
    for (final mode in SelectionMode.values) {
      test('selects exactly the id and anchors it ($mode)', () {
        final state = SelectionState(
          mode: mode,
          selected: ids(['/a']),
          anchor: id('/a'),
        ).select(id('/b'));
        expect(state.selected, idSet(['/b']));
        expect(state.anchor, id('/b'));
        expect(state.mode, mode);
      });

      test('returns the same state when nothing changes ($mode)', () {
        final state = SelectionState(mode: mode).select(id('/a'));
        expect(identical(state.select(id('/a')), state), isTrue);
      });
    }

    test('moves the anchor even when the id is the only selection', () {
      final state = SelectionState(selected: ids(['/a']), anchor: id('/b'));
      final next = state.select(id('/a'));
      expect(identical(next, state), isFalse);
      expect(next.anchor, id('/a'));
    });

    test('replaces a multiple selection', () {
      final state = SelectionState(mode: multiple, selected: ids(['/a', '/b']));
      expect(state.select(id('/a')).selected, idSet(['/a']));
    });
  });

  group('toggle', () {
    test('multiple: adds and removes, anchoring the id', () {
      var state = const SelectionState.empty(mode: multiple);
      state = state.toggle(id('/a')).toggle(id('/b'));
      expect(state.selected.toList(), ids(['/a', '/b']));
      expect(state.anchor, id('/b'));
      state = state.toggle(id('/a'));
      expect(state.selected, idSet(['/b']));
      expect(state.anchor, id('/a'));
    });

    test('single: toggling the selected id clears with the anchor', () {
      final state = const SelectionState.empty().select(id('/a'));
      final cleared = state.toggle(id('/a'));
      expect(cleared.isEmpty, isTrue);
      expect(cleared.anchor, isNull);
      expect(cleared.mode, single);
    });

    test('single: toggling another id selects it', () {
      final state = const SelectionState.empty().select(id('/a'));
      final next = state.toggle(id('/b'));
      expect(next.selected, idSet(['/b']));
      expect(next.anchor, id('/b'));
    });
  });

  group('extendTo', () {
    final order = ids(['/1', '/2', '/3', '/4', '/5']);
    final anchored = const SelectionState.empty(
      mode: multiple,
    ).select(id('/2'));

    test('selects forward and backward ranges, keeping the anchor', () {
      final forward = anchored.extendTo(id('/4'), order);
      expect(forward.selected.toList(), ids(['/2', '/3', '/4']));
      expect(forward.anchor, id('/2'));
      final backward = forward.extendTo(id('/1'), order);
      expect(backward.selected.toList(), ids(['/1', '/2']));
      expect(backward.anchor, id('/2'));
    });

    test('replaces ids outside the range', () {
      final state = SelectionState(
        mode: multiple,
        selected: ids(['/5', '/9']),
        anchor: id('/2'),
      );
      expect(state.extendTo(id('/3'), order).selected, idSet(['/2', '/3']));
    });

    test('anchor equal to id selects just that id', () {
      expect(anchored.extendTo(id('/2'), order).selected, idSet(['/2']));
      expect(identical(anchored.extendTo(id('/2'), order), anchored), isTrue);
    });

    test('returns the same state when the range is unchanged', () {
      final ranged = anchored.extendTo(id('/4'), order);
      expect(identical(ranged.extendTo(id('/4'), order), ranged), isTrue);
    });

    test('without an anchor behaves as select', () {
      final state = SelectionState(mode: multiple, selected: ids(['/1']));
      final next = state.extendTo(id('/3'), order);
      expect(next.selected, idSet(['/3']));
      expect(next.anchor, id('/3'));
    });

    test('anchor or id missing from order behaves as select', () {
      final missingId = anchored.extendTo(id('/9'), order);
      expect(missingId.selected, idSet(['/9']));
      expect(missingId.anchor, id('/9'));
      final noAnchorInOrder = SelectionState(
        mode: multiple,
        anchor: id('/9'),
      ).extendTo(id('/3'), order);
      expect(noAnchorInOrder.selected, idSet(['/3']));
      expect(noAnchorInOrder.anchor, id('/3'));
      expect(anchored.extendTo(id('/3'), const []).selected, idSet(['/3']));
    });

    test('single mode behaves as select', () {
      final state = const SelectionState.empty().select(id('/2'));
      final next = state.extendTo(id('/4'), order);
      expect(next.selected, idSet(['/4']));
      expect(next.anchor, id('/4'));
    });

    test('iterates order once and stops at the range end', () {
      final once = OnePass(order);
      final next = anchored.extendTo(id('/3'), once);
      expect(next.selected, idSet(['/2', '/3']));
      expect(once.pulled, 3);
    });

    test('a missing end consumes order once and falls back', () {
      final once = OnePass(order);
      expect(anchored.extendTo(id('/9'), once).selected, idSet(['/9']));
      expect(once.pulled, order.length);
    });
  });

  group('addAll and removeAll', () {
    test('multiple: union appended in order, anchor kept', () {
      final state = SelectionState(
        mode: multiple,
        selected: ids(['/a']),
        anchor: id('/a'),
      );
      final next = state.addAll(OnePass(ids(['/c', '/a', '/b'])));
      expect(next.selected.toList(), ids(['/a', '/c', '/b']));
      expect(next.anchor, id('/a'));
      expect(identical(state.addAll(ids(['/a'])), state), isTrue);
      expect(identical(state.addAll(const []), state), isTrue);
    });

    test('single: keeps only the last id, anchor kept', () {
      final state = SelectionState(selected: ids(['/a']), anchor: id('/a'));
      final next = state.addAll(OnePass(ids(['/b', '/c'])));
      expect(next.selected, idSet(['/c']));
      expect(next.anchor, id('/a'));
      expect(identical(state.addAll(const []), state), isTrue);
      expect(identical(state.addAll(ids(['/b', '/a'])), state), isTrue);
    });

    for (final mode in SelectionMode.values) {
      test('removeAll removes, keeps the anchor ($mode)', () {
        final state = SelectionState(
          mode: mode,
          selected: ids(['/a']),
          anchor: id('/a'),
        );
        final next = state.removeAll(OnePass(ids(['/x', '/a'])));
        expect(next.isEmpty, isTrue);
        expect(next.anchor, id('/a'));
        expect(next.mode, mode);
        expect(identical(state.removeAll(ids(['/x'])), state), isTrue);
        expect(identical(state.removeAll(const []), state), isTrue);
      });
    }

    test('removeAll keeps the other ids in order', () {
      final state = SelectionState(
        mode: multiple,
        selected: ids(['/a', '/b', '/c']),
      );
      expect(state.removeAll(ids(['/b'])).selected.toList(), ids(['/a', '/c']));
    });
  });

  group('clear', () {
    for (final mode in SelectionMode.values) {
      test('drops selection and anchor, keeps the mode ($mode)', () {
        final state = SelectionState(
          mode: mode,
          selected: ids(['/a']),
          anchor: id('/a'),
        ).clear();
        expect(state.isEmpty, isTrue);
        expect(state.anchor, isNull);
        expect(state.mode, mode);
        expect(identical(state.clear(), state), isTrue);
      });
    }

    test('clears an anchor without a selection', () {
      final state = SelectionState(mode: multiple, anchor: id('/a'));
      expect(state.clear().anchor, isNull);
    });
  });

  group('withMode', () {
    test('same mode returns the same state', () {
      final state = SelectionState(mode: multiple, selected: ids(['/a']));
      expect(identical(state.withMode(multiple), state), isTrue);
    });

    test('to multiple keeps selection and anchor', () {
      final state = SelectionState(selected: ids(['/a']), anchor: id('/b'));
      final next = state.withMode(multiple);
      expect(next.mode, multiple);
      expect(next.selected, idSet(['/a']));
      expect(next.anchor, id('/b'));
    });

    test('to single keeps the anchor when it is selected', () {
      final state = SelectionState(
        mode: multiple,
        selected: ids(['/a', '/b']),
        anchor: id('/b'),
      );
      final next = state.withMode(single);
      expect(next.mode, single);
      expect(next.selected, idSet(['/b']));
      expect(next.anchor, id('/b'));
    });

    test('to single keeps the only selected id and anchors it', () {
      for (final state in [
        SelectionState(mode: multiple, selected: ids(['/a'])),
        SelectionState(mode: multiple, selected: ids(['/a']), anchor: id('/b')),
      ]) {
        final next = state.withMode(single);
        expect(next.mode, single);
        expect(next.selected, idSet(['/a']));
        expect(next.anchor, id('/a'));
      }
    });

    test('to single clears several ids without a selected anchor', () {
      for (final state in [
        SelectionState(mode: multiple, selected: ids(['/a', '/b'])),
        SelectionState(
          mode: multiple,
          selected: ids(['/a', '/b']),
          anchor: id('/c'),
        ),
      ]) {
        final next = state.withMode(single);
        expect(next.mode, single);
        expect(next.isEmpty, isTrue);
        expect(next.anchor, isNull);
      }
    });

    test('to single clears an empty selection and its anchor', () {
      final state = SelectionState(mode: multiple, anchor: id('/a'));
      final next = state.withMode(single);
      expect(next, const SelectionState.empty());
    });

    test('mode switches survive a JSON round trip', () {
      final multi = SelectionState(
        mode: multiple,
        selected: ids(['/b', '/a']),
        anchor: id('/c'),
      );
      for (final state in [
        multi,
        multi.withMode(single),
        SelectionState(
          mode: multiple,
          selected: ids(['/a']),
          anchor: id('/b'),
        ).withMode(single),
        SelectionState(selected: ids(['/a'])).withMode(multiple),
      ]) {
        final decoded =
            jsonDecode(jsonEncode(state.toJson())) as Map<String, Object?>;
        expect(SelectionState.fromJson(decoded), state);
      }
    });
  });

  group('prune', () {
    final tree = DirectoryTree.fromPaths(['/r/a.txt', '/r/b.txt']);
    final a = tree.nodeAt('/r/a.txt')!.id;
    final b = tree.nodeAt('/r/b.txt')!.id;

    test('drops ids and the anchor that the tree lacks', () {
      final state = SelectionState(
        mode: multiple,
        selected: [a, id('/gone'), b],
        anchor: id('/gone'),
      );
      final next = state.prune(tree);
      expect(next.selected.toList(), [a, b]);
      expect(next.anchor, isNull);
    });

    test('drops a missing anchor alone', () {
      final state = SelectionState(
        mode: multiple,
        selected: [a],
        anchor: id('/gone'),
      );
      final next = state.prune(tree);
      expect(next.selected, {a});
      expect(next.anchor, isNull);
    });

    test('keeps a present anchor and returns the same state when clean', () {
      final state = SelectionState(mode: multiple, selected: [a], anchor: b);
      expect(identical(state.prune(tree), state), isTrue);
      final dirty = SelectionState(selected: [id('/gone')], anchor: b);
      final next = dirty.prune(tree);
      expect(next.isEmpty, isTrue);
      expect(next.anchor, b);
      expect(next.mode, single);
    });
  });

  group('JSON', () {
    test('writes sorted ids and the anchor', () {
      final state = SelectionState(
        mode: multiple,
        selected: ids(['/b', '/a', '/C']),
        anchor: id('/b'),
      );
      expect(state.toJson(), {
        'mode': 'multiple',
        'selected': ['/C', '/a', '/b'],
        'anchor': '/b',
      });
      expect(const SelectionState.empty().toJson(), {
        'mode': 'single',
        'selected': <String>[],
        'anchor': null,
      });
    });

    test('round trips through jsonEncode and jsonDecode', () {
      final random = Random(7);
      for (var i = 0; i < 100; i++) {
        final mode = random.nextBool() ? single : multiple;
        final pool = ids(['/a', '/b', '/c', '/d', 'C:/x', '/é']);
        final selected = mode == single
            ? [if (random.nextBool()) pool[random.nextInt(pool.length)]]
            : [
                for (final nodeId in pool)
                  if (random.nextBool()) nodeId,
              ];
        final anchor = random.nextBool()
            ? null
            : pool[random.nextInt(pool.length)];
        final state = SelectionState(
          mode: mode,
          selected: selected,
          anchor: anchor,
        );
        final decoded =
            jsonDecode(jsonEncode(state.toJson())) as Map<String, Object?>;
        final restored = SelectionState.fromJson(decoded);
        expect(restored, state);
        expect(restored.hashCode, state.hashCode);
        expect(restored.toJson(), state.toJson());
      }
    });

    test('a missing anchor key means null; extra keys are ignored', () {
      final state = SelectionState.fromJson({
        'mode': 'multiple',
        'selected': ['/a'],
        'extra': 1,
      });
      expect(state, SelectionState(mode: multiple, selected: ids(['/a'])));
    });

    test('malformed input throws FormatException', () {
      final cases = <Map<String, Object?>>[
        {},
        {'selected': <String>[]},
        {'mode': 'Single', 'selected': <String>[]},
        {'mode': 1, 'selected': <String>[]},
        {'mode': null, 'selected': <String>[]},
        {'mode': 'single'},
        {'mode': 'single', 'selected': null},
        {'mode': 'single', 'selected': '/a'},
        {
          'mode': 'single',
          'selected': {'/a'},
        },
        {
          'mode': 'multiple',
          'selected': ['/a', 1],
        },
        {
          'mode': 'multiple',
          'selected': [null],
        },
        {'mode': 'single', 'selected': <String>[], 'anchor': 1},
        {
          'mode': 'single',
          'selected': <String>[],
          'anchor': ['/a'],
        },
      ];
      for (final json in cases) {
        expect(
          () => SelectionState.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
    });

    test('single mode with two distinct ids throws ArgumentError', () {
      expect(
        () => SelectionState.fromJson({
          'mode': 'single',
          'selected': ['/a', '/b'],
          'anchor': null,
        }),
        throwsArgumentError,
      );
      expect(
        SelectionState.fromJson({
          'mode': 'single',
          'selected': ['/a', '/a'],
        }).selected,
        idSet(['/a']),
      );
    });
  });

  group('equality and toString', () {
    test('compares mode, selected as a set, and anchor', () {
      final a = SelectionState(
        mode: multiple,
        selected: ids(['/a', '/b']),
        anchor: id('/a'),
      );
      final b = SelectionState(
        mode: multiple,
        selected: ids(['/b', '/a']),
        anchor: id('/a'),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.select(id('/a')), isFalse);
      expect(
        a == SelectionState(mode: multiple, selected: ids(['/a', '/b'])),
        isFalse,
      );
      expect(
        SelectionState(selected: ids(['/a'])) ==
            SelectionState(mode: multiple, selected: ids(['/a'])),
        isFalse,
      );
      expect(const SelectionState.empty(), SelectionState());
      expect(const SelectionState.empty().hashCode, SelectionState().hashCode);
    });

    test('toString lists sorted ids', () {
      final state = SelectionState(
        mode: multiple,
        selected: ids(['/b', '/a']),
        anchor: id('/b'),
      );
      expect(
        state.toString(),
        'SelectionState(mode: multiple, selected: [/a, /b], anchor: /b)',
      );
      expect(
        const SelectionState.empty().toString(),
        'SelectionState(mode: single, selected: [], anchor: null)',
      );
    });
  });

  group('check states', () {
    // r
    //   a/      x.txt, y.txt
    //   b/      (empty directory, a leaf)
    //   c.txt
    final tree = DirectoryTree<Never>.build(const [
      TreeEntry.file('/r/a/x.txt'),
      TreeEntry.file('/r/a/y.txt'),
      TreeEntry.directory('/r/b'),
      TreeEntry.file('/r/c.txt'),
    ]);
    NodeId at(String path) => tree.nodeAt(path)!.id;
    final r = at('/r');
    final a = at('/r/a');
    final b = at('/r/b');
    final x = at('/r/a/x.txt');
    final y = at('/r/a/y.txt');
    final c = at('/r/c.txt');
    const empty = SelectionState.empty(mode: multiple);

    test('leaves are checked when selected; parents summarize', () {
      final state = empty.addAll([x]);
      expect(state.checkStateOf(tree, x), CheckState.checked);
      expect(state.checkStateOf(tree, y), CheckState.unchecked);
      expect(state.checkStateOf(tree, a), CheckState.partial);
      expect(state.checkStateOf(tree, r), CheckState.partial);
      expect(state.checkStateOf(tree, b), CheckState.unchecked);
      expect(state.addAll([y]).checkStateOf(tree, a), CheckState.checked);
      expect(state.addAll([y, b, c]).checkStateOf(tree, r), CheckState.checked);
    });

    test('ids of directories with children never count', () {
      final state = empty.addAll([r, a]);
      expect(state.checkStateOf(tree, r), CheckState.unchecked);
      expect(state.checkStateOf(tree, a), CheckState.unchecked);
      expect(state.checkStates(tree).values.toSet(), {CheckState.unchecked});
    });

    test('an empty directory is a leaf', () {
      final state = empty.addAll([b]);
      expect(state.checkStateOf(tree, b), CheckState.checked);
      expect(state.checkStateOf(tree, r), CheckState.partial);
      expect(empty.check(tree, b).selected, {b});
    });

    test('unknown ids are unchecked and absent from checkStates', () {
      final state = empty.addAll([id('/nope')]);
      expect(state.checkStateOf(tree, id('/nope')), CheckState.unchecked);
      expect(state.checkStates(tree).containsKey(id('/nope')), isFalse);
    });

    test('checkStates covers every node in pre-order and is unmodifiable', () {
      final states = empty.addAll([x, c]).checkStates(tree);
      expect(states.keys.toList(), [for (final node in tree.nodes) node.id]);
      expect(states[r], CheckState.partial);
      expect(states[a], CheckState.partial);
      expect(states[c], CheckState.checked);
      expect(() => states[r] = CheckState.checked, throwsUnsupportedError);
      expect(empty.checkStates(DirectoryTree<Never>.empty()), isEmpty);
    });

    test('check, uncheck, and toggleCheck act on subtree leaves', () {
      final anchored = empty.select(c);
      final checked = anchored.check(tree, a);
      expect(checked.selected, {c, x, y});
      expect(checked.anchor, c);
      expect(checked.checkStateOf(tree, a), CheckState.checked);
      final unchecked = checked.uncheck(tree, r);
      expect(unchecked.isEmpty, isTrue);
      expect(unchecked.anchor, c);
      expect(identical(checked.check(tree, a), checked), isTrue);
      expect(identical(empty.uncheck(tree, a), empty), isTrue);
      final partial = empty.addAll([x]);
      final toggled = partial.toggleCheck(tree, a);
      expect(toggled.checkStateOf(tree, a), CheckState.checked);
      expect(
        toggled.toggleCheck(tree, a).checkStateOf(tree, a),
        CheckState.unchecked,
      );
      expect(empty.toggleCheck(tree, x).selected, {x});
      expect(empty.toggleCheck(tree, x).toggleCheck(tree, x), empty);
    });

    test('unknown ids leave the state unchanged', () {
      final state = empty.addAll([x]);
      expect(identical(state.check(tree, id('/nope')), state), isTrue);
      expect(identical(state.uncheck(tree, id('/nope')), state), isTrue);
      expect(identical(state.toggleCheck(tree, id('/nope')), state), isTrue);
      const singleState = SelectionState.empty();
      expect(
        identical(singleState.check(tree, id('/nope')), singleState),
        isTrue,
      );
    });

    test('single mode: one-leaf subtrees check, larger ones throw', () {
      const state = SelectionState.empty();
      expect(state.check(tree, x).selected, {x});
      expect(state.check(tree, x).check(tree, c).selected, {c});
      expect(state.toggleCheck(tree, c).selected, {c});
      expect(state.toggleCheck(tree, c).toggleCheck(tree, c).isEmpty, isTrue);
      expect(() => state.check(tree, a), throwsStateError);
      expect(() => state.check(tree, r), throwsStateError);
      expect(() => state.toggleCheck(tree, a), throwsStateError);
      expect(
        () => state.select(x).toggleCheck(tree, a),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('single selection mode'),
          ),
        ),
      );
      // Unchecking is always allowed.
      expect(state.select(x).uncheck(tree, a).isEmpty, isTrue);
      expect(identical(state.uncheck(tree, r), state), isTrue);
    });

    test('single mode: a directory with exactly one leaf can be checked', () {
      final oneLeaf = DirectoryTree.fromPaths(['/r/only/f.txt', '/r/g.txt']);
      final only = oneLeaf.nodeAt('/r/only')!.id;
      final f = oneLeaf.nodeAt('/r/only/f.txt')!.id;
      final state = const SelectionState.empty().check(oneLeaf, only);
      expect(state.selected, {f});
      expect(state.checkStateOf(oneLeaf, only), CheckState.checked);
      expect(state.toggleCheck(oneLeaf, only).isEmpty, isTrue);
    });

    test('works with typed trees and typed comparators', () {
      final typed = DirectoryTree<int>.build(
        const [
          TreeEntry.file('/t/big', data: 9),
          TreeEntry.file('/t/small', data: 1),
        ],
        options: TreeOptions(
          order: TreeOrder.by<int>(
            (left, right) => (left.data ?? 0).compareTo(right.data ?? 0),
          ),
        ),
      );
      final small = typed.nodeAt('/t/small')!.id;
      final state = empty.check(typed, small);
      expect(state.checkStateOf(typed, typed.roots.single), CheckState.partial);
      expect(state.checkStates(typed)[small], CheckState.checked);
      expect(state.prune(typed), state);
    });
  });

  group('check states against a brute-force oracle', () {
    test('checkStates and checkStateOf on random trees and selections', () {
      var multiRootTrees = 0;
      var emptyDirectories = 0;
      for (var seed = 0; seed < 300; seed++) {
        final random = Random(seed);
        final tree = randomTree(random);
        if (tree.roots.length > 1) multiRootTrees++;
        emptyDirectories += tree.directories
            .where((node) => !node.hasChildren)
            .length;
        final selected = randomSelection(random, tree);
        final state = SelectionState(mode: multiple, selected: selected);
        final states = state.checkStates(tree);
        expect(states.keys.toList(), [
          for (final node in tree.nodes) node.id,
        ], reason: 'seed $seed');
        for (final node in tree.nodes) {
          final expected = oracleState(tree, selected, node.id);
          expect(states[node.id], expected, reason: 'seed $seed ${node.id}');
          expect(
            state.checkStateOf(tree, node.id),
            expected,
            reason: 'seed $seed ${node.id}',
          );
        }
        expect(
          state.checkStateOf(tree, id('/not/in/tree')),
          CheckState.unchecked,
        );

        // Single mode with at most one selected id.
        final pick = tree.nodes[random.nextInt(tree.length)].id;
        final singleState = SelectionState(selected: [pick]);
        final singleStates = singleState.checkStates(tree);
        for (final node in tree.nodes) {
          expect(
            singleStates[node.id],
            oracleState(tree, {pick}, node.id),
            reason: 'seed $seed single ${node.id}',
          );
        }
      }
      expect(multiRootTrees, greaterThan(50));
      expect(emptyDirectories, greaterThan(50));
    });

    test('check, uncheck, and toggleCheck on random trees', () {
      for (var seed = 0; seed < 300; seed++) {
        final random = Random(1000 + seed);
        final tree = randomTree(random);
        final selected = randomSelection(random, tree);
        final state = SelectionState(
          mode: multiple,
          selected: selected,
          anchor: tree.nodes.first.id,
        );
        final target = tree.nodes[random.nextInt(tree.length)].id;
        final leaves = oracleLeaves(tree, target).toSet();
        final reason = 'seed $seed $target';

        final checked = state.check(tree, target);
        expect(checked.selected, {...selected, ...leaves}, reason: reason);
        expect(checked.anchor, state.anchor, reason: reason);
        expect(
          checked.checkStateOf(tree, target),
          CheckState.checked,
          reason: reason,
        );

        final unchecked = state.uncheck(tree, target);
        expect(unchecked.selected, selected.difference(leaves), reason: reason);
        expect(unchecked.anchor, state.anchor, reason: reason);
        expect(
          unchecked.checkStateOf(tree, target),
          CheckState.unchecked,
          reason: reason,
        );

        final before = state.checkStateOf(tree, target);
        final once = state.toggleCheck(tree, target);
        final twice = once.toggleCheck(tree, target);
        switch (before) {
          case CheckState.checked:
            expect(once, unchecked, reason: reason);
            expect(twice, state, reason: reason);
          case CheckState.unchecked:
            expect(once, checked, reason: reason);
            expect(twice, state, reason: reason);
          case CheckState.partial:
            expect(once, checked, reason: reason);
            expect(twice, unchecked, reason: reason);
        }

        // Starting from a fully checked or fully unchecked subtree, toggling
        // twice restores the original leaf selection.
        for (final start in [checked, unchecked]) {
          expect(
            start.toggleCheck(tree, target).toggleCheck(tree, target),
            start,
            reason: reason,
          );
        }
      }
    });
  });

  group('deep trees', () {
    final buffer = StringBuffer();
    for (var i = 0; i < 1000; i++) {
      buffer.write('/d$i');
    }
    final chain = buffer.toString();
    final tree = DirectoryTree.fromPaths(['$chain/leaf.txt', '/d0/top.txt']);
    final leaf = tree.nodeAt('$chain/leaf.txt')!.id;
    final top = tree.nodeAt('/d0/top.txt')!.id;
    const empty = SelectionState.empty(mode: multiple);

    test('checkStates handles a 1000-deep chain', () {
      expect(tree.nodeAt('$chain/leaf.txt')!.depth, greaterThanOrEqualTo(999));
      final states = empty.addAll([leaf]).checkStates(tree);
      expect(states.length, tree.length);
      expect(states[tree.roots.single], CheckState.partial);
      expect(states[tree.parentOf(leaf)!.id], CheckState.checked);
      final all = empty.addAll([leaf, top]).checkStates(tree);
      expect(all.values.toSet(), {CheckState.checked});
    });

    test('check and checkStateOf handle a 1000-deep chain', () {
      final root = tree.roots.single;
      final checked = empty.check(tree, root);
      expect(checked.selected, {leaf, top});
      expect(checked.checkStateOf(tree, root), CheckState.checked);
      expect(checked.uncheck(tree, root).isEmpty, isTrue);
    });
  });
}
