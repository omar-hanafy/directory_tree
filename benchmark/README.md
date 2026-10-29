# directory_tree benchmarks

Performance benchmarks that compare `directory_tree` 1.0.0 (the release on
pub.dev) with the 2.0.0 rewrite on identical, generated inputs.

This directory is excluded from the published package (`.pubignore`) and from
the root analyzer (`analysis_options.yaml`). Every subdirectory is its own
pub package with its own `pubspec.yaml` and `analysis_options.yaml`.

| Directory | Contents |
|---|---|
| `workloads/` | Deterministic, seeded path generators (pure Dart, no dependencies). |
| `harness/` | Shared measurement code: CLI flags, warm-up and timed runs, the per-step time budget, JSON output. |
| `v1/` | Subject for `directory_tree: 1.0.0` from pub.dev (exact version). |
| `v2/` | Subject for the 2.0.0 code in this repository (`directory_tree: {path: ../..}`). |
| `runner/` | Compiles each implementation to an AOT executable, runs the matrix, writes `RESULTS.md`. |
| `RESULTS.md` | The latest report. |
| `results.jsonl` | Every stored record, one JSON object per line (the source of `RESULTS.md`). |

## Running

The full matrix (every implementation, shape, and size):

```sh
cd benchmark/runner
dart pub get
dart run bin/run.dart
```

Useful flags (`dart run bin/run.dart --help` lists them all):

```sh
dart run bin/run.dart --sizes 10k,100k           # skip the 1M workloads
dart run bin/run.dart --impls v2 --sizes 1m      # re-measure one column
dart run bin/run.dart --budget-ms 20000          # give up sooner
dart run bin/run.dart --report-only              # rebuild RESULTS.md only
```

The runner compiles `benchmark/<impl>/bin/bench.dart` with
`dart compile exe` into `benchmark/<impl>/build/bench` (gitignored) and skips
an implementation whose package or `bin/bench.dart` does not exist. New
records replace stored ones with the same implementation, shape, size, and
operation, so you can re-measure a subset without losing the rest; pass
`--fresh` to start over. Each record stores the machine, OS, and
`dart --version` it was measured with, and `RESULTS.md` lists every
environment that contributed.

One implementation and workload, without the runner:

```sh
cd benchmark/v1
dart pub get
dart compile exe bin/bench.dart -o build/bench
build/bench --shape deep --size 100k --runs 5 --warmup 1 --budget-ms 60000
```

`dart run bin/bench.dart ...` works too, but it runs on the JIT; only report
AOT numbers. Run the packages' own checks with `dart analyze` and
`dart test` inside `workloads/`, `harness/`, `v1/`, `v2/`, and `runner/`.

## Workloads

`Workload.generate(shape, size, seed: ...)` returns `size` unique absolute
POSIX paths under `/repo`, plus the inputs the operations need. The generator
uses its own 32-bit PRNG (mulberry32), so a seed gives the same list on every
run, machine, and SDK; `workloads/test/` pins the fingerprints.

- `deep`: project-like trees. Files sit 1-14 segments below `/repo` (most at
  7-14), directories hold about 5-30 entries, names come from a programming
  vocabulary with mixed extensions.
- `wide`: shallow trees. Files sit 2-3 segments below `/repo` in very large
  directories whose size grows with the workload: about 1,000-3,000 files
  each at 10k, 3,000-9,500 at 100k, and 10,000-30,000 at 1M.

Sizes: 10,000, 100,000, and 1,000,000 files. Both shapes put a few files
directly in `/repo`, so `/repo` is the single top folder for every
implementation.

Each workload also defines:

- Toggle target: a directory near the middle of the tree (the median, by
  path, of the directories that hold 5-25% of all files).
- Filter query: `legacy`, a plain name fragment that appears in about 3% of
  file names and in no directory name. It is a substring rather than an
  `ext:` query so every implementation's filter syntax accepts it.
- Fingerprint: an FNV-1a hash of the path list. Every record carries it, and
  `RESULTS.md` warns when the records compared in one row disagree.

`RESULTS.md` has a table with each workload's folder count, depth, toggle
target, and match count. For more detail (files per directory, depth
histogram), run `dart run bin/stats.dart [size ...]` inside `workloads/`.

## Operations

Only the operation itself is timed. Inputs it needs (the entry list, the
built tree, the expanded-id sets, the rows to diff) are prepared before the
timed runs.

Both implementations run with their default options (v1 defaults to
case-insensitive paths, v2 to case-sensitive ones; the workloads are all
lower case apart from a few root files, so the trees are the same).

| Operation | v1 (1.0.0) | v2 (2.0.0) |
|---|---|---|
| `build` | `TreeBuilder().build(entries: ...)`; entries are non-virtual `TreeEntry`s (id = path, name = basename), created untimed. | `DirectoryTree.build(entries)`; entries are `TreeEntry<Never>.file(path)`, created untimed. |
| `flatten` | `DefaultFlattenStrategy().flatten(data:, expandedIds:)` with every folder id expanded. | `tree.flatten()` (default `ExpansionState.expanded()`). |
| `toggle` | Collapse the toggle target the cheapest supported way. v1 has no incremental API: a full flatten with the target removed from the expanded set. | `rows.collapseNode(id)` on the fully expanded `TreeRows` (incremental; `TreeRows` is immutable, so every run starts from the same rows). |
| `toggle_full` | Same call as `toggle` (the only way v1 can collapse). | `tree.flatten(expansion: const ExpansionState.expanded().collapse(id))`. |
| `filter` | `flatten` with `filterQuery: 'legacy'`. | `tree.flatten(filter: TreeQuery.parse('legacy'))`. |
| `diff` | `diffVisibleNodes(fullRows, rowsAfterToggle)`. | `ListDiff.compute(fullRows, rowsAfterToggle, keyOf: (row) => row.id)`. |

