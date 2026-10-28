import 'package:directory_tree_bench_workloads/workloads.dart';
import 'package:test/test.dart';

Map<String, int> _filesPerDir(List<String> paths) {
  final counts = <String, int>{};
  for (final path in paths) {
    final dir = path.substring(0, path.lastIndexOf('/'));
    counts[dir] = (counts[dir] ?? 0) + 1;
  }
  return counts;
}

int _depth(String path) => '/'.allMatches(path).length - 1;

void main() {
  group('SeededRandom', () {
    test('produces a fixed sequence for a seed', () {
      final rng = SeededRandom(42);
      expect(
        [for (var i = 0; i < 4; i++) rng.nextUint32()],
        [2581720956, 1925393290, 3661312704, 2876485805],
      );
    });

    test('range stays inside its bounds', () {
      final rng = SeededRandom(7);
      for (var i = 0; i < 10000; i++) {
        expect(rng.range(5, 30), inInclusiveRange(5, 30));
      }
    });
  });

  group('Workload', () {
    // Pinned so a change to the generators (which would invalidate every
    // stored result) is a deliberate, visible decision.
    test('fingerprints are pinned', () {
      expect(
        Workload.generate(WorkloadShape.deep, 10000).fingerprint,
        '131893f6',
      );
      expect(
        Workload.generate(WorkloadShape.wide, 10000).fingerprint,
        'f0e2e2b1',
      );
    });

    for (final shape in WorkloadShape.values) {
      for (final size in [10000, 100000]) {
        group('${shape.name} $size', () {
          final w = Workload.generate(shape, size);

          test('is deterministic for a seed and differs across seeds', () {
            final again = Workload.generate(shape, size);
            expect(again.paths, w.paths);
            expect(again.toggleTarget, w.toggleTarget);
            final other = Workload.generate(shape, size, seed: 1);
            expect(other.fingerprint, isNot(w.fingerprint));
          });

          test('has exactly size unique absolute POSIX paths', () {
            expect(w.paths, hasLength(size));
            expect(
              w.paths.map((p) => p.toLowerCase()).toSet(),
              hasLength(size),
            );
            for (final path in w.paths) {
              expect(path, startsWith('$workloadRoot/'));
              expect(path, isNot(contains('//')));
              expect(path, isNot(contains(r'\')));
            }
          });

          test('keeps files directly under the root', () {
            // Keeps every implementation's anchor at /repo.
            expect(w.paths.where((p) => _depth(p) == 1), isNotEmpty);
          });

          test('matches the shape', () {
            final perDir = _filesPerDir(w.paths);
            final depths = w.paths.map(_depth).toList();
            final maxDepth = depths.reduce((a, b) => a > b ? a : b);
            expect(w.maxFileDepth, maxDepth);
            if (shape == WorkloadShape.deep) {
              expect(maxDepth, inInclusiveRange(8, 14));
              final median = (perDir.values.toList()
                ..sort())[perDir.length ~/ 2];
              expect(median, inInclusiveRange(3, 30));
              expect(perDir.values.where((c) => c > 120), isEmpty);
            } else {
              expect(maxDepth, inInclusiveRange(2, 3));
              final big = perDir.entries.where((e) => e.key != workloadRoot);
              expect(big.every((e) => e.value >= 1000), isTrue);
            }
          });

          test('filter query matches 1-5% of files, only by file name', () {
            final matches = w.paths
                .where((p) => p.split('/').last.contains(w.filterQuery))
                .length;
            expect(matches, w.filterMatchCount);
            expect(matches / size, inInclusiveRange(0.01, 0.05));
            for (final path in w.paths) {
              final dir = path.substring(0, path.lastIndexOf('/'));
              expect(dir, isNot(contains(w.filterQuery)));
            }
          });

          test('toggle target is a directory holding a large subtree', () {
            final prefix = '${w.toggleTarget}/';
            final inside = w.paths.where((p) => p.startsWith(prefix)).length;
            expect(inside, w.toggleTargetFileCount);
            expect(w.toggleTarget, isNot(workloadRoot));
            expect(inside / size, inInclusiveRange(0.05, 0.25));
          });
        });
      }
    }

    test('rejects tiny sizes and unknown shapes', () {
      expect(
        () => Workload.generate(WorkloadShape.deep, 10),
        throwsArgumentError,
      );
      expect(() => WorkloadShape.parse('tall'), throwsFormatException);
      expect(WorkloadShape.parse('wide'), WorkloadShape.wide);
    });
  });
}
