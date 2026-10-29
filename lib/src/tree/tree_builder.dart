part of 'directory_tree.dart';

/// A mutable set of [TreeEntry]s that builds immutable [DirectoryTree]s.
///
/// Use a builder to assemble entries incrementally (from a scanner, a file
/// picker, or a stream of changes) and call [build] whenever you need a
/// snapshot. [DirectoryTree.rebuild] and [DirectoryTree.toBuilder] give you
/// a builder seeded from an existing tree.
///
/// Entries are keyed by the [NodeId] of their path under
/// [TreeOptions.paths]: adding an entry whose path maps to an existing id
/// replaces that entry in place, keeping its position. Entries whose paths
/// cannot be parsed are kept, in order, so [build] can report them in
/// [DirectoryTree.issues].
///
/// ```dart
/// final builder = DirectoryTreeBuilder<int>()
///   ..addFile('/repo/lib/a.dart', data: 120)
///   ..addFile('/repo/lib/b.dart', data: 80)
///   ..addDirectory('/repo/assets');
/// final tree = builder.build();
/// builder.remove('/repo/lib'); // also removes both files
/// ```
///
/// A builder is mutable and is not a value: it compares by identity.
final class DirectoryTreeBuilder<T> {
  /// Creates a builder with [options], seeded with [entries] in order.
  ///
  /// Entries that share an id merge as described for [add].
  DirectoryTreeBuilder({
    TreeOptions options = const TreeOptions(),
    Iterable<TreeEntry<T>> entries = const [],
  }) : _options = options {
    addAll(entries);
  }

  TreeOptions _options;

  // Insertion-ordered. Valid entries are keyed by their NodeId; entries with
  // unparseable paths get a unique Object key so they keep their position
  // and never merge.
  final Map<Object, _BuilderItem<T>> _items = <Object, _BuilderItem<T>>{};

  /// The options used for keys and for [build].
  ///
  /// Setting options with a different [TreeOptions.paths] policy re-parses
  /// every entry and recomputes its key, in O(total path length). Entries
  /// that now share a key merge: the first position keeps the later entry.
  TreeOptions get options => _options;

  set options(TreeOptions value) {
    final rekey = value.paths != _options.paths;
    _options = value;
    if (rekey) _rekey();
  }

  /// The current entries in insertion order, one per key, including entries
  /// with invalid paths.
  ///
  /// Returns an unmodifiable snapshot that later changes do not affect.
  List<TreeEntry<T>> get entries =>
      List<TreeEntry<T>>.unmodifiable(_items.values.map((item) => item.entry));

  /// The number of entries, including entries with invalid paths.
  int get length => _items.length;

  /// Adds [entry], replacing any entry whose path has the same id.
  ///
  /// A replaced entry keeps its position; this matches building from a list
  /// with duplicates, where the later entry wins. An entry with an invalid
  /// path is kept and reported when you [build]. Parses the path once, in
  /// O(path length).
  void add(TreeEntry<T> entry) =>
      _put(_BuilderItem<T>.parse(entry, _options.paths));

  /// Adds every entry of [entries] in order, as [add] does.
  void addAll(Iterable<TreeEntry<T>> entries) {
    for (final entry in entries) {
      add(entry);
    }
  }

  /// Adds a file entry for [path] with optional [data].
  void addFile(String path, {T? data}) =>
      add(TreeEntry<T>.file(path, data: data));

  /// Adds a directory entry for [path] with optional [data].
  void addDirectory(String path, {T? data}) =>
      add(TreeEntry<T>.directory(path, data: data));

  /// Whether an entry exists at [path], compared by id under
  /// [TreeOptions.paths].
  ///
  /// Returns false for paths that cannot be parsed. Only entries count;
  /// directories that a build would infer do not.
  bool contains(String path) {
    final policy = _options.paths;
    final parsed = policy.tryParse(path);
    return parsed != null && _items.containsKey(policy.idOf(parsed));
  }

