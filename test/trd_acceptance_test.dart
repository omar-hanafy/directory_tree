// Port of every case in the 1.x test/compliance_test.dart to the 2.x API.
//
// Mapping: 1.x `TreeBuilder` with anchor compression and case-insensitive
// paths is `TreeRoots.minimal()` with `PathPolicy.caseInsensitive`; 1.x
// "origin direct/inferred" is `TreeNode.isExplicit`; 1.x depth-0 names are
// root labels; 1.x `stripPrefixes` source paths become full `node.path`
// expectations (2.x has no prefix stripping).
import 'package:directory_tree/directory_tree.dart';
import 'package:test/test.dart';

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

DirectoryTree<Never> buildTree({
  required List<String> files,
  List<String> selectedDirs = const [],
  String Function(String path)? unicodeNormalize,
}) => DirectoryTree<Never>.build(
  [
    for (final file in files) TreeEntry<Never>.file(file),
    for (final dir in selectedDirs) TreeEntry<Never>.directory(dir),
  ],
  options: TreeOptions(
    paths: PathPolicy(
      caseSensitive: false,
      unicodeNormalizer: unicodeNormalize,
    ),
    roots: const TreeRoots.minimal(),
  ),
);

List<String> depthNames(DirectoryTree<Object?> tree, int depth) => [
  for (final node in tree.nodes)
    if (node.depth == depth) depth == 0 ? node.label : node.name,
];

String dump(DirectoryTree<Object?> tree) => tree.nodes
    .map(
      (node) =>
          '${'  ' * node.depth}${node.isDirectory ? 'dir ' : 'file'} '
          '${node.label}  [path=${node.path}, explicit=${node.isExplicit}]',
    )
    .join('\n');

TreeNode<Object?> nodeAt(DirectoryTree<Object?> tree, int depth, String name) =>
    tree.nodes.firstWhere(
      (node) =>
          node.depth == depth && (depth == 0 ? node.label : node.name) == name,
      orElse: () => throw TestFailure(
        'Expected to find "$name" at depth=$depth.\n\nTree:\n${dump(tree)}',
      ),
    );

List<String> childNames(DirectoryTree<Object?> tree, String rootLabel) => [
  for (final child in tree.childrenOf(nodeAt(tree, 0, rootLabel).id))
    child.name,
];

