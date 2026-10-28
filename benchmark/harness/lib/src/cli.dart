import 'dart:convert';
import 'dart:io';

import 'package:directory_tree_bench_workloads/workloads.dart';

import 'runner.dart';
import 'subject.dart';

const _usage =
    '''
Usage: bench --shape <deep|wide> --size <n> [options]

Runs every benchmark operation for one workload and prints one JSON object
per operation to stdout.

  --shape <deep|wide>     Workload shape (required).
  --size <n>              File count, for example 10000, 100k, or 1m (required).
  --runs <n>              Timed runs per operation (default 5).
  --warmup <n>            Untimed warm-up runs per operation (default 1).
  --budget-ms <ms>        Longest a single step may take (default 60000).
  --seed <n>              Workload seed (default ${Workload.defaultSeed}).
  --operations <a,b,...>  Subset of: ${'build,flatten,toggle,filter,diff'}.
  -h, --help              Show this help.''';

/// Parses [args], runs the benchmark for [implementation] with subjects from
/// [createSubject], prints JSON lines to stdout, and exits the process.
///
/// Exit codes: 0 when every operation produced numbers or timed out, 1 when
/// an operation failed with an error, 64 on a usage error.
Future<Never> runBenchmarkCli(
  List<String> args, {
  required String implementation,
  required SubjectFactory createSubject,
}) async {
  final BenchConfig config;
  try {
    final parsed = parseBenchArgs(args, implementation: implementation);
    if (parsed == null) {
      stdout.writeln(_usage);
      await stdout.flush();
      exit(0);
    }
    config = parsed;
  } on FormatException catch (e) {
    stderr
      ..writeln('error: ${e.message}')
      ..writeln(_usage);
    await stderr.flush();
    exit(64);
  }

  final records = await runBenchmark(
    config,
    createSubject,
    onRecord: (record) => stdout.writeln(jsonEncode(record)),
  );
  await stdout.flush();
  exit(records.any((r) => r.containsKey('error')) ? 1 : 0);
}

/// Parses benchmark CLI arguments. Returns null when help was requested.
///
/// Throws a [FormatException] for invalid arguments.
BenchConfig? parseBenchArgs(
  List<String> args, {
  required String implementation,
}) {
  final values = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '-h' || arg == '--help') return null;
    if (!arg.startsWith('--')) throw FormatException('Unexpected "$arg"');
    final eq = arg.indexOf('=');
    if (eq != -1) {
      values[arg.substring(2, eq)] = arg.substring(eq + 1);
    } else {
      if (i + 1 >= args.length) throw FormatException('Missing value: $arg');
      values[arg.substring(2)] = args[++i];
    }
  }

  String take(String name) =>
      values.remove(name) ?? (throw FormatException('Missing --$name'));
  int intOf(String name, int fallback, {int min = 0}) {
    final raw = values.remove(name);
    if (raw == null) return fallback;
    final value = parseCount(raw);
    if (value < min) throw FormatException('--$name must be >= $min');
    return value;
  }

  final shape = WorkloadShape.parse(take('shape'));
  final size = parseCount(take('size'));
  final operationsRaw = values.remove('operations');
  final operations = operationsRaw == null
      ? standardOperations
      : operationsRaw.split(',').map((s) => s.trim()).toList();
  for (final op in operations) {
    if (!standardOperations.contains(op)) {
      throw FormatException('Unknown operation "$op"');
    }
  }
  final config = BenchConfig(
    implementation: implementation,
    shape: shape,
    size: size,
    runs: intOf('runs', 5, min: 1),
    warmup: intOf('warmup', 1),
    budget: Duration(milliseconds: intOf('budget-ms', 60000, min: 1)),
    seed: intOf('seed', Workload.defaultSeed),
    operations: operations,
  );
  if (values.isNotEmpty) {
    throw FormatException('Unknown option --${values.keys.first}');
  }
  return config;
}

/// Parses `10000`, `100k`, or `1m` (case-insensitive).
int parseCount(String raw) {
  final s = raw.trim().toLowerCase();
  final multiplier = s.endsWith('k')
      ? 1000
      : s.endsWith('m')
      ? 1000000
      : 1;
  final digits = multiplier == 1 ? s : s.substring(0, s.length - 1);
  final value = int.tryParse(digits);
  if (value == null) throw FormatException('Not a number: "$raw"');
  return value * multiplier;
}