  /// Removes the entry at [path] and, when [recursive] (the default), every
  /// entry inside it.
  ///
  /// Paths are compared by id, so with a case-insensitive policy
  /// `remove('/A')` also removes `/a/b.txt`. Removing a path root such as
  /// `/` with [recursive] removes every entry under that root. Returns the
  /// number of entries removed; an invalid [path] removes nothing and
  /// returns 0. Runs in O(entries).
  int remove(String path, {bool recursive = true}) {
    final policy = _options.paths;
    final target = policy.tryParse(path);
    if (target == null) return 0;
    final targetId = policy.idOf(target);
    final removedSelf = _items.remove(targetId) == null ? 0 : 1;
    if (!recursive) return removedSelf;

    final bool Function(_BuilderItem<T> item) isInside;
    if (target.isRoot) {
      final rootKey = _foldWith(policy, target.root);
      isInside = (item) {
        final itemPath = item.path;
        return itemPath != null &&
            !itemPath.isRoot &&
            _foldWith(policy, itemPath.root) == rootKey;
      };
    } else {
      // Ids of paths inside the target extend the target id with '/'.
      final prefix = '${targetId.value}/';
      isInside = (item) => item.key?.value.startsWith(prefix) ?? false;
    }
    final doomed = [
      for (final MapEntry(:key, :value) in _items.entries)
        if (isInside(value)) key,
    ];
    for (final key in doomed) {
      _items.remove(key);
    }
    return removedSelf + doomed.length;
  }

  /// Removes every entry for which [test] returns true and returns how many
  /// were removed.
  ///
  /// [test] sees each entry once, in insertion order, and must not modify
  /// this builder.
  int removeWhere(bool Function(TreeEntry<T> entry) test) {
    final doomed = [
      for (final MapEntry(:key, :value) in _items.entries)
        if (test(value.entry)) key,
    ];
    for (final key in doomed) {
      _items.remove(key);
    }
    return doomed.length;
  }

  /// Removes every entry. [options] stay as they are.
  void clear() => _items.clear();

  /// Builds an immutable [DirectoryTree] from the current entries and
  /// [options].
  ///
  /// The builder is unchanged and can keep collecting entries; each call
  /// builds a new tree. See [DirectoryTree.build] for the semantics and cost.
  DirectoryTree<T> build() => _TreeAssembler<T>(
    _options,
    _items.values.toList(growable: false),
  ).assemble();

  void _put(_BuilderItem<T> item) {
    _items[item.key ?? Object()] = item;
  }

  void _rekey() {
    final items = _items.values.toList(growable: false);
    _items.clear();
    final policy = _options.paths;
    for (final item in items) {
      _put(_BuilderItem<T>.parse(item.entry, policy));
    }
  }
}

/// Folds one path part the way [PathPolicy.idOf] folds a whole path.
///
/// The trie folds each segment on its own while ids fold the whole canonical
/// string. The two agree because the package's simple case folding maps
/// each code point on its own, without context, and maps `/` to itself.
/// Materialization asserts that ids stay unique.
String _foldWith(PathPolicy policy, String text) => policy.foldKey(text);

/// An entry with its parsed path and key, or the parse error message.
final class _BuilderItem<T> {
  _BuilderItem(this.entry, this.path, this.key, this.error);

  factory _BuilderItem.parse(TreeEntry<T> entry, PathPolicy policy) {
    try {
      final path = policy.parse(entry.path);
      return _BuilderItem<T>(entry, path, policy.idOf(path), null);
    } on FormatException catch (error) {
      return _BuilderItem<T>(entry, null, null, error.message);
    }
  }

  final TreeEntry<T> entry;
  final TreePath? path;
  final NodeId? key;
  final String? error;
}

/// An entry that parsed and is still a candidate for the tree.
final class _Candidate<T> {
  _Candidate(this.entry, this.path, this.key, this.position);

