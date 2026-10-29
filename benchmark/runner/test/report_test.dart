import 'package:directory_tree_bench_runner/runner.dart';
import 'package:directory_tree_bench_workloads/workloads.dart';
import 'package:test/test.dart';

BenchRecord _record(
  String impl,
  String op, {
  String shape = 'deep',
  int size = 10000,
  Map<String, Object?> fields = const {},
}) => {
  'implementation': impl,
  'shape': shape,
  'size': size,
  'operation': op,
  'runs': 5,
  'warmup': 1,
  'budget_ms': 60000,
  'seed': Workload.defaultSeed,
  'fingerprint': 'abc',
  'machine': 'Test CPU (arm64)',
  'os': 'testOS 1',
  'dart': 'Dart SDK version: 3.x',
  ...fields,
};

void main() {
  test('mergeRecords replaces by key and sorts', () {
    final merged = mergeRecords(
      [
        _record('v1', 'flatten', fields: {'median_ms': 9.0}),
        _record('v1', 'build', size: 100000, fields: {'median_ms': 1.0}),
      ],
      [
        _record('v2', 'build', fields: {'median_ms': 2.0}),
        _record('v1', 'flatten', fields: {'median_ms': 3.0}),
        _record('v1', 'build', shape: 'wide', fields: {'median_ms': 4.0}),
      ],
    );
    expect(
      merged.map(
        (r) =>
            '${r['shape']} ${r['size']} ${r['operation']} '
            '${r['implementation']} ${r['median_ms']}',
      ),
      [
        'deep 10000 build v2 2.0',
        'deep 10000 flatten v1 3.0',
        'deep 100000 build v1 1.0',
        'wide 10000 build v1 4.0',
      ],
    );
  });

  test('cells format numbers, timeouts, blocked operations, and speedups', () {
    final fast = _record('v2', 'build', fields: {'median_ms': 2.5});
    final slow = _record('v1', 'build', fields: {'median_ms': 1250.0});
    final timeout = _record(
      'v1',
      'build',
      fields: {'timeout_ms': 60000, 'timeout_phase': 'run'},
    );
    final blocked = _record(
      'v1',
      'flatten',
      fields: {'timeout_ms': 60000, 'blocked_by': 'build'},
    );
    expect(medianCell(slow), '1,250');
    expect(medianCell(fast), '2.50');
    expect(
      medianCell(_record('v1', 'x', fields: {'median_ms': 0.1234})),
      '0.123',
    );
    expect(medianCell(timeout), '> 60,000 (timeout)');
    expect(medianCell(blocked), 'timeout (blocked by build)');
    expect(medianCell(_record('v1', 'x', fields: {'error': 'boom'})), 'error');
    expect(medianCell(null), '');
    expect(speedupCell(slow, fast), '500x');
    expect(speedupCell(fast, slow), '0.00x');
    expect(speedupCell(timeout, fast), '> 24,000x');
    // Blocked operations never ran, so they have no speedup.
    expect(speedupCell(blocked, fast), '');
    expect(
      speedupCell(
        _record('v1', 'build', fields: {'median_ms': 9.0, 'min_ms': 4.0}),
        _record('v2', 'build', fields: {'median_ms': 3.0, 'min_ms': 2.0}),
        field: 'min_ms',
      ),
      '2.00x',
    );
    expect(minCell(_record('v1', 'x', fields: {'min_ms': 1250})), '1,250');
    expect(minCell(blocked), 'timeout (blocked by build)');
    expect(speedupCell(slow, null), '');
    expect(speedupCell(slow, timeout), '');
  });

  test('renderMarkdown leaves v2 columns empty without v2 records', () {
    final md = renderMarkdown(
      [
        _record(
          'v1',
          'build',
          fields: {
            'median_ms': 12.0,
            'min_ms': 11.0,
            'max_ms': 13.0,
            'nodes': 7,
          },
        ),
        _record(
          'v1',
          'flatten',
          fields: {'timeout_ms': 60000, 'timeout_phase': 'warmup'},
        ),
      ],
      workloads: [Workload.generate(WorkloadShape.deep, 10000)],
      generatedAt: DateTime.utc(2026, 10, 28),
    );
    expect(md, contains('- Test CPU (arm64); testOS 1; Dart SDK version: 3.x'));
    expect(
      md,
      contains(
        '| operation | shape | size | v1 median (ms) | v2 median (ms) '
        '| speedup |',
      ),
    );
    expect(md, contains('| build | deep | 10,000 | 12.00 |  |  |'));
    expect(
      md,
      contains('| flatten | deep | 10,000 | > 60,000 (timeout) |  |  |'),
    );
    expect(
      md,
      contains(
        '| v1 | build | deep | 10,000 | 12.00 | 11.00 | 13.00 | nodes 7 |',
      ),
    );
    expect(md, contains('timeout in warmup'));
    expect(md, contains('### Fastest run'));
    expect(md, contains('| build | deep | 10,000 | 11.00 |  |  |'));
    expect(md, contains('`/repo/'));
    expect(md, isNot(contains(String.fromCharCode(0x2014))));
  });

  test('renderMarkdown warns about mismatched workloads', () {
    final md = renderMarkdown(
      [
        _record('v1', 'build', fields: {'median_ms': 1.0}),
        _record('v2', 'build', fields: {'median_ms': 1.0, 'fingerprint': 'x'}),
      ],
      workloads: const [],
      generatedAt: DateTime.utc(2026),
    );
    expect(md, contains('fingerprints differ'));
  });
}
