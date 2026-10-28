import 'package:directory_tree_bench_harness/harness.dart';
import 'package:directory_tree_bench_v2/v2_subject.dart';

/// Benchmarks directory_tree 2.0.0. Run with `--help` for options.
Future<void> main(List<String> args) =>
    runBenchmarkCli(args, implementation: 'v2', createSubject: createV2Subject);