  final TreeEntry<T> entry;
  final TreePath path;

  /// The policy id of [path]; also the id of the entry's node, since node
  /// spellings only differ from [path] in letter case, which ids fold.
  final NodeId key;

  /// Index in the builder's entry order; issues are reported in this order.
  final int position;

  /// The trie slot of [path], once inserted.
  _Slot<T>? slot;

  /// Whether the entry was skipped with an issue.
  bool dropped = false;
}

/// A trie node: one directory or file position, keyed by folded segments.
///
/// The trie is the core of the build. Walking an entry path costs
/// O(path length), siblings are found by hash instead of by scanning, and
/// node paths and ids are only created once per slot, which keeps the build
/// O(L + n log n) instead of quadratic in path depth.
final class _Slot<T> {
  _Slot(this.parent);

  /// The slot one level up; null for path-root slots (`/`, `C:/`, ...).
  final _Slot<T>? parent;

  /// Child slots keyed by folded segment; null until the first child.
  Map<String, _Slot<T>>? children;

  /// The code-unit-smallest spelling of this slot's segment (or of the root
  /// string, for path-root slots) among the paths of accepted entries
  /// passing strictly through it. Null for slots no accepted entry passes
  /// through.
  String? implied;

  /// The accepted entry whose path ends here, if any.
  _Candidate<T>? candidate;

  /// The spelling of the [TreeRoots.fixed] root at this slot, if any.
  TreePath? fixedPath;

  /// Whether an accepted entry contributes this directory (see
  /// [TreeRoots]).
  bool contributes = false;

  // Materialization state, valid for slots that become tree nodes.
  bool isRoot = false;
  int depth = 0;
  late TreePath path;
  late NodeId id;
  late String label;
  late TreeNode<T> node;
  List<_Slot<T>> sorted = const [];
  int size = 1;
  int index = -1;
}

/// Runs the normative build algorithm over a builder's items.
///
/// 1. Parse results become candidates or `invalidPath` issues.
/// 2. With fixed roots: place the roots, then drop candidates outside them.
/// 3. Insert candidates into the trie.
/// 4. File candidates with children become `conflict` issues.
/// 5. The accepted entries record the implied spellings of the directories
///    they pass through, and contributions decide the top-level slots.
/// 6. Materialize: display paths and ids top-down, labels for roots, nodes
///    bottom-up with sorted children, then the pre-order arrays.
final class _TreeAssembler<T> {
  _TreeAssembler(this.options, this.items)
    : policy = options.paths,
      _entryIssues = List<TreeIssue<T>?>.filled(items.length, null);

  final TreeOptions options;
  final PathPolicy policy;
  final List<_BuilderItem<T>> items;

  final Map<String, _Slot<T>> _tops = <String, _Slot<T>>{};
  final List<TreeIssue<T>> _rootIssues = <TreeIssue<T>>[];
  final List<TreeIssue<T>?> _entryIssues;

  DirectoryTree<T> assemble() {
    final candidates = _parseCandidates();
    final fixed = options.roots.kind == TreeRootsKind.fixed;
    final fixedRoots = fixed ? _placeFixedRoots(candidates) : null;
    for (final candidate in candidates) {
      if (!candidate.dropped) _insert(candidate);
    }
    _resolveConflicts(candidates);
    // Only after conflicts are resolved: a dropped file must not spell the
    // directories above it, or rebuilding from the tree's entries, which
    // leave it out, would spell them differently.
    _implySpellings(candidates);
    _markContributions(candidates);
    return _materialize(fixedRoots ?? _chooseRoots(), candidates);
  }

  String _fold(String text) => _foldWith(policy, text);

  void _issue(_Candidate<T> candidate, TreeIssueKind kind, String message) {
    candidate.dropped = true;
    _entryIssues[candidate.position] = TreeIssue<T>(
      kind: kind,
      path: candidate.entry.path,
      entry: candidate.entry,
      message: message,
    );
  }

