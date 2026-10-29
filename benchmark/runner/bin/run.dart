import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:directory_tree_bench_harness/harness.dart';
import 'package:directory_tree_bench_runner/runner.dart';

const _usage = '''
Usage: dart run bin/run.dart [options]   (from benchmark/runner)

Compiles each implementation in benchmark/<impl>/ with `dart compile exe`,
runs every shape x size, merges the records into benchmark/results.jsonl,
and rewrites benchmark/RESULTS.md.

  --impls <a,b>        Implementations (default v1,v2; missing ones are skipped).
  --shapes <a,b>       Shapes (default deep,wide).
  --sizes <a,b>        Sizes (default 10k,100k,1m).
  --runs <n>           Timed runs per operation (default 5).
  --warmup <n>         Warm-up runs per operation (default 1).
  --budget-ms <ms>     Longest a single step may take (default 60000).
  --no-compile         Reuse existing build/bench executables.
  --fresh              Drop previously stored records instead of merging.
  --report-only        Only rewrite RESULTS.md from results.jsonl.
  --benchmark-dir <d>  The benchmark/ directory (default: found from cwd).
  -h, --help           Show this help.''';

Future<void> main(List<String> args) async {
  final _Options options;
  try {
    options = _Options.parse(args);
  } on FormatException catch (e) {
    stderr
      ..writeln('error: ${e.message}')
      ..writeln(_usage);
    exitCode = 64;
    return;
  }
  if (options.help) {
    stdout.writeln(_usage);
    return;
  }

  final benchDir = options.benchmarkDir ?? _findBenchmarkDir();
  if (benchDir == null) {
    stderr.writeln('error: cannot find benchmark/; pass --benchmark-dir');
    exitCode = 64;
    return;
  }
  final resultsFile = File('${benchDir.path}/results.jsonl');
  final markdownFile = File('${benchDir.path}/RESULTS.md');
  final dart = _dartExecutable();

  final existing = options.fresh || !resultsFile.existsSync()
      ? <BenchRecord>[]
      : [
          for (final line in resultsFile.readAsLinesSync())
            if (line.trim().isNotEmpty)
              (jsonDecode(line) as Map).cast<String, Object?>(),
        ];

  final fresh = <BenchRecord>[];
  var failed = false;
  if (!options.reportOnly) {
    final env = await BenchEnvironment.detect(dart);
    _log('Machine: ${env.machine}');
    _log('OS: ${env.os}');
    _log('Dart: ${env.dart}');

    final executables = <String, String>{};
    for (final impl in options.impls) {
      final dir = Directory('${benchDir.path}/$impl');
      if (!File('${dir.path}/pubspec.yaml').existsSync() ||
          !File('${dir.path}/bin/bench.dart').existsSync()) {
        _log('Skipping $impl: ${dir.path}/bin/bench.dart does not exist.');
        continue;
      }
      final exe = await _compile(dart, dir, compile: options.compile);
      if (exe == null) {
        failed = true;
      } else {
        executables[impl] = exe;
      }
    }

    for (final shape in options.shapes) {
      for (final size in options.sizes) {
        for (final entry in executables.entries) {
          final records = await _runOne(
            entry.value,
            implementation: entry.key,
            shape: shape,
            size: size,
            options: options,
          );
          for (final r in records) {
            if (r.containsKey('error')) failed = true;
            fresh.add({...r, ...env.toJson()});
          }
          // Persist after every process so an interrupted session keeps
          // what it measured.
          _write(resultsFile, mergeRecords(existing, fresh));
        }
      }
    }
  }

  final merged = mergeRecords(existing, fresh);
  _write(resultsFile, merged);
  final workloads = <Workload>[];
  final seen = <String>{};
  for (final r in merged) {
    if (!seen.add('${r['shape']}|${r['size']}|${r['seed']}')) continue;
    workloads.add(
      Workload.generate(
        WorkloadShape.parse(r['shape']! as String),
        r['size']! as int,
        seed: r['seed'] as int? ?? Workload.defaultSeed,
      ),
    );
  }
  markdownFile.writeAsStringSync(
    renderMarkdown(merged, workloads: workloads, generatedAt: DateTime.now()),
  );
  _log('Wrote ${markdownFile.path} (${merged.length} records).');
  if (failed) exitCode = 1;
}

void _log(String message) => stderr.writeln(message);

void _write(File file, List<BenchRecord> records) {
  file.writeAsStringSync(records.map((r) => '${jsonEncode(r)}\n').join());
}

String _dartExecutable() {
  final self = Platform.resolvedExecutable;
  final name = self.split(Platform.pathSeparator).last;
  return name == 'dart' || name == 'dart.exe' ? self : 'dart';
}

