import 'package:directory_tree/directory_tree.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // ---------- Constants mirroring the TRD paths ----------
  const repo = '/Users/omarhanafy/scripts/context_collector';
  const lib = '$repo/lib';
  const src = '$lib/src';
  const features = '$src/features';
  const scan = '$features/scan';
  const models = '$scan/models';
  const services = '$scan/services';
  const editor = '$features/editor';

  const fileCategory = '$models/file_category.dart';
  const markdownBuilder = '$services/markdown_builder.dart';
  const scanDart = '$scan/scan.dart';
  const contextCollectorDart = '$src/context_collector.dart';
  const pubspecYaml = '$repo/pubspec.yaml';

  // ---------- Helpers ----------
  TreeData buildTree({
    required List<String> files,
    List<String> selectedDirs = const [],
    List<String> stripPrefixes = const [repo],
    bool caseInsensitive = true,
    String Function(String)? unicodeNormalize,
  }) {
    final entries = <TreeEntry>[
      for (var i = 0; i < files.length; i++)
        TreeEntry(id: 'f$i', name: p.basename(files[i]), fullPath: files[i]),
    ];

    return TreeBuilder().build(
      entries: entries,
      selectedDirectories: selectedDirs,
      stripPrefixes: stripPrefixes,
      caseInsensitivePaths: caseInsensitive,
      unicodeNormalize: unicodeNormalize,
      omitContainerRowAtRoot: true,
      autoPickVisibleRoot: false,
      // TRD-safe defaults already applied by your patched builder.
    );
  }

  List<VisibleNode> flattenAll(TreeData data) {
    const flattener = SortedFlattenStrategy(AlphaSortDelegate());
    // Expand everything so we can assert structure precisely.
    return flattener.flatten(data: data, expandedIds: data.nodes.keys.toSet());
  }

  List<String> depthNames(List<VisibleNode> v, int depth) => v
      .where((n) => n.depth == depth)
      .map((n) => n.name)
      .toList(growable: false);

  String dump(List<VisibleNode> v) => v
      .map(
        (n) =>
            '${'  ' * n.depth}${n.type == NodeType.folder || n.type == NodeType.root ? '📁' : '📄'} ${n.name}'
            '  [path=${n.sourcePath ?? n.virtualPath}, origin=${n.origin}]',
      )
      .join('\n');

  VisibleNode nodeAt(List<VisibleNode> v, int depth, String name) =>
      v.firstWhere(
        (n) => n.depth == depth && n.name == name,
        orElse: () {
          throw TestFailure(
            'Expected to find "$name" at depth=$depth.\n\nTree:\n${dump(v)}',
          );
        },
      );

  Iterable<VisibleNode> childrenOf(
    List<VisibleNode> v,
    String parentNameAtDepth,
    int parentDepth,
  ) sync* {
    // In DFS order the children immediately follow parent until depth <= parentDepth.
    final parentIndex = v.indexWhere(
      (n) => n.depth == parentDepth && n.name == parentNameAtDepth,
    );
    if (parentIndex < 0) return;
    final parent = v[parentIndex];
    for (var i = parentIndex + 1; i < v.length; i++) {
      if (v[i].depth <= parent.depth) break;
      if (v[i].depth == parent.depth + 1) yield v[i];
    }
  }

  int countFilesWithEntryId(List<VisibleNode> v, String entryId) =>
      v.where((n) => n.entryId == entryId).length;

  // ---------- TRD Acceptance Cases ----------
  group('TRD Acceptance Cases', () {
    test(
      'Case A — add one file under .../scan/models/ → top parent: models',
      () {
        final data = buildTree(files: [fileCategory]);
        final vis = flattenAll(data);

        expect(depthNames(vis, 0), equals(['models']), reason: dump(vis));
        // models/ contains the file at depth 1
        expect(
          nodeAt(vis, 1, 'file_category.dart').type,
          NodeType.file,
          reason: dump(vis),
        );
        // models was inferred (not directly selected)
        expect(
          nodeAt(vis, 0, 'models').origin,
          SelectionOrigin.inferred,
          reason: dump(vis),
        );
      },
    );

    test(
      'Case B — plus a sibling under .../scan/services/ → top parents: models, services',
      () {
        final data = buildTree(files: [fileCategory, markdownBuilder]);
        final vis = flattenAll(data);

        expect(
          depthNames(vis, 0),
          equals(['models', 'services']),
          reason: dump(vis),
        );
        expect(
          nodeAt(vis, 1, 'file_category.dart').type,
          NodeType.file,
          reason: dump(vis),
        );
        expect(
          nodeAt(vis, 1, 'markdown_builder.dart').type,
          NodeType.file,
          reason: dump(vis),
        );
      },
    );

    test('Case C — plus .../scan/scan.dart → top parent collapses to: scan', () {
      final data = buildTree(files: [fileCategory, markdownBuilder, scanDart]);
      final vis = flattenAll(data);

      expect(depthNames(vis, 0), equals(['scan']), reason: dump(vis));

      // scan children: scan.dart (file), models/ (folder), services/ (folder)
      final kids = childrenOf(vis, 'scan', 0).map((n) => n.name).toList();
      expect(
        kids,
        equals(['models', 'services', 'scan.dart']),
        reason: dump(vis),
      );

      // scan top parent is inferred (we never directly selected /scan as a directory)
      expect(
        nodeAt(vis, 0, 'scan').origin,
        SelectionOrigin.inferred,
        reason: dump(vis),
      );
      // Strip prefix used as tooltip path base
      expect(
        nodeAt(vis, 0, 'scan').sourcePath,
        '/lib/src/features/scan',
        reason: dump(vis),
      );
    });

    test(
      'Case D — add directory-only .../features/editor/ → top parents: editor (direct), scan (inferred)',
      () {
        final data = buildTree(
          files: [fileCategory, markdownBuilder, scanDart],
          selectedDirs: [editor],
        );
        final vis = flattenAll(data);

        // Alphabetical at depth 0
        expect(
          depthNames(vis, 0),
          equals(['editor', 'scan']),
          reason: dump(vis),
        );

        expect(
          nodeAt(vis, 0, 'editor').origin,
          SelectionOrigin.direct,
          reason: dump(vis),
        );
        expect(
          nodeAt(vis, 0, 'scan').origin,
          SelectionOrigin.inferred,
          reason: dump(vis),
        );
      },
    );

    test(
      'Case E.1 — add file .../lib/src/context_collector.dart → top parent becomes: src (inferred)',
      () {
        final data = buildTree(
          files: [
            fileCategory,
            markdownBuilder,
            scanDart,
            contextCollectorDart,
          ],
          selectedDirs: [
            editor,
          ], // editor still selected, but src dominates as top
        );
        final vis = flattenAll(data);

        expect(depthNames(vis, 0), equals(['src']), reason: dump(vis));
        expect(
          nodeAt(vis, 0, 'src').origin,
          SelectionOrigin.inferred,
          reason: dump(vis),
        );

        // src should include a file context_collector.dart and features/ folder
        final kids = childrenOf(vis, 'src', 0).map((n) => n.name).toList();
        expect(kids, contains('context_collector.dart'), reason: dump(vis));
        expect(kids, contains('features'), reason: dump(vis));
      },
    );

    test(
      'Case E.2 — add directory .../lib/src/ (direct) → top parent: src (direct)',
      () {
        final data = buildTree(
          files: [fileCategory, markdownBuilder, scanDart],
          selectedDirs: [editor, src], // direct selection of src
        );
        final vis = flattenAll(data);

        expect(depthNames(vis, 0), equals(['src']), reason: dump(vis));
        expect(
          nodeAt(vis, 0, 'src').origin,
          SelectionOrigin.direct,
          reason: dump(vis),
        );
      },
    );

    test(
      'Case F — add repo root file .../pubspec.yaml → top parent: context_collector',
      () {
        final data = buildTree(
          files: [
            fileCategory,
            markdownBuilder,
            scanDart,
            contextCollectorDart,
            pubspecYaml,
          ],
          selectedDirs: [editor],
        );
        final vis = flattenAll(data);

        expect(
          depthNames(vis, 0),
          equals(['context_collector']),
          reason: dump(vis),
        );

        // With stripPrefixes, the top parent's sourcePath equals the prefix basename
        expect(
          nodeAt(vis, 0, 'context_collector').sourcePath,
          '/context_collector',
          reason: dump(vis),
        );
      },
    );
  });

  // ---------- Normalization, Dedup & Stability ----------
  group('Normalization, dedup & stability (TRD §3, §11)', () {
    test(
      'Dedups files by normalized path (case-insensitive) even with distinct ids',
      () {
        const dupeA = '$models/FILE_CATEGORY.dart';
        const dupeB = '$models/file_category.dart';

        final data = TreeBuilder().build(
          entries: [
            TreeEntry(id: 'A', name: p.basename(dupeA), fullPath: dupeA),
            TreeEntry(id: 'B', name: p.basename(dupeB), fullPath: dupeB),
          ],
          selectedDirectories: const [],
          caseInsensitivePaths: true,
        );
        final vis = flattenAll(data);

        // Top parent is models
        expect(depthNames(vis, 0), equals(['models']), reason: dump(vis));
        // Only ONE file node appears
        final files = vis.where((n) => n.type == NodeType.file).toList();
        expect(files.length, 1, reason: dump(vis));
        expect([
          'FILE_CATEGORY.dart',
          'file_category.dart',
        ], contains(files.single.name));
      },
    );

    test('Directory-only selections dedup & persist with trailing slashes', () {
      final data = buildTree(
        files: [],
        selectedDirs: ['$editor/', editor], // duplicated with trailing slash
      );
      final vis = flattenAll(data);

      expect(depthNames(vis, 0), equals(['editor']), reason: dump(vis));
      expect(
        nodeAt(vis, 0, 'editor').origin,
        SelectionOrigin.direct,
        reason: dump(vis),
      );
    });

    test('Unicode normalization hook is honored (NFC) for anchors', () {
      // "cafe\u0301" (NFD) → "café" (NFC)
      const nfdDir = '$features/cafe\u0301';
      const nfcDir = '$features/café';
      const fileNfd = '$nfdDir/readme.md';
      const fileNfc = '$nfcDir/README.md';

      final data = buildTree(
        files: [fileNfd, fileNfc],
        selectedDirs: [nfdDir, nfcDir],
        // Custom minimal normalizer for test: fold e+combining-acute → é
        unicodeNormalize: (s) => s.replaceAll('e\u0301', 'é'),
      );
      final vis = flattenAll(data);

      // After normalization, there should be a single top parent "café"
      expect(depthNames(vis, 0), equals(['café']), reason: dump(vis));
      expect(
        nodeAt(vis, 0, 'café').origin,
        SelectionOrigin.direct,
        reason: dump(vis),
      );
    });

    test(
      'Windows-style paths normalize & dedup to a single top parent (TRD §8.9)',
      () {
        final data = TreeBuilder().build(
          entries: const [
            TreeEntry(
              id: 'A',
              name: 'a.dart',
              fullPath: r'C:\work\repo\lib\a.dart',
            ),
            TreeEntry(
              id: 'B',
              name: 'a.dart',
              fullPath: 'c:/work/repo/lib/a.dart',
            ),
          ],
          stripPrefixes: const ['C:/work/repo'],
          caseInsensitivePaths: true,
        );
        final vis = flattenAll(data);

        expect(depthNames(vis, 0), equals(['lib']), reason: dump(vis));
        expect(
          vis.where((n) => n.type == NodeType.file).length,
          1,
          reason: dump(vis),
        );
      },
    );

    test('Symlink-like literals stay distinct top parents (TRD §8.10)', () {
      const symlinkDir = '$repo/link_to_lib';
      final data = buildTree(files: ['$lib/a.dart', '$symlinkDir/a.dart']);
      final vis = flattenAll(data);

      expect(
        depthNames(vis, 0),
        equals(['lib', 'link_to_lib']),
        reason: dump(vis),
      );
      expect(
        vis.where((n) => n.type == NodeType.file && n.name == 'a.dart').length,
        2,
        reason: dump(vis),
      );
    });

    test('Hidden dotfiles render the same as normal files (TRD §8.12)', () {
      final data = buildTree(files: ['$repo/.env', '$repo/app.dart']);
      final vis = flattenAll(data);

      expect(
        depthNames(vis, 0),
        equals(['context_collector']),
        reason: dump(vis),
      );
      final names = childrenOf(
        vis,
        'context_collector',
        0,
      ).map((n) => n.name).toList();
      expect(names, equals(['.env', 'app.dart']), reason: dump(vis));
    });
  });

  // ---------- Ordering & UI surface ----------
  group('Ordering & UI surface (TRD §5, §6)', () {
    test('Folders first then files, alpha by name (case-insensitive)', () {
      final data = buildTree(files: ['$scan/Zeta.md', '$scan/alpha.md']);
      final vis = flattenAll(data);
      // Top is scan
      expect(depthNames(vis, 0), equals(['scan']), reason: dump(vis));
      final children = childrenOf(vis, 'scan', 0).toList();

      // Under scan: folders first (none in this scenario), then files alphabetically
      final childNames = children.map((n) => n.name).toList();
      expect(childNames, equals(['alpha.md', 'Zeta.md']), reason: dump(vis));
    });

    test('Top parents render at depth 0 (omit container row)', () {
      final data = buildTree(files: [fileCategory, markdownBuilder]);
      final vis = flattenAll(data);

      // No label like "tree" at depth 0; the two top parents are depth 0
      expect(
        depthNames(vis, 0),
        equals(['models', 'services']),
        reason: dump(vis),
      );
      // Their children are depth 1
      expect(
        vis.where((n) => n.depth == 1 && n.type == NodeType.file).length,
        2,
        reason: dump(vis),
      );
    });
  });

  // ---------- Anchor compression & edge behaviors ----------
  group('Anchor compression & edge behaviors (TRD §4, §8)', () {
    test(
      'Selecting overlapping directories (scan/ and scan/models/) → top parent is scan only',
      () {
        final data = buildTree(files: [], selectedDirs: [scan, models]);
        final vis = flattenAll(data);

        expect(depthNames(vis, 0), equals(['scan']), reason: dump(vis));
      },
    );

    test(
      'Removing scan/ while scan/models/ remains → top parent falls back to models (TRD §12)',
      () {
        final before = buildTree(files: [], selectedDirs: [scan, models]);
        final visBefore = flattenAll(before);
        expect(
          depthNames(visBefore, 0),
          equals(['scan']),
          reason: dump(visBefore),
        );

        final after = buildTree(files: [], selectedDirs: [models]);
        final visAfter = flattenAll(after);

        expect(
          depthNames(visAfter, 0),
          equals(['models']),
          reason: dump(visAfter),
        );
        expect(
          nodeAt(visAfter, 0, 'models').origin,
          SelectionOrigin.direct,
          reason: dump(visAfter),
        );
      },
    );

    test(
      'Unknown-type promotion lifts directory to top parent once metadata arrives (TRD §11.5, §12)',
      () {
        const unknownDir = '$features/newtop';

        final phase1 = buildTree(files: [unknownDir]);
        final vis1 = flattenAll(phase1);
        expect(depthNames(vis1, 0), equals(['features']), reason: dump(vis1));

        final phase2 = buildTree(files: [], selectedDirs: [unknownDir]);
        final vis2 = flattenAll(phase2);

        expect(depthNames(vis2, 0), equals(['newtop']), reason: dump(vis2));
        expect(
          nodeAt(vis2, 0, 'newtop').origin,
          SelectionOrigin.direct,
          reason: dump(vis2),
        );
      },
    );

    test('Two disjoint trees → two top parents', () {
      const otherRoot = '/some/other/project/lib';
      final data = buildTree(files: [], selectedDirs: [editor, otherRoot]);
      final vis = flattenAll(data);

      // Alpha order: 'editor', then 'lib'
      expect(depthNames(vis, 0), equals(['editor', 'lib']), reason: dump(vis));
    });

    test('Idempotent file adds: same path twice does not duplicate leaves', () {
      final data = buildTree(files: [fileCategory, fileCategory]);
      final vis = flattenAll(data);

      // Only one file node with that name
      final files = vis.where((n) => n.type == NodeType.file).toList();
      expect(files.length, 1, reason: dump(vis));
      expect(files.single.name, 'file_category.dart', reason: dump(vis));
    });

    test(
      'Each selected file appears exactly once under a single top parent (C2)',
      () {
        final d = buildTree(files: [fileCategory, markdownBuilder, scanDart]);
        final vis = flattenAll(d);

        // Map entryId -> count should all be 1
        final fileNodes = vis.where((n) => n.type == NodeType.file).toList();
        for (final n in fileNodes) {
          expect(countFilesWithEntryId(vis, n.entryId!), 1, reason: dump(vis));
        }
      },
    );

    test('Selecting a top anchor directly does not create a "." child', () {
      final data = buildTree(files: [], selectedDirs: [src]);
      final vis = flattenAll(data);

      expect(depthNames(vis, 0), equals(['src']), reason: dump(vis));
      final kids = childrenOf(vis, 'src', 0).map((n) => n.name).toList();
      expect(kids, isEmpty, reason: dump(vis));
    });
  });
}
