import 'dart:async';
import 'dart:isolate';

import 'package:directory_tree_bench_workloads/workloads.dart';

import 'subject.dart';

/// Settings for one benchmark invocation (one implementation, shape, size).
class BenchConfig {
  /// Creates a configuration.
  const BenchConfig({
    required this.implementation,
    required this.shape,
    required this.size,
    this.seed = Workload.defaultSeed,
    this.runs = 5,
    this.warmup = 1,
    this.budget = const Duration(seconds: 60),
    this.operations = standardOperations,
    this.prerequisites = standardPrerequisites,
  });

  /// The implementation label, such as `v1` or `v2`.
  final String implementation;

  /// The workload shape.
  final WorkloadShape shape;

  /// The workload size (file count).
  final int size;

  /// The workload seed.
  final int seed;

  /// Timed runs per operation.
  final int runs;

  /// Untimed warm-up runs per operation.
  final int warmup;

  /// The longest any single step may take: workload generation, an
  /// operation's set-up, or one warm-up or timed run. A step that exceeds it
  /// is abandoned by killing the child isolate.
  final Duration budget;

  /// The operations to run, in order.
  final List<String> operations;

  /// See [standardPrerequisites].
  final Map<String, List<String>> prerequisites;
}

/// Runs every operation of [config] and returns one record per operation.
///
/// Operations run in a child isolate, one after another. Every step must
/// finish within [BenchConfig.budget]; otherwise the child is killed, the
/// operation is reported with `timeout_ms`, and a new child continues with
/// the remaining operations. [onRecord] receives each record as soon as it
/// is known.
Future<List<Map<String, Object?>>> runBenchmark(
  BenchConfig config,
  SubjectFactory createSubject, {
  void Function(Map<String, Object?> record)? onRecord,
}) async {
  final records = <Map<String, Object?>>[];
  final failures = <String, _Failure>{};
  final pending = [...config.operations];
  String? fingerprint;

  Map<String, Object?> base(String operation) => {
    'implementation': config.implementation,
    'shape': config.shape.name,
    'size': config.size,
    'operation': operation,
    'runs': config.runs,
    'warmup': config.warmup,
    'budget_ms': config.budget.inMilliseconds,
    'seed': config.seed,
    'fingerprint': ?fingerprint,
  };

  void emit(String operation, Map<String, Object?> fields) {
    final record = {...base(operation), ...fields};
    records.add(record);
    pending.remove(operation);
    onRecord?.call(record);
  }

  void fail(String operation, _Failure failure, Map<String, Object?> fields) {
    failures[operation] = failure;
    emit(operation, fields);
  }

  while (pending.isNotEmpty) {
    // Report operations whose prerequisites already failed.
    for (final operation in [...pending]) {
      final blocker = (config.prerequisites[operation] ?? const <String>[])
          .where(failures.containsKey)
          .firstOrNull;
      if (blocker == null) continue;
      final failure = failures[blocker]!;
      fail(operation, failure, {
        if (failure == _Failure.timeout) ...{
          'timeout_ms': config.budget.inMilliseconds,
          'timeout_phase': 'blocked',
        } else
          'error': 'blocked: prerequisite failed',
        'blocked_by': blocker,
      });
    }
    if (pending.isEmpty) break;

    final child = _Child(config, createSubject, [...pending]);
    await for (final event in child.events()) {
      switch (event) {
        case _WorkloadReady(:final description):
          fingerprint = description['fingerprint'] as String?;
        case _Result(:final operation, :final timesMs, :final counts):
          final sorted = [...timesMs]..sort();
          emit(operation, {
            'median_ms': _round(_median(sorted)),
            'min_ms': _round(sorted.first),
            'max_ms': _round(sorted.last),
            ...counts,
          });
        case _Failed(:final operation, :final error):
          final targets = operation == null ? [...pending] : [operation];
          for (final target in targets) {
            fail(target, _Failure.error, {'error': error});
          }
        case _TimedOut(:final operation, :final phase, :final completedRuns):
          final targets = operation == null ? [...pending] : [operation];
          for (final target in targets) {
            fail(target, _Failure.timeout, {
              'timeout_ms': config.budget.inMilliseconds,
              'timeout_phase': phase,
              'completed_runs': completedRuns,
            });
          }
      }
    }
  }
  return records;
}

enum _Failure { timeout, error }

