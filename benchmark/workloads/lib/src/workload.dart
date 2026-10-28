import 'dart:math' as math;

import 'random.dart';

/// The overall shape of a generated tree.
enum WorkloadShape {
  /// Project-like trees: depth about 8-14, directories of roughly 5-30
  /// entries.
  deep,

  /// Shallow trees (files at depth 2-3) with very large directories
  /// (thousands to tens of thousands of files each).
  wide;

  /// Parses a shape name such as `deep` or `wide`.
  static WorkloadShape parse(String name) => WorkloadShape.values.firstWhere(
    (s) => s.name == name,
    orElse: () => throw FormatException('Unknown shape "$name"'),
  );
}

/// The sizes (file counts) the benchmark suite runs by default.
const List<int> standardSizes = [10000, 100000, 1000000];

/// The absolute directory every generated path lives under.
const String workloadRoot = '/repo';

/// The name fragment the filter workload searches for.
///
/// Only file names contain it (never directory names), and the generators
/// put it in about 3% of them. It is a plain substring so every
/// implementation's query syntax accepts it.
const String filterFragment = 'legacy';

/// A deterministic list of absolute POSIX file paths plus the derived inputs
/// the benchmark operations need.
class Workload {
  Workload._({
    required this.shape,
    required this.size,
    required this.seed,
    required this.paths,
    required this.folderCount,
    required this.maxFileDepth,
    required this.toggleTarget,
    required this.toggleTargetFileCount,
    required this.filterMatchCount,
  });

  /// The seed used when callers do not pass one.
  static const int defaultSeed = 20261028;

  /// Generates the workload for [shape] and [size] files.
  ///
  /// The same arguments produce an identical [paths] list on every run and
  /// machine.
  factory Workload.generate(
    WorkloadShape shape,
    int size, {
    int seed = defaultSeed,
  }) {
    if (size < 100) {
      throw ArgumentError.value(size, 'size', 'must be at least 100');
    }
    final gen = _Generator(SeededRandom(seed ^ (shape.index * 0x9E3779B9)));
    switch (shape) {
      case WorkloadShape.deep:
        gen.generateDeep(size);
      case WorkloadShape.wide:
        gen.generateWide(size);
    }
    assert(gen.paths.length == size, 'generator produced the wrong count');
    final target = gen.pickToggleTarget(size);
    return Workload._(
      shape: shape,
      size: size,
      seed: seed,
      paths: List.unmodifiable(gen.paths),
      folderCount: gen.dirs.length,
      maxFileDepth: gen.maxFileDepth,
      toggleTarget: target.path,
      toggleTargetFileCount: target.fileCount,
      filterMatchCount: gen.filterMatches,
    );
  }

  /// The tree shape.
  final WorkloadShape shape;

  /// The number of file paths.
  final int size;

  /// The seed the paths were generated from.
  final int seed;

  /// Absolute POSIX file paths under [workloadRoot], in generation (depth
  /// first) order. Every path is unique, also case-insensitively.
  final List<String> paths;

  /// The number of distinct directories, including [workloadRoot].
  final int folderCount;

  /// The largest number of path segments below [workloadRoot] of any file.
  final int maxFileDepth;

  /// A directory near the middle of the tree whose subtree holds a large
  /// share of the files. The toggle operation collapses it.
  final String toggleTarget;

  /// The number of files below [toggleTarget].
  final int toggleTargetFileCount;

  /// The query for the filter operation.
  String get filterQuery => filterFragment;

  /// The number of files whose name contains [filterQuery].
  final int filterMatchCount;

  /// A stable FNV-1a (32-bit) hash of [paths], as 8 hex digits.
  ///
  /// Implementations report it so results can be checked to come from the
  /// same input.
  late final String fingerprint = _fingerprint(paths);

  /// A JSON-friendly summary of this workload.
  Map<String, Object> describe() => {
    'shape': shape.name,
    'size': size,
    'seed': seed,
    'fingerprint': fingerprint,
    'folders': folderCount,
    'max_file_depth': maxFileDepth,
    'toggle_target': toggleTarget,
    'toggle_target_files': toggleTargetFileCount,
    'filter_query': filterQuery,
    'filter_matches': filterMatchCount,
  };

  static String _fingerprint(List<String> paths) {
    var hash = 0x811C9DC5;
    void add(int unit) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }

