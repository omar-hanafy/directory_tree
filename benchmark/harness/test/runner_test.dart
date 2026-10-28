import 'package:directory_tree_bench_harness/harness.dart';
import 'package:test/test.dart';

/// Runs forever; [Isolate.kill] must still stop it.
int _spin() {
  var i = 0;
  while (true) {
    i = (i + 1) & 0xFFFF;
    if (i == -1) return i;
  }
}

class _FakeSubject extends BenchSubject {
  _FakeSubject(this.workload, {this.hangIn, this.throwInSetUp});

  final Workload workload;
  final String? hangIn;
  final String? throwInSetUp;

  @override
  void setUp(String operation) {
    if (operation == throwInSetUp) throw StateError('set-up broke');
  }

  @override
  Map<String, Object> run(String operation) {
    if (operation == hangIn) _spin();
    return {'files': workload.paths.length};
  }
}

/// Spends 40 ms in [beforeRun], which must stay out of the timings.
class _ResettingSubject extends BenchSubject {
  int resets = 0;
  bool dirty = false;

  @override
  void setUp(String operation) {}

  @override
  void beforeRun(String operation) {
    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < 40) {}
    resets++;
    dirty = false;
  }

  @override
  Map<String, Object> run(String operation) {
    if (dirty) throw StateError('beforeRun did not reset');
    dirty = true;
    return {'resets': resets};
  }
}

BenchSubject _fast(Workload w) => _FakeSubject(w);
BenchSubject _resetting(Workload w) => _ResettingSubject();
BenchSubject _hangInFlatten(Workload w) => _FakeSubject(w, hangIn: 'flatten');
BenchSubject _throwInToggle(Workload w) =>
    _FakeSubject(w, throwInSetUp: 'toggle');
BenchSubject _hangInFactory(Workload w) {
  _spin();
  return _FakeSubject(w);
}

const _config = BenchConfig(
  implementation: 'fake',
  shape: WorkloadShape.deep,
  size: 200,
  runs: 3,
  budget: Duration(milliseconds: 500),
);

Map<String, Map<String, Object?>> _byOperation(
  List<Map<String, Object?>> records,
) => {for (final r in records) r['operation']! as String: r};

void main() {
  test('reports median and min per operation when nothing fails', () async {
    final streamed = <Map<String, Object?>>[];
    final records = await runBenchmark(_config, _fast, onRecord: streamed.add);
    expect(streamed, records);
    expect(records.map((r) => r['operation']), standardOperations);
    for (final r in records) {
      expect(r['implementation'], 'fake');
      expect(r['shape'], 'deep');
      expect(r['size'], 200);
      expect(r['runs'], 3);
      expect(r['median_ms'], isA<double>());
      expect(
        r['min_ms'] as double,
        lessThanOrEqualTo(r['median_ms'] as double),
      );
      expect(r['files'], 200);
      expect(
        r['fingerprint'],
        Workload.generate(WorkloadShape.deep, 200).fingerprint,
      );
      expect(r, isNot(contains('timeout_ms')));
    }
  });

  test('calls beforeRun before every run without timing it', () async {
    final records = await runBenchmark(
      const BenchConfig(
        implementation: 'fake',
        shape: WorkloadShape.deep,
        size: 200,
        runs: 3,
        warmup: 2,
        operations: ['build', 'flatten'],
      ),
      _resetting,
    );
    expect(records[0]['resets'], 5);
    // The counter keeps going across operations in one child.
    expect(records[1]['resets'], 10);
    for (final r in records) {
      expect(r['median_ms'] as double, lessThan(20));
    }
  });

  test('kills a run that exceeds the budget and continues', () async {
    final sw = Stopwatch()..start();
    final records = _byOperation(await runBenchmark(_config, _hangInFlatten));
    expect(sw.elapsed, lessThan(const Duration(seconds: 20)));

    expect(records.keys, unorderedEquals(standardOperations));
    expect(records['build'], contains('median_ms'));
    expect(records['flatten'], {
      ...records['flatten']!,
      'timeout_ms': 500,
      'timeout_phase': 'warmup',
      'completed_runs': 0,
    });
    expect(records['flatten'], isNot(contains('median_ms')));
    // toggle and filter only need build, so a fresh child runs them.
    expect(records['toggle'], contains('median_ms'));
    expect(records['filter'], contains('median_ms'));
    // diff needs flatten, which already exceeded the budget.
    expect(records['diff']!['timeout_phase'], 'blocked');
    expect(records['diff']!['blocked_by'], 'flatten');
    expect(records['diff']!['timeout_ms'], 500);
  });

  test('reports errors and blocks dependent operations', () async {
    final records = _byOperation(await runBenchmark(_config, _throwInToggle));
    expect(records['toggle']!['error'], contains('set-up broke'));
    expect(records['filter'], contains('median_ms'));
    expect(records['diff']!['error'], contains('blocked'));
    expect(records['diff']!['blocked_by'], 'toggle');
    expect(records['diff'], isNot(contains('timeout_ms')));
  });

  test('times out every operation when the workload set-up hangs', () async {
    final records = await runBenchmark(_config, _hangInFactory);
    expect(records.map((r) => r['operation']), standardOperations);
    for (final r in records) {
      expect(r['timeout_ms'], 500);
      expect(r['timeout_phase'], 'workload');
    }
  });

  group('parseBenchArgs', () {
    test('reads values and defaults', () {
      final c = parseBenchArgs([
        '--shape',
        'wide',
        '--size=100k',
        '--budget-ms',
        '1500',
        '--operations',
        'build,diff',
      ], implementation: 'v1')!;
      expect(c.shape, WorkloadShape.wide);
      expect(c.size, 100000);
      expect(c.budget, const Duration(milliseconds: 1500));
      expect(c.runs, 5);
      expect(c.warmup, 1);
      expect(c.operations, ['build', 'diff']);
    });

    test('returns null for help and rejects bad input', () {
      expect(parseBenchArgs(['-h'], implementation: 'v1'), isNull);
      for (final bad in [
        <String>['--size', '10'],
        ['--shape', 'deep'],
        ['--shape', 'tall', '--size', '10'],
        ['--shape', 'deep', '--size', '1x'],
        ['--shape', 'deep', '--size', '10', '--runs', '0'],
        ['--shape', 'deep', '--size', '10', '--operations', 'sort'],
        ['--shape', 'deep', '--size', '10', '--nope', '1'],
      ]) {
        expect(
          () => parseBenchArgs(bad, implementation: 'v1'),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });

    test('parseCount accepts k and m suffixes', () {
      expect(parseCount('10000'), 10000);
      expect(parseCount('10K'), 10000);
      expect(parseCount('1m'), 1000000);
    });
  });
}