void main() {
  group('TRD acceptance cases', () {
    test('Case A - one file under .../scan/models/ -> top parent: models', () {
      final tree = buildTree(files: [fileCategory]);
      expect(depthNames(tree, 0), ['models'], reason: dump(tree));
      expect(nodeAt(tree, 1, 'file_category.dart').isFile, isTrue);
      expect(nodeAt(tree, 0, 'models').isExplicit, isFalse);
    });

    test('Case B - plus a sibling under .../scan/services/ -> top parents: '
        'models, services', () {
      final tree = buildTree(files: [fileCategory, markdownBuilder]);
      expect(depthNames(tree, 0), ['models', 'services'], reason: dump(tree));
      expect(nodeAt(tree, 1, 'file_category.dart').isFile, isTrue);
      expect(nodeAt(tree, 1, 'markdown_builder.dart').isFile, isTrue);
    });

    test(
      'Case C - plus .../scan/scan.dart -> top parent collapses to: scan',
      () {
        final tree = buildTree(
          files: [fileCategory, markdownBuilder, scanDart],
        );
        expect(depthNames(tree, 0), ['scan'], reason: dump(tree));
        expect(childNames(tree, 'scan'), ['models', 'services', 'scan.dart']);
        final scanNode = nodeAt(tree, 0, 'scan');
        expect(scanNode.isExplicit, isFalse);
        // 1.x asserted the stripped source path '/lib/src/features/scan'.
        expect(scanNode.path.toString(), scan);
      },
    );

    test('Case D - add directory-only .../features/editor/ -> top parents: '
        'editor (explicit), scan (inferred)', () {
      final tree = buildTree(
        files: [fileCategory, markdownBuilder, scanDart],
        selectedDirs: [editor],
      );
      expect(depthNames(tree, 0), ['editor', 'scan'], reason: dump(tree));
      expect(nodeAt(tree, 0, 'editor').isExplicit, isTrue);
      expect(nodeAt(tree, 0, 'scan').isExplicit, isFalse);
    });

    test('Case E.1 - add file .../lib/src/context_collector.dart -> top '
        'parent becomes: src (inferred)', () {
      final tree = buildTree(
        files: [fileCategory, markdownBuilder, scanDart, contextCollectorDart],
        selectedDirs: [editor],
      );
      expect(depthNames(tree, 0), ['src'], reason: dump(tree));
      expect(nodeAt(tree, 0, 'src').isExplicit, isFalse);
      final kids = childNames(tree, 'src');
      expect(kids, contains('context_collector.dart'));
      expect(kids, contains('features'));
    });

    test('Case E.2 - add directory .../lib/src/ (explicit) -> top parent: '
        'src (explicit)', () {
      final tree = buildTree(
        files: [fileCategory, markdownBuilder, scanDart],
        selectedDirs: [editor, src],
      );
      expect(depthNames(tree, 0), ['src'], reason: dump(tree));
      expect(nodeAt(tree, 0, 'src').isExplicit, isTrue);
    });

    test('Case F - add repo root file .../pubspec.yaml -> top parent: '
        'context_collector', () {
      final tree = buildTree(
        files: [
          fileCategory,
          markdownBuilder,
          scanDart,
          contextCollectorDart,
          pubspecYaml,
        ],
        selectedDirs: [editor],
      );
      expect(depthNames(tree, 0), ['context_collector'], reason: dump(tree));
      // 1.x asserted the stripped source path '/context_collector'.
      expect(nodeAt(tree, 0, 'context_collector').path.toString(), repo);
    });
  });

  group('Normalization, dedup and stability (TRD 3, 11)', () {
    test('dedups files by normalized path (case-insensitive) even when '
        'spelled differently', () {
      const dupeA = '$models/FILE_CATEGORY.dart';
      const dupeB = '$models/file_category.dart';
      final tree = buildTree(files: [dupeA, dupeB]);
      expect(depthNames(tree, 0), ['models'], reason: dump(tree));
      final files = tree.files.toList();
      expect(files, hasLength(1), reason: dump(tree));
      // 2.x is precise: the later entry wins.
      expect(files.single.name, 'file_category.dart');
    });

    test(
      'directory-only selections dedup and persist with trailing slashes',
      () {
        final tree = buildTree(files: [], selectedDirs: ['$editor/', editor]);
        expect(depthNames(tree, 0), ['editor'], reason: dump(tree));
        expect(nodeAt(tree, 0, 'editor').isExplicit, isTrue);
      },
    );

    test('Unicode normalization hook is honored (NFC) for anchors', () {
      // "cafe\u0301" (NFD) and "caf\u00e9" (NFC) are the same name.
      const nfdDir = '$features/cafe\u0301';
      const nfcDir = '$features/caf\u00e9';
      const fileNfd = '$nfdDir/readme.md';
      const fileNfc = '$nfcDir/README.md';
      final tree = buildTree(
        files: [fileNfd, fileNfc],
        selectedDirs: [nfdDir, nfcDir],
        unicodeNormalize: (path) => path.replaceAll('e\u0301', '\u00e9'),
      );
      expect(depthNames(tree, 0), ['caf\u00e9'], reason: dump(tree));
      expect(nodeAt(tree, 0, 'caf\u00e9').isExplicit, isTrue);
      expect(tree.fileCount, 1);
    });

    test('Windows-style paths normalize and dedup to a single top parent '
        '(TRD 8.9)', () {
      final tree = DirectoryTree<Never>.build(const [
        TreeEntry.file(r'C:\work\repo\lib\a.dart'),
        TreeEntry.file('c:/work/repo/lib/a.dart'),
      ], options: const TreeOptions(paths: PathPolicy.caseInsensitive));
      expect(depthNames(tree, 0), ['lib'], reason: dump(tree));
      expect(tree.fileCount, 1, reason: dump(tree));
      expect(tree.rootNodes.single.path.toString(), 'C:/work/repo/lib');
    });

    test('symlink-like literals stay distinct top parents (TRD 8.10)', () {
      const symlinkDir = '$repo/link_to_lib';
      final tree = buildTree(files: ['$lib/a.dart', '$symlinkDir/a.dart']);
      expect(depthNames(tree, 0), ['lib', 'link_to_lib'], reason: dump(tree));
      expect(
        tree.files.where((node) => node.name == 'a.dart'),
        hasLength(2),
        reason: dump(tree),
      );
    });

    test('hidden dotfiles render the same as normal files (TRD 8.12)', () {
      final tree = buildTree(files: ['$repo/.env', '$repo/app.dart']);
      expect(depthNames(tree, 0), ['context_collector'], reason: dump(tree));
      expect(childNames(tree, 'context_collector'), ['.env', 'app.dart']);
    });
  });

  group('Ordering and UI surface (TRD 5, 6)', () {
    test('folders first then files, alpha by name (case-insensitive)', () {
      final tree = buildTree(files: ['$scan/Zeta.md', '$scan/alpha.md']);
      expect(depthNames(tree, 0), ['scan'], reason: dump(tree));
      expect(childNames(tree, 'scan'), ['alpha.md', 'Zeta.md']);
    });

    test('top parents render at depth 0 (no container row)', () {
      final tree = buildTree(files: [fileCategory, markdownBuilder]);
      expect(depthNames(tree, 0), ['models', 'services'], reason: dump(tree));
      expect(
        tree.nodes.where((node) => node.depth == 1 && node.isFile),
        hasLength(2),
        reason: dump(tree),
      );
    });
  });

  group('Anchor compression and edge behaviors (TRD 4, 8)', () {
    test('selecting overlapping directories (scan/ and scan/models/) -> top '
        'parent is scan only', () {
      final tree = buildTree(files: [], selectedDirs: [scan, models]);
      expect(depthNames(tree, 0), ['scan'], reason: dump(tree));
    });

    test('removing scan/ while scan/models/ remains -> top parent falls back '
        'to models (TRD 12)', () {
      final before = buildTree(files: [], selectedDirs: [scan, models]);
      expect(depthNames(before, 0), ['scan'], reason: dump(before));

      final after = buildTree(files: [], selectedDirs: [models]);
      expect(depthNames(after, 0), ['models'], reason: dump(after));
      expect(nodeAt(after, 0, 'models').isExplicit, isTrue);

      // The same transition as an incremental rebuild.
      final rebuilt = before.rebuild(
        (builder) => builder.remove(scan, recursive: false),
      );
      expect(rebuilt, after);
    });

    test('unknown-type promotion lifts a directory to top parent once '
        'metadata arrives (TRD 11.5, 12)', () {
      const unknownDir = '$features/newtop';

      final phase1 = buildTree(files: [unknownDir]);
      expect(depthNames(phase1, 0), ['features'], reason: dump(phase1));

      final phase2 = buildTree(files: [], selectedDirs: [unknownDir]);
      expect(depthNames(phase2, 0), ['newtop'], reason: dump(phase2));
      expect(nodeAt(phase2, 0, 'newtop').isExplicit, isTrue);
    });

    test('two disjoint trees -> two top parents', () {
      const otherRoot = '/some/other/project/lib';
      final tree = buildTree(files: [], selectedDirs: [editor, otherRoot]);
      expect(depthNames(tree, 0), ['editor', 'lib'], reason: dump(tree));
    });

    test('idempotent file adds: the same path twice does not duplicate '
        'leaves', () {
      final tree = buildTree(files: [fileCategory, fileCategory]);
      final files = tree.files.toList();
      expect(files, hasLength(1), reason: dump(tree));
      expect(files.single.name, 'file_category.dart');
    });

    test('each selected file appears exactly once under a single top parent '
        '(C2)', () {
      final tree = buildTree(files: [fileCategory, markdownBuilder, scanDart]);
      for (final entry in tree.entries) {
        expect(
          tree.nodes.where((node) => identical(node.entry, entry)),
          hasLength(1),
          reason: dump(tree),
        );
      }
      expect(tree.roots, hasLength(1));
    });

    test('selecting a top anchor directly does not create a "." child', () {
      final tree = buildTree(files: [], selectedDirs: [src]);
      expect(depthNames(tree, 0), ['src'], reason: dump(tree));
      expect(childNames(tree, 'src'), isEmpty, reason: dump(tree));
    });
  });
}
