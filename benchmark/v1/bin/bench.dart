import 'package:directory_tree_bench_harness/harness.dart';
import 'package:directory_tree_bench_v1/v1_subject.dart';

/// Benchmarks directory_tree 1.0.0. Run with `--help` for options.
Future<void> main(List<String> args) =>
    runBenchmarkCli(args, implementation: 'v1', createSubject: createV1Subject);