    for (final path in paths) {
      for (final unit in path.codeUnits) {
        add(unit);
      }
      add(0x0A);
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

class _Dir {
  _Dir(this.path, this.depth);

  final String path;
  final int depth;
  int fileCount = 0;
}

const _dirWords = [
  'src', 'lib', 'app', 'core', 'common', 'shared', 'utils', 'helpers', //
  'components', 'widgets', 'screens', 'pages', 'features', 'services',
  'models', 'data', 'domain', 'presentation', 'api', 'client', 'server',
  'config', 'assets', 'styles', 'hooks', 'store', 'state', 'auth', 'billing',
  'payments', 'profile', 'settings', 'search', 'analytics', 'network',
  'storage', 'cache', 'db', 'test', 'fixtures', 'mocks', 'internal',
  'platform', 'android', 'ios', 'web', 'desktop', 'cli', 'tools', 'scripts',
  'docs', 'examples', 'generated', 'proto', 'schema', 'l10n', 'theme',
  'layout', 'routing', 'navigation', 'editor', 'renderer', 'parser',
  'compiler', 'runtime', 'plugins', 'extensions', 'modules', 'packages',
  'vendor', 'kernel', 'io', 'graphics', 'audio', 'video', 'ui', 'admin',
  'dashboard', 'reports', 'notifications', 'messaging', 'chat', 'feed',
  'media', 'upload', 'sync', 'offline', 'workers', 'jobs', 'queue', 'events',
  'logging', 'metrics', 'tracing', 'security', 'crypto', 'users', 'accounts',
  'orders', 'cart', 'checkout', 'catalog', 'inventory', 'shipping',
];

const _fileWords = [
  'main', 'index', 'button', 'dialog', 'card', 'list', 'item', 'view', //
  'controller', 'service', 'repository', 'provider', 'model', 'entity',
  'mapper', 'adapter', 'factory', 'builder', 'handler', 'router', 'client',
  'request', 'response', 'error', 'result', 'config', 'constants', 'theme',
  'colors', 'strings', 'icons', 'helpers', 'utils', 'validator', 'formatter',
  'parser', 'serializer', 'cache', 'store', 'reducer', 'action', 'effect',
  'state', 'event', 'bloc', 'cubit', 'screen', 'page', 'layout', 'header',
  'footer', 'sidebar', 'menu', 'toolbar', 'tab', 'form', 'field', 'input',
  'avatar', 'badge', 'chip', 'tooltip', 'banner', 'toast', 'spinner',
  'session', 'token', 'user', 'account', 'order', 'invoice', 'payment',
  'product', 'cart', 'search', 'filter', 'sort', 'pager', 'upload', 'image',
];

/// Extension weights for project-like trees.
const _deepExtensions = {
  'dart': 30, 'ts': 12, 'tsx': 6, 'js': 6, 'json': 8, 'md': 5, 'yaml': 5, //
  'png': 8, 'svg': 4, 'kt': 4, 'swift': 3, 'txt': 3, 'html': 2, 'css': 2,
  'sh': 1, 'proto': 1,
};

/// Extension weights for asset-like directories.
const _wideExtensions = {
  'png': 30, 'jpg': 25, 'json': 20, 'webp': 10, 'svg': 10, 'csv': 5, //
};

const _filterProbability = 0.03;

class _Generator {
  _Generator(this.rng);

  final SeededRandom rng;
  final paths = <String>[];
  final dirs = <_Dir>[];
  int maxFileDepth = 0;
  int filterMatches = 0;

  late final List<String> _deepExtList = _expand(_deepExtensions);
  late final List<String> _wideExtList = _expand(_wideExtensions);

  static List<String> _expand(Map<String, int> weights) => [
    for (final e in weights.entries) ...List.filled(e.value, e.key),
  ];

  /// Ancestor chain of the directory currently being filled, root first.
  final _stack = <_Dir>[];

  void _enter(String path) {
    final dir = _Dir(path, _stack.length);
    dirs.add(dir);
    _stack.add(dir);
  }

  void _leave() => _stack.removeLast();

  void _addFile(String name) {
    final dir = _stack.last;
    paths.add('${dir.path}/$name');
    for (final ancestor in _stack) {
      ancestor.fileCount++;
    }
    maxFileDepth = math.max(maxFileDepth, dir.depth + 1);
    if (name.contains(filterFragment)) filterMatches++;
  }

  String _uniqueDirName(Set<String> taken) {
    final word = rng.pick(_dirWords);
    var name = word;
    for (var i = 2; !taken.add(name); i++) {
      name = '${word}_$i';
    }
    return name;
  }

  String _uniqueFileName(Set<String> taken) {
    final ext = rng.pick(_deepExtList);
    final a = rng.pick(_fileWords);
    var stem = rng.chance(0.6) ? '${a}_${rng.pick(_fileWords)}' : a;
    if (rng.chance(_filterProbability)) stem = '${stem}_$filterFragment';
    var name = '$stem.$ext';
    for (var i = 2; !taken.add(name); i++) {
      name = '${stem}_$i.$ext';
    }
    return name;
  }

  // --- deep -----------------------------------------------------------------

  void generateDeep(int size) {
    _enter(workloadRoot);
    const rootFiles = [
      'README.md',
      'pubspec.yaml',
      'analysis_options.yaml',
      'LICENSE',
      '.gitignore',
    ];
    for (final f in rootFiles) {
      _addFile(f);
    }
    final topCount = rng.range(6, 12);
    final shares = _split(size - rootFiles.length, topCount);
    final taken = <String>{};
    for (final share in shares) {
      if (share == 0) continue;
      final name = _uniqueDirName(taken);
      _deepDir('$workloadRoot/$name', share, rng.range(7, 13));
    }
    _leave();
  }

  /// The deepest directory level, so files sit at most 14 segments below the
  /// root.
  static const _maxDirDepth = 13;

  /// Fills a directory with [budget] files spread over a subtree whose leaf
  /// directories sit about [target] levels below the root.
  void _deepDir(String path, int budget, int target) {
    _enter(path);
    final depth = _stack.length - 1;
    final names = <String>{};
    var levelsLeft = target - depth;
    if (levelsLeft <= 0 && budget > 30 && depth < _maxDirDepth) {
      levelsLeft = 1; // Too many files for one directory: go one level deeper.
    }
    if (levelsLeft <= 0 || budget <= 3 || depth >= _maxDirDepth) {
      for (var i = 0; i < budget; i++) {
        _addFile(_uniqueFileName(names));
      }
      _leave();
      return;
    }

    final files = math.min(
      budget - 1,
      depth < 3 ? rng.range(0, 3) : rng.range(1, 8),
    );
    for (var i = 0; i < files; i++) {
      _addFile(_uniqueFileName(names));
    }
    final remaining = budget - files;
    // Branching so that leaf directories end up with about 12 files.
    final base = math.pow(remaining / 12, 1 / levelsLeft).toDouble();
    final jitter = 0.7 + rng.nextDouble() * 0.6;
    final dirCount = (base * jitter)
        .round()
        .clamp(1, math.min(24, remaining))
        .toInt();
    final shares = _split(remaining, dirCount);
    for (final share in shares) {
      if (share == 0) continue;
      final childTarget = (target + rng.range(-1, 1))
          .clamp(depth + 1, _maxDirDepth)
          .toInt();
      _deepDir('$path/${_uniqueDirName(names)}', share, childTarget);
    }
    _leave();
  }

  /// Splits [total] into [parts] positive-ish random shares (zero only when
  /// [total] < [parts]).
  List<int> _split(int total, int parts) {
    final weights = [for (var i = 0; i < parts; i++) 0.3 + rng.nextDouble()];
    final sum = weights.fold<double>(0, (a, b) => a + b);
    final shares = [for (final w in weights) (total * w / sum).floor()];
    var left = total - shares.fold<int>(0, (a, b) => a + b);
    for (var i = 0; left > 0; i = (i + 1) % parts, left--) {
      shares[i]++;
    }
    return shares;
  }

  // --- wide -----------------------------------------------------------------

  void generateWide(int size) {
    _enter(workloadRoot);
    const rootFiles = ['README.md', 'manifest.json', 'LICENSE'];
    for (final f in rootFiles) {
      _addFile(f);
    }
    final leafMean = (math.sqrt(size) * 20).round().clamp(1000, 30000).toInt();
    final leafSizes = <int>[];
    var left = size - rootFiles.length;
    while (left > 0) {
      final n = math.min(left, (leafMean * (0.5 + rng.nextDouble())).round());
      leafSizes.add(n);
      left -= n;
    }
    if (leafSizes.length > 1 && leafSizes.last < leafMean ~/ 2) {
      leafSizes[leafSizes.length - 2] += leafSizes.removeLast();
    }

    final topNames = <String>{};
    var next = 0;
    while (next < leafSizes.length) {
      final name = _uniqueDirName(topNames);
      final flat = rng.chance(0.4);
      final count = flat
          ? 1
          : math.min(rng.range(2, 6), leafSizes.length - next);
      _enter('$workloadRoot/$name');
      if (flat) {
        _wideFiles(leafSizes[next]);
      } else {
        for (var i = 0; i < count; i++) {
          final shard = 'shard_${i.toString().padLeft(3, '0')}';
          _enter('$workloadRoot/$name/$shard');
          _wideFiles(leafSizes[next + i]);
          _leave();
        }
      }
      _leave();
      next += count;
    }
    _leave();
  }

  void _wideFiles(int count) {
    for (var i = 0; i < count; i++) {
      final word = rng.pick(_fileWords);
      final ext = rng.pick(_wideExtList);
      final marker = rng.chance(_filterProbability) ? '_$filterFragment' : '';
      _addFile('$word${marker}_${i.toString().padLeft(6, '0')}.$ext');
    }
  }

  // --- toggle target ----------------------------------------------------------

  /// Picks the median (by path) directory among those holding 5%-25% of all
  /// files, falling back to the largest non-root directory.
  _Dir pickToggleTarget(int size) {
    final candidates =
        dirs
            .where(
              (d) =>
                  d.depth >= 1 &&
                  d.fileCount >= size * 0.05 &&
                  d.fileCount <= size * 0.25,
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (candidates.isNotEmpty) return candidates[candidates.length ~/ 2];
    return dirs
        .where((d) => d.depth >= 1)
        .reduce((a, b) => b.fileCount > a.fileCount ? b : a);
  }
}