Directory? _findBenchmarkDir() {
  bool isBench(Directory d) =>
      File('${d.path}/workloads/pubspec.yaml').existsSync() &&
      File('${d.path}/harness/pubspec.yaml').existsSync();
  var dir = Directory.current.absolute;
  while (true) {
    for (final candidate in [dir, Directory('${dir.path}/benchmark')]) {
      if (isBench(candidate)) return candidate;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

Future<String?> _compile(
  String dart,
  Directory dir, {
  required bool compile,
}) async {
  final name = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
  final exe = '${dir.path}/build/bench${Platform.isWindows ? '.exe' : ''}';
  if (!compile) {
    if (File(exe).existsSync()) return exe;
    _log('error: $exe is missing; run without --no-compile.');
    return null;
  }
  Directory('${dir.path}/build').createSync(recursive: true);
  for (final step in [
    ['pub', 'get'],
    ['compile', 'exe', 'bin/bench.dart', '-o', exe],
  ]) {
    _log('[$name] dart ${step.join(' ')}');
    final r = await Process.run(dart, step, workingDirectory: dir.path);
    if (r.exitCode != 0) {
      _log(
        'error: [$name] dart ${step.join(' ')} failed:\n${r.stdout}${r.stderr}',
      );
      return null;
    }
  }
  return exe;
}

Future<List<BenchRecord>> _runOne(
  String exe, {
  required String implementation,
  required String shape,
  required int size,
  required _Options options,
}) async {
  _log('== $implementation $shape $size');
  final process = await Process.start(exe, [
    '--shape',
    shape,
    '--size',
    '$size',
    '--runs',
    '${options.runs}',
    '--warmup',
    '${options.warmup}',
    '--budget-ms',
    '${options.budgetMs}',
  ]);
  final records = <BenchRecord>[];
  final out = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) {
        if (!line.startsWith('{')) {
          _log('  $line');
          return;
        }
        final r = (jsonDecode(line) as Map).cast<String, Object?>();
        records.add(r);
        _log('  ${_summary(r)}');
      });
  final err = process.stderr
      .transform(utf8.decoder)
      .forEach((chunk) => stderr.write(chunk));

  // The executable enforces the per-step budget itself; this outer limit
  // only guards against a broken executable.
  final steps =
      standardOperations.length * (options.warmup + options.runs + 1) + 1;
  final limit = Duration(milliseconds: options.budgetMs * steps + 60000);
  final code = await process.exitCode.timeout(
    limit,
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
  await Future.wait([out, err]);

  final reported = {for (final r in records) r['operation']};
  for (final op in standardOperations) {
    if (reported.contains(op)) continue;
    final r = <String, Object?>{
      'implementation': implementation,
      'shape': shape,
      'size': size,
      'operation': op,
      'runs': options.runs,
      'warmup': options.warmup,
      'budget_ms': options.budgetMs,
      'error': code == -1
          ? 'process exceeded ${limit.inSeconds} s and was killed'
          : 'no record (exit code $code)',
    };
    records.add(r);
    _log('  ${_summary(r)}');
  }
  return records;
}

String _summary(BenchRecord r) {
  final head = '${r['operation']}:';
  if (r['median_ms'] is num) {
    return '$head median ${formatMs(r['median_ms']! as num)} ms, '
        'min ${formatMs(r['min_ms']! as num)} ms';
  }
  return '$head ${medianCell(r)}${r['error'] != null ? ': ${r['error']}' : ''}';
}

class _Options {
  _Options({
    required this.help,
    required this.impls,
    required this.shapes,
    required this.sizes,
    required this.runs,
    required this.warmup,
    required this.budgetMs,
    required this.compile,
    required this.fresh,
    required this.reportOnly,
    required this.benchmarkDir,
  });

  factory _Options.parse(List<String> args) {
    final values = <String, String>{};
    final flags = <String>{};
    const flagNames = {'no-compile', 'fresh', 'report-only'};
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '-h' || arg == '--help') {
        flags.add('help');
        continue;
      }
      if (!arg.startsWith('--')) throw FormatException('Unexpected "$arg"');
      final name = arg.substring(2);
      if (flagNames.contains(name)) {
        flags.add(name);
        continue;
      }
      final eq = name.indexOf('=');
      if (eq != -1) {
        values[name.substring(0, eq)] = name.substring(eq + 1);
      } else if (i + 1 < args.length) {
        values[name] = args[++i];
      } else {
        throw FormatException('Missing value: $arg');
      }
    }
    List<String> list(String name, List<String> fallback) =>
        values.remove(name)?.split(',').map((s) => s.trim()).toList() ??
        fallback;
    int number(String name, int fallback, {int min = 0}) {
      final raw = values.remove(name);
      final value = raw == null ? fallback : parseCount(raw);
      if (value < min) throw FormatException('--$name must be >= $min');
      return value;
    }

    final shapes = list('shapes', [
      for (final s in WorkloadShape.values) s.name,
    ]);
    shapes.forEach(WorkloadShape.parse);
    final sizes = list('sizes', [
      for (final s in standardSizes) '$s',
    ]).map(parseCount).toList();
    final benchDir = values.remove('benchmark-dir');
    final options = _Options(
      help: flags.contains('help'),
      impls: list('impls', knownImplementations),
      shapes: shapes,
      sizes: sizes,
      runs: number('runs', 5, min: 1),
      warmup: number('warmup', 1),
      budgetMs: number('budget-ms', 60000, min: 1),
      compile: !flags.contains('no-compile'),
      fresh: flags.contains('fresh'),
      reportOnly: flags.contains('report-only'),
      benchmarkDir: benchDir == null ? null : Directory(benchDir).absolute,
    );
    if (values.isNotEmpty) {
      throw FormatException('Unknown option --${values.keys.first}');
    }
    return options;
  }

  final bool help;
  final List<String> impls;
  final List<String> shapes;
  final List<int> sizes;
  final int runs;
  final int warmup;
  final int budgetMs;
  final bool compile;
  final bool fresh;
  final bool reportOnly;
  final Directory? benchmarkDir;
}