  List<_Candidate<T>> _parseCandidates() {
    final candidates = <_Candidate<T>>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final entry = item.entry;
      final path = item.path;
      if (path == null) {
        _entryIssues[i] = TreeIssue<T>(
          kind: TreeIssueKind.invalidPath,
          path: entry.path,
          entry: entry,
          message: '${item.error}; the entry was skipped.',
        );
      } else if (entry.isFile && path.isRoot) {
        _entryIssues[i] = TreeIssue<T>(
          kind: TreeIssueKind.invalidPath,
          path: entry.path,
          entry: entry,
          message: 'A file entry cannot be a path root; the entry was skipped.',
        );
      } else {
        candidates.add(_Candidate<T>(entry, path, item.key!, i));
      }
    }
    return candidates;
  }

  _Slot<T> _topSlot(String root) => _tops[_fold(root)] ??= _Slot<T>(null);

  _Slot<T> _childSlot(_Slot<T> slot, String segment) =>
      (slot.children ??= <String, _Slot<T>>{})[_fold(segment)] ??= _Slot<T>(
        slot,
      );

  void _imply(_Slot<T> slot, String spelling) {
    final current = slot.implied;
    // Case-sensitive policies cannot merge different spellings, so the
    // first spelling is the only one.
    if (current == null ||
        (!policy.caseSensitive && spelling.compareTo(current) < 0)) {
      slot.implied = spelling;
    }
  }

  void _insert(_Candidate<T> candidate) {
    final path = candidate.path;
    var slot = _topSlot(path.root);
    for (final segment in path.segments) {
      slot = _childSlot(slot, segment);
    }
    slot.candidate = candidate;
    candidate.slot = slot;
  }

  /// Records, for every accepted entry, its spelling of each directory its
  /// path passes strictly through, walking up from its slot. Every slot
  /// with children keeps an accepted entry below it (only files with
  /// children are dropped, and a leaf slot's entry is never one), so every
  /// inferred directory gets a spelling. O(total path segments).
  void _implySpellings(List<_Candidate<T>> candidates) {
    for (final candidate in candidates) {
      if (candidate.dropped) continue;
      final path = candidate.path;
      // A parsed path's segments are a stored list, so this is O(1).
      final segments = path.segments;
      var slot = candidate.slot!;
      for (var i = segments.length - 1; i > 0; i--) {
        slot = slot.parent!;
        _imply(slot, segments[i - 1]);
      }
      if (segments.isNotEmpty) _imply(slot.parent!, path.root);
    }
  }

  List<_Slot<T>> _placeFixedRoots(List<_Candidate<T>> candidates) {
    final parsed = <TreePath>[];
    for (final raw in options.roots.fixedPaths) {
      try {
        parsed.add(policy.parse(raw));
      } on FormatException catch (error) {
        _rootIssues.add(
          TreeIssue<T>(
            kind: TreeIssueKind.invalidPath,
            path: raw,
            message: '${error.message}; the root was ignored.',
          ),
        );
      }
    }
    // Outer roots first, so a nested root always finds its outer root
    // already placed. Equal depths cannot nest, so their order is irrelevant.
    parsed.sort((a, b) => a.segments.length.compareTo(b.segments.length));

    final roots = <_Slot<T>>[];
    for (final path in parsed) {
      final segments = path.segments;
      var slot = _tops[_fold(path.root)];
      var nested = false;
      for (var i = 0; slot != null && i < segments.length; i++) {
        if (slot.fixedPath != null) {
          nested = true;
          break;
        }
        slot = slot.children?[_fold(segments[i])];
      }
      if (nested) continue;
      final existing = slot?.fixedPath;
      if (existing != null) {
        // A duplicate under the policy: keep the smallest spelling so the
        // result does not depend on the order of the list.
        if (path.compareTo(existing) < 0) slot!.fixedPath = path;
        continue;
      }
      var placed = _topSlot(path.root);
      for (final segment in segments) {
        placed = _childSlot(placed, segment);
      }
      placed.fixedPath = path;
      roots.add(placed);
    }

    for (final candidate in candidates) {
      _checkFixedPlacement(candidate);
    }
    return roots;
  }

  void _checkFixedPlacement(_Candidate<T> candidate) {
    final segments = candidate.path.segments;
    var slot = _tops[_fold(candidate.path.root)];
    for (var i = 0; slot != null; i++) {
      if (slot.fixedPath != null) {
        if (i == segments.length && candidate.entry.isFile) {
          _issue(
            candidate,
            TreeIssueKind.conflict,
            'The file entry equals a fixed root, which is always a '
            'directory; the file entry was dropped.',
          );
        }
        return;
      }
      if (i == segments.length) break;
      slot = slot.children?[_fold(segments[i])];
    }
    _issue(
      candidate,
      TreeIssueKind.outsideRoots,
      'The entry is outside every fixed root; the entry was dropped.',
    );
  }

  void _resolveConflicts(List<_Candidate<T>> candidates) {
    for (final candidate in candidates) {
      if (candidate.dropped || !candidate.entry.isFile) continue;
      final slot = candidate.slot!;
      if (slot.children == null) continue;
      // Another entry lies inside this file's path, so the path must be a
      // directory. The slot stays as an inferred directory.
      slot.candidate = null;
      _issue(
        candidate,
        TreeIssueKind.conflict,
        'The file entry is an ancestor of another entry, so the path is a '
        'directory; the file entry was dropped.',
      );
    }
  }

  void _markContributions(List<_Candidate<T>> candidates) {
    for (final candidate in candidates) {
      if (candidate.dropped) continue;
      final slot = candidate.slot!;
      if (candidate.entry.isFile) {
        slot.parent!.contributes = true;
      } else {
        slot.contributes = true;
      }
    }
  }

  List<_Slot<T>> _chooseRoots() {
    switch (options.roots.kind) {
      case TreeRootsKind.minimal:
        final roots = <_Slot<T>>[];
        final stack = <_Slot<T>>[..._tops.values];
        while (stack.isNotEmpty) {
          final slot = stack.removeLast();
          if (slot.contributes) {
            roots.add(slot);
            continue;
          }
          final children = slot.children;
          if (children != null) stack.addAll(children.values);
        }
        return roots;
      case TreeRootsKind.commonAncestor:
        return [for (final top in _tops.values) _deepestCommonSlot(top)];
      case TreeRootsKind.filesystem:
        return _tops.values.toList();
      case TreeRootsKind.fixed:
        throw StateError('Fixed roots are placed before entries.');
    }
  }

  /// Descends from [top] while the current slot is not a contribution and
  /// has a single child: the deepest slot containing every contribution.
  _Slot<T> _deepestCommonSlot(_Slot<T> top) {
    var slot = top;
    while (!slot.contributes) {
      final children = slot.children;
      if (children == null || children.length != 1) break;
      slot = children.values.first;
    }
    return slot;
  }

  TreePath _rootPath(_Slot<T> root) {
    final candidate = root.candidate;
    if (candidate != null) return candidate.path;
    final fixed = root.fixedPath;
    if (fixed != null) return fixed;
    // An inferred root: spell each level with its smallest implied
    // spelling, from the path root down.
    final segments = <String>[];
    var slot = root;
    for (var parent = slot.parent; parent != null; parent = slot.parent) {
      segments.add(slot.implied!);
      slot = parent;
    }
    return createTreePath(slot.implied!, segments.reversed.toList());
  }

  DirectoryTree<T> _materialize(
    List<_Slot<T>> roots,
    List<_Candidate<T>> candidates,
  ) {
    // Top-down: display paths, ids, and depths. Parents precede children in
    // [order], which is all the later passes rely on.
    final order = <_Slot<T>>[];
    for (final root in roots) {
      root
        ..isRoot = true
        ..path = _rootPath(root)
        // A root with an entry uses the entry's parsed path, whose id the
        // builder already computed.
        ..id = root.candidate?.key ?? policy.idOf(root.path);
      order.add(root);
    }
    for (var i = 0; i < order.length; i++) {
      final slot = order[i];
      final children = slot.children;
      if (children == null) continue;
      for (final child in children.values) {
        child.depth = slot.depth + 1;
        final candidate = child.candidate;
        if (candidate == null) {
          child
            ..path = appendTreePathSegment(slot.path, child.implied!)
            ..id = policy.idOf(child.path);
        } else {
          // An entry node shares its entry's strings instead of building
          // equal copies: the parsed canonical string whenever the parents
          // are spelled as in the entry (for an already canonical input it
          // is the entry's path string itself), and the id, which only
          // folds letter case. A case-sensitive policy keys slots by exact
          // spelling, so there the parents always match and need no check.
          final parsed = candidate.path;
          final name = parsed.name;
          final string = parsed.toString();
          final shared =
              policy.caseSensitive || isChildString(slot.path, name, string);
          child
            ..path = appendTreePathSegment(
              slot.path,
              name,
              canonical: shared ? string : null,
            )
            ..id = candidate.key;
        }
        assert(
          child.id == policy.idOf(child.path),
          'A node id must be the policy id of its display path.',
        );
        order.add(child);
      }
    }

    _labelRoots(roots);

    // Bottom-up: a node is created after all of its children, so its
    // children list can be sorted with the user comparator over finished
    // child nodes, and every node is created exactly once.
    final compareNodes = options.order;
    int compare(_Slot<T> a, _Slot<T> b) {
      final result = compareNodes(a.node, b.node);
      return result != 0 ? result : a.id.value.compareTo(b.id.value);
    }

    var fileCount = 0;
    for (var i = order.length - 1; i >= 0; i--) {
      final slot = order[i];
      final entry = slot.candidate?.entry;
      final parentId = slot.isRoot ? null : slot.parent!.id;
      if (entry != null && entry.isFile) {
        // Files contribute their parent directory, so every top-level node
        // is a directory and a file's label is always its name.
        assert(!slot.isRoot, 'A file cannot be a top-level node.');
        fileCount++;
        slot.node = FileNode<T>._(
          id: slot.id,
          path: slot.path,
          parent: parentId,
          depth: slot.depth,
          entry: entry,
        );
        continue;
      }
      final children = slot.children;
      if (children != null) {
        final sorted = children.values.toList(growable: false)..sort(compare);
        var size = 1;
        for (final child in sorted) {
          size += child.size;
        }
        slot
          ..sorted = sorted
          ..size = size;
      }
      slot.node = DirectoryNode<T>._(
        id: slot.id,
        path: slot.path,
        label: slot.isRoot ? slot.label : slot.path.name,
        parent: parentId,
        depth: slot.depth,
        entry: entry,
        children: List<NodeId>.unmodifiable(
          slot.sorted.map((child) => child.id),
        ),
      );
    }
    roots.sort(compare);

    // Pre-order with an explicit stack: deep trees cannot overflow.
    final count = order.length;
    final nodes = <TreeNode<T>>[];
    final indexById = <NodeId, int>{};
    final parentIndices = Int32List(count);
    final subtreeSizes = Int32List(count);
    final rootIndices = <int>[];
    final stack = roots.reversed.toList();
    while (stack.isNotEmpty) {
      final slot = stack.removeLast();
      final index = nodes.length;
      slot.index = index;
      nodes.add(slot.node);
      indexById[slot.id] = index;
      subtreeSizes[index] = slot.size;
      if (slot.isRoot) {
        parentIndices[index] = -1;
        rootIndices.add(index);
      } else {
        parentIndices[index] = slot.parent!.index;
      }
      final sorted = slot.sorted;
      for (var k = sorted.length - 1; k >= 0; k--) {
        stack.add(sorted[k]);
      }
    }
    assert(indexById.length == count, 'Two tree nodes share a NodeId.');

    return DirectoryTree<T>._(
      options: options,
      nodes: List<TreeNode<T>>.unmodifiable(nodes),
      indexById: indexById,
      parentIndices: parentIndices,
      subtreeSizes: subtreeSizes,
      rootIndices: List<int>.unmodifiable(rootIndices),
      entries: List<TreeEntry<T>>.unmodifiable([
        for (final candidate in candidates)
          if (!candidate.dropped) candidate.entry,
      ]),
      issues: List<TreeIssue<T>>.unmodifiable([
        ..._rootIssues,
        for (final issue in _entryIssues) ?issue,
      ]),
      fileCount: fileCount,
    );
  }

  /// Labels top-level slots: their name, unless other roots share it; then
  /// the shortest trailing path that is unique within the colliding group,
  /// falling back to the full canonical path.
  ///
  /// The result is that of growing every colliding label one segment at a
  /// time until it is unique, without building the labels in between: a
  /// root needs one segment more than the longest suffix it shares with
  /// another root of its group (at least two). A trie over the reversed
  /// segment lists finds that length for every root in O(total segments),
  /// and each label is joined once. Trailing labels with different numbers
  /// of segments cannot be equal (segments never contain `/`), and a full
  /// path equals a trailing label only for a drive root, whose `C:/a`
  /// reads like the segments `C:` and `a`, so the drive counts as one more
  /// segment when suffixes are compared.
  void _labelRoots(List<_Slot<T>> roots) {
    final groups = <String, List<_Slot<T>>>{};
    for (final root in roots) {
      (groups[root.path.name] ??= <_Slot<T>>[]).add(root);
    }
    for (final group in groups.values) {
      if (group.length == 1) {
        group.first.label = group.first.path.name;
        continue;
      }
      final suffixes = [for (final root in group) _labelSegments(root.path)];
      final trie = _SuffixNode();
      for (final segments in suffixes) {
        var node = trie;
        for (var i = segments.length - 1; i >= 0; i--) {
          node = (node.children ??= <String, _SuffixNode>{})[segments[i]] ??=
              _SuffixNode();
          node.count++;
        }
      }
      for (var r = 0; r < group.length; r++) {
        final segments = suffixes[r];
        // The first suffix length no other root shares, or one past the
        // whole list when another root ends with all of it.
        var take = 0;
        var node = trie;
        while (take < segments.length) {
          node = node.children![segments[segments.length - 1 - take]]!;
          take++;
          if (node.count == 1) break;
        }
        if (node.count != 1) take++;
        if (take < 2) take = 2;
        final path = group[r].path;
        final names = path.segments;
        group[r].label = take > names.length
            ? path.toString()
            : names.getRange(names.length - take, names.length).join('/');
      }
    }
    assert(
      roots.map((root) => root.label).toSet().length == roots.length,
      'Root labels must be unique.',
    );
  }

  /// The segments of a root [path] as its labels read them: its segments,
  /// preceded by the drive (`C:`) for a drive root, whose full path
  /// `C:/a` is spelled like the trailing label of the segments `C:` and
  /// `a`. Root paths are parsed or created in list form, so reading
  /// [TreePath.segments] is O(1).
  static List<String> _labelSegments(TreePath path) {
    final root = path.root;
    final segments = path.segments;
    final isDrive =
        root.length == 3 &&
        root.codeUnitAt(1) == 0x3A && // :
        isAsciiLetter(root.codeUnitAt(0));
    if (!isDrive) return segments;
    return [root.substring(0, 2), ...segments];
  }
}

/// A node of the reversed-suffix trie in [_TreeAssembler._labelRoots]:
/// how many roots of a group end with the segments that lead to it.
final class _SuffixNode {
  int count = 0;
  Map<String, _SuffixNode>? children;
}