So the `toggle` row compares what an application pays to collapse a folder,
and the `toggle_full` row compares full re-flattens. Filter results are
matches plus their ancestors in both versions. Each subject's test checks
every count against the workload (and v2's test checks that the incremental
and full collapse give the same rows).

Each record also carries counts derived from the result (`nodes`, `rows`,
`hidden_rows`, `removed`, `inserted`). They keep the work from being
optimized away and let you check that implementations produce comparable
output.

## Measurement

For each operation the harness runs the warm-up runs (default 1) and then the
timed runs (default 5) and reports the median and minimum (and maximum) wall
time in milliseconds, measured with `Stopwatch`.

Operations run in a child isolate. Every step (workload generation, an
operation's set-up, each warm-up or timed run) has to finish within the
budget (default 60 s, `--budget-ms`). When a step runs longer, the harness
kills the child isolate, prints the operation with `"timeout_ms": <budget>`
and `"timeout_phase"` instead of numbers, and continues with the remaining
operations in a new child isolate. Operations that depend on one that timed
out (see `standardPrerequisites`; for example everything after a `build` that
exceeded the budget) are reported as timeouts with `"timeout_phase":
"blocked"` and `"blocked_by"` rather than spending the budget again. The
runner also kills an executable that outlives its whole budget, so a run
never hangs.

Output is one JSON object per operation on stdout, for example:

```json
{"implementation":"v1","shape":"deep","size":10000,"operation":"toggle","runs":5,"warmup":1,"budget_ms":60000,"seed":20261028,"fingerprint":"131893f6","median_ms":0.593,"min_ms":0.577,"max_ms":0.61,"rows":10647,"hidden_rows":898}
```

## Adding an implementation

`v2/` is the reference for a new implementation `<impl>` (add its name to
`knownImplementations` in `runner/lib/src/report.dart` to give it a column).

1. Create `benchmark/<impl>/pubspec.yaml` with `publish_to: none`, depending on
   `directory_tree: {path: ../..}`, `directory_tree_bench_harness: {path:
   ../harness}`, and `directory_tree_bench_workloads: {path: ../workloads}`,
   plus `lints` and `test` as dev dependencies. Copy
   `v1/analysis_options.yaml`.
2. Implement `BenchSubject` (see `harness/lib/src/subject.dart` and
   `v1/lib/v1_subject.dart`):
   - `setUp(operation)` prepares the operation's inputs untimed and must work
     in a fresh subject, because a timeout restarts the remaining operations
     in a new isolate.
   - `beforeRun(operation)` (optional) restores state before every run, for
     example re-expanding the target before an incremental collapse.
   - `run(operation)` performs the operation once and returns counts derived
     from the result.
   Use the implementation's idiomatic API for each operation: for `toggle`,
   the cheapest supported way to collapse `workload.toggleTarget` and get
   the updated rows; for `toggle_full`, a full flatten.
3. Add `bin/bench.dart`:
   ```dart
   Future<void> main(List<String> args) =>
       runBenchmarkCli(args, implementation: '<impl>', createSubject: createSubject);
   ```
   where `createSubject` is a top-level function (it is sent to isolates).
4. Add a test like `v2/test/v2_subject_test.dart` that checks the counts
   against the workload, then run `dart run bin/run.dart` from `runner/`.

## Caveats

- Wall-clock numbers depend on the machine, its load, thermal state, and
  power settings. Compare columns only when they come from the same
  environment, and close other heavy processes first.
- Garbage collection dominates the spread on the 100k and 1M workloads: a
  run that triggers a full collection of the large heap (the tree plus a
  million rows) can take several times longer than one that does not, and
  the operations run one after another in the same isolate, so later
  operations also collect garbage left by earlier ones. With 5 timed runs
  the median can land on either side, so `RESULTS.md` also has a "Fastest
  run" table (v1 min / v2 min), which reflects the cost of the operation
  itself. Raise `--runs` for steadier medians.
- A v1 `build` of wide 1M takes 56-60 s on an M2 Pro, right at the default
  budget; the stored records for it were measured with
  `--budget-ms 180000` (the settings line in `RESULTS.md` lists every
  budget used).
- The workloads are synthetic. `wide` deliberately scales directory size with
  the workload, which stresses per-directory costs (v1 copies a folder's child
  list on every insertion, so building a directory of k files costs O(k^2)).
- `build` excludes creating the input list. `toggle` deliberately compares
  different algorithms (v1 full flatten, v2 incremental update); use
  `toggle_full` for a like-for-like flatten comparison.
- AOT compilation drops object fields that the program never reads. The
  timed v1 operations read only `VisibleNode.id`, which would shrink a v1
  row in the benchmark executable from 96 to 16 bytes and let `flatten`,
  `toggle_full`, and v1's `toggle` allocate several times less than in
  any application that draws rows. Both subjects therefore read every row
  field once, on a tiny tree, in their untimed set-up, so each executable
  keeps the rows an application gets. Results measured before this read
  was added understate v1's row cost: its `flatten` medians were 10.7 ms
  (deep 100k) and 187 ms (wide 1M), well below those in `RESULTS.md`.
- `filter` uses a plain substring query; v1's `ext:` and `!` syntax is not
  exercised.
- Generator changes alter the fingerprints and invalidate stored results;
  regenerate everything (`--fresh`) after such a change.
