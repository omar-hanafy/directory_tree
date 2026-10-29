import 'package:directory_tree_bench_workloads/workloads.dart';

/// Prints a summary of every standard workload (shape x size).
///
/// Usage: `dart run bin/stats.dart [size ...]`
void main(List<String> args) {
  final sizes = args.isEmpty ? standardSizes : args.map(int.parse).toList();
  for (final shape in WorkloadShape.values) {
    for (final size in sizes) {
      final sw = Stopwatch()..start();
      final w = Workload.generate(shape, size);
      final entries = <String, int>{};
      final fileDepths = <int, int>{};
      for (final path in w.paths) {
        final cut = path.lastIndexOf('/');
        final dir = path.substring(0, cut);
        entries[dir] = (entries[dir] ?? 0) + 1;
        final depth = '/'.allMatches(path).length - 1;
        fileDepths[depth] = (fileDepths[depth] ?? 0) + 1;
      }
      final perDir = entries.values.toList()..sort();
      print({
        ...w.describe(),
        'generate_ms': sw.elapsedMilliseconds,
        'dirs_with_files': perDir.length,
        'files_per_dir_p10_p50_p90_max': [
          perDir[perDir.length ~/ 10],
          perDir[perDir.length ~/ 2],
          perDir[perDir.length * 9 ~/ 10],
          perDir.last,
        ],
        'file_depths': (fileDepths.keys.toList()..sort())
            .map((d) => '$d:${fileDepths[d]}')
            .join(' '),
      });
    }
  }
}