double _median(List<double> sorted) {
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

double _round(double ms) => (ms * 1000).round() / 1000;

// --- coordinator side of one child isolate ------------------------------------

sealed class _Event {}

class _WorkloadReady extends _Event {
  _WorkloadReady(this.description);
  final Map<String, Object?> description;
}

class _Result extends _Event {
  _Result(this.operation, this.timesMs, this.counts);
  final String operation;
  final List<double> timesMs;
  final Map<String, Object?> counts;
}

class _Failed extends _Event {
  _Failed(this.operation, this.error);
  final String? operation;
  final String error;
}

class _TimedOut extends _Event {
  _TimedOut(this.operation, this.phase, this.completedRuns);
  final String? operation;
  final String phase;
  final int completedRuns;
}

class _Child {
  _Child(this.config, this.createSubject, this.operations);

  final BenchConfig config;
  final SubjectFactory createSubject;
  final List<String> operations;

  /// Runs the child and yields its events. The stream always ends: on
  /// completion, on failure, on unexpected exit, or when a step exceeds the
  /// budget.
  Stream<_Event> events() {
    final controller = StreamController<_Event>();
    final messages = ReceivePort();
    final exits = ReceivePort();
    final errors = ReceivePort();
    Isolate? isolate;
    Timer? timer;
    String? operation;
    var phase = 'workload';
    var completedRuns = 0;
    var finished = false;

    void finish() {
      if (finished) return;
      finished = true;
      timer?.cancel();
      messages.close();
      exits.close();
      errors.close();
      isolate?.kill(priority: Isolate.immediate);
      controller.close();
    }

    void arm() {
      timer?.cancel();
      timer = Timer(config.budget, () {
        if (finished) return;
        controller.add(_TimedOut(operation, phase, completedRuns));
        finish();
      });
    }

    messages.listen((message) {
      if (finished) return;
      final m = message as Map<String, Object?>;
      switch (m['event']) {
        case 'workload':
          controller.add(
            _WorkloadReady(m['description']! as Map<String, Object?>),
          );
        case 'phase':
          operation = m['operation'] as String?;
          phase = m['phase']! as String;
          completedRuns = m['completed_runs'] as int? ?? 0;
          arm();
        case 'result':
          controller.add(
            _Result(
              m['operation']! as String,
              (m['times_ms']! as List).cast<double>(),
              m['counts']! as Map<String, Object?>,
            ),
          );
        case 'error':
          controller.add(_Failed(operation, m['error']! as String));
          finish();
        case 'done':
          finish();
      }
    });
    errors.listen((error) {
      if (finished) return;
      final pair = error as List<Object?>;
      controller.add(_Failed(operation, 'uncaught: ${pair.first}'));
      finish();
    });
    exits.listen((_) {
      if (finished) return;
      controller.add(_Failed(operation, 'child isolate exited unexpectedly'));
      finish();
    });

    () async {
      try {
        isolate = await Isolate.spawn(
          _childMain,
          _ChildArgs(
            messages.sendPort,
            config.shape,
            config.size,
            config.seed,
            config.runs,
            config.warmup,
            operations,
            createSubject,
          ),
          paused: true,
          errorsAreFatal: true,
          onExit: exits.sendPort,
          onError: errors.sendPort,
          debugName: 'bench-${config.implementation}',
        );
        if (finished) {
          isolate!.kill(priority: Isolate.immediate);
          return;
        }
        arm();
        isolate!.resume(isolate!.pauseCapability!);
      } on Object catch (e) {
        controller.add(_Failed(null, 'spawn failed: $e'));
        finish();
      }
    }();

    return controller.stream;
  }
}

// --- child isolate --------------------------------------------------------------

class _ChildArgs {
  _ChildArgs(
    this.port,
    this.shape,
    this.size,
    this.seed,
    this.runs,
    this.warmup,
    this.operations,
    this.createSubject,
  );

  final SendPort port;
  final WorkloadShape shape;
  final int size;
  final int seed;
  final int runs;
  final int warmup;
  final List<String> operations;
  final SubjectFactory createSubject;
}

void _childMain(_ChildArgs args) {
  final port = args.port;
  void phase(String? operation, String phase, [int completedRuns = 0]) =>
      port.send({
        'event': 'phase',
        'operation': operation,
        'phase': phase,
        'completed_runs': completedRuns,
      });

  String? current;
  try {
    phase(null, 'workload');
    final workload = Workload.generate(args.shape, args.size, seed: args.seed);
    port.send({'event': 'workload', 'description': workload.describe()});
    final subject = args.createSubject(workload);

    for (final operation in args.operations) {
      current = operation;
      phase(operation, 'setup');
      subject.setUp(operation);
      final times = <double>[];
      Map<String, Object> counts = const {};
      for (var i = 0; i < args.warmup + args.runs; i++) {
        final warm = i < args.warmup;
        phase(operation, warm ? 'warmup' : 'run', times.length);
        subject.beforeRun(operation);
        final sw = Stopwatch()..start();
        counts = subject.run(operation);
        sw.stop();
        if (!warm) times.add(sw.elapsedMicroseconds / 1000);
      }
      port.send({
        'event': 'result',
        'operation': operation,
        'times_ms': times,
        'counts': counts,
      });
    }
    port.send({'event': 'done'});
  } on Object catch (e, st) {
    final where = current == null ? 'workload' : 'operation $current';
    final frames = st.toString().split('\n').take(6).join(' | ');
    port.send({'event': 'error', 'error': '$where: $e ($frames)'});
  }
}
