import 'package:directory_tree_bench_workloads/workloads.dart';

/// The operations every implementation measures, in execution order.
///
/// - `build`: turn the workload's paths into the implementation's tree.
/// - `flatten`: produce the visible rows with every folder expanded.
/// - `toggle`: collapse [Workload.toggleTarget] and get the updated rows the
///   cheapest way the implementation supports (incremental when it has an
///   incremental API).
/// - `toggle_full`: the same collapse through a full flatten with the target
///   collapsed in the expansion state.
/// - `filter`: produce the rows for [Workload.filterQuery].
/// - `diff`: diff the fully expanded rows against the rows after `toggle`.
const List<String> standardOperations = [
  'build',
  'flatten',
  'toggle',
  'toggle_full',
  'filter',
  'diff',
];

/// The operations whose prepared state each operation's [BenchSubject.setUp]
/// recomputes. When a prerequisite times out or fails, the dependent
/// operation is reported as blocked instead of being attempted.
const Map<String, List<String>> standardPrerequisites = {
  'build': [],
  'flatten': ['build'],
  'toggle': ['build'],
  'toggle_full': ['build'],
  'filter': ['build'],
  'diff': ['build', 'flatten', 'toggle'],
};

/// One implementation under test, created fresh inside each child isolate.
///
/// The harness calls [setUp] once per operation, then [beforeRun] and [run]
/// for every warm-up and timed run of that operation. Only [run] is timed.
/// Each child isolate gets a new subject, so [setUp] must be able to prepare
/// an operation's inputs from scratch (lazy fields work well for that).
abstract class BenchSubject {
  /// Prepares everything [operation] needs, without timing it.
  void setUp(String operation);

  /// Restores state before each run of [operation], without timing it.
  ///
  /// Stateful operations need it, for example an incremental collapse that
  /// must start from the expanded state every run. The per-step budget
  /// covers [beforeRun] and [run] together. Does nothing by default.
  void beforeRun(String operation) {}

  /// Executes [operation] once and returns counts describing the result
  /// (for example `{'rows': 1234}`).
  ///
  /// The counts end up in the JSON output and must be derived from the
  /// result, so the measured work cannot be optimized away.
  Map<String, Object> run(String operation);
}

/// Creates the subject for a workload. Must be a top-level or static
/// function: it is sent to child isolates.
typedef SubjectFactory = BenchSubject Function(Workload workload);
