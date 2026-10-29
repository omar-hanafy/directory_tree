# directory_tree - agent guide (maintainers)

Pure-Dart package (no Flutter dependency, only `meta`) that turns path lists
into immutable, indexed directory trees and the views a UI needs: flattened
rows with incremental expand and collapse, search queries, selection with
tri-state checks, list and tree diffs, and text rendering.
`flutter_directory_tree` builds Flutter widgets on it.

## Entry points

- `lib/directory_tree.dart`: the core library. Pure Dart, runs on every
  platform (VM, AOT, Flutter, JavaScript, WebAssembly).
- `lib/io.dart`: the optional `DirectoryScanner`, which needs `dart:io`. It
  does not export the core library, and the core never imports it.

## Architecture (`lib/src/`)

| Directory | Contents |
| --- | --- |
| `path/` | `TreePath` (canonical root + segments), `PathPolicy` (parsing, case folding, `idOf`). |
| `tree/` | `DirectoryTree` (pre-order node array, id index, subtree sizes), with the parts `tree_builder.dart` (`DirectoryTreeBuilder` and the trie-based assembler) and `tree_node.dart` (sealed `TreeNode`, `FileNode`, `DirectoryNode`); `NodeId`, `TreeEntry`, `TreeIssue`, `TreeOptions`/`TreeRoots`/`TreeOrder`. |
| `view/` | `ExpansionState`, `TreeRows`/`TreeRow` (`flatten`, incremental updates, keyboard helpers), `tree_renderer.dart` (`TreeStyle`, `render`). |
| `filter/` | `TreeFilter` and its combinators, `TreeQuery` (search syntax, `matchRanges`). |
| `selection/` | `SelectionState`, `SelectionMode`, `CheckState`. |
| `diff/` | `ListDiff` (LIS-based keyed list diff), `TreeDiff` (by node id). |
| `io/` | `DirectoryScanner` (explicit-stack walk over `dart:io`). |

## Validation gates (run before claiming any change done)

```bash
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos                 # every lint is a gate
dart fix test_fixes --compare-to-golden    # CI runs it once test_fixes/ exists
dart run tool/check_repo.dart              # em-dash, changelog, platform imports, deprecations
dart run tool/validate_agent_plugin.dart   # AI plugin/marketplace consistency
# After plugin changes (needs the claude, codex, and agy CLIs on PATH):
dart run tool/verify_agent_hosts.dart --require claude,codex,agy
dart test                                  # VM
dart test -p node                          # JavaScript
dart test -p node -c dart2wasm             # WebAssembly locally; CI uses -p chrome -c dart2wasm
dart pub publish --dry-run                 # must stay at 0 warnings
dart pub global activate pana 0.23.19 && pana --exit-code-threshold 0 .   # 160/160
```

`.github/workflows/ci.yml` runs these jobs:

- "CI / Test on stable": the version channel check, format, analyze, dart
  fix goldens, `tool/check_repo.dart`, and the VM, Node, and Chrome wasm
  test runs.
- "CI / Test on minimum SDK": Dart 3.8.0 with `dart pub downgrade`,
  `dart analyze`, then `dart test --compiler source` (the downgraded
  frontend server cannot start on 3.8.0).
- "CI / Test on Windows": `dart test` on `windows-latest`, so the scanner
  meets real drive letters and backslashes. Not a required check.
- "CI / Test on beta": analyze and test on the beta SDK,
  `continue-on-error`.
- "CI / Pana": pana pinned to 0.23.19 with `--exit-code-threshold 0`, so
  any lost point fails. Bump the pin deliberately.

`agent-plugin.yml` ("Agent plugin / Hosts") runs the plugin validator,
the skill claims test, and the host check on pull requests and pushes to
`main` that touch the plugin, weekly, and on demand. It is not a required
check: a host outage must not block a release.

`publish-dry-run.yml` runs `dart pub publish --dry-run`; warnings are fatal
there, so never add `--ignore-warnings`.

`analysis_options.yaml` is strict (strict casts, inference, and raw types);
`test/` and `example/` relax only doc and API-shape rules. Never weaken a
rule to get a green run.

## Conventions

- Only `lib/io.dart` and `lib/src/io/**` import `dart:io`; nothing under
  `lib/` imports another platform library (`dart:html`, `dart:ffi`,
  `dart:isolate`, `dart:js_interop`, ...). `tool/check_repo.dart` enforces
  both.
- Traversals are iterative (explicit stacks, pre-order index ranges); no
  recursion, so depth is unlimited. `test/directory_tree_test.dart` builds
  and walks a 1000-deep chain.
- No integers above 2^53, so the VM, JavaScript, and wasm give the same
  results.
- Immutable value types are `final class` with `@immutable`, `==`,
  `hashCode`, and `toString`; methods that return a new instance are
  `@useResult`. The exceptions are deliberate: `TreeFilter` is an
  `abstract class` users extend, `TreeRows` is an unmodifiable `ListBase`,
  and `DirectoryTreeBuilder` is mutable and compares by identity.
- Determinism: the same entry set in any order builds `==` trees with the
  same node order and ids (`test/determinism_test.dart`). Never let output
  depend on hash iteration order or input order.
- Bad input never throws while building; it becomes a `TreeIssue`.
- Tests live flat in `test/`, one file per domain. Use `@TestOn('vm')` only
  for files that import `dart:io` or read repository files; every other
  file must compile and pass on Node and wasm.
- Every public declaration has dartdoc that follows `docs_guide.md`: what
  it is, when to use it, and its contract (defaults, null and empty
  behavior, side effects, complexity).
- Never use the em-dash character (U+2014) in any file; use '-'.
  `tool/check_repo.dart` enforces it.
- Every Dart block in `README.md` is copied verbatim into
  `test/readme_test.dart`, which runs it and checks each
  `print(...); // output` comment, and compares multi-line output with the
  ```` ```text ```` block that directly follows the Dart block. Edit an
  example in both places; meta tests fail when a block has no copy, a
  print goes unchecked, or a text block is not a checked output. README
  code lines must survive `dart format` at the test's indentation (about
  74 columns).
- `example/example.dart` (pure, tested by `test/example_test.dart` on every
  platform) and `example/scan_directory.dart` (tested by
  `test/scan_example_test.dart` on the VM) print their results; keep the
  tests in sync.

## AI assistant plugin (Claude Code, Codex, Antigravity)

- Canonical tree: `tooling/ai/directory-tree/` with one shared `skills/`
  set (`use-directory-tree`, `migrate-directory-tree-v1-to-v2`),
  `assets/icon.png`, an `evals/` suite for `claude plugin eval`, and three
  manifests: `plugin.json` (Agent Plugins 1.0, read by Codex, Antigravity,
  and other Agent Plugins clients), `.claude-plugin/plugin.json` (Claude
  Code), and `.codex-plugin/plugin.json` (legacy, for older Codex
  releases). Catalogs: `.claude-plugin/marketplace.json` and
  `.agents/plugins/marketplace.json` at the repo root; Antigravity has no
  third-party marketplace and installs the plugin folder by its GitHub
  `tree/main/...` URL.
- All three manifests' `version` must equal the `pubspec.yaml` version, and
  their shared metadata must match; the Codex interface appears in
  `plugin.json` (`extensions["com.openai"].interface`) and in the legacy
  manifest, identically. `tool/validate_agent_plugin.dart` enforces this,
  plus the icon, the skill frontmatter and size limits, the eval layout,
  and the install commands in both READMEs.
- `tool/verify_agent_hosts.dart` installs the plugin in throwaway Claude
  Code, Codex, and Antigravity profiles (never the real ones) and requires
  the pubspec version and byte-identical skills; `--github <ref>` installs
  from GitHub the way users do. A weekly failure usually means a host
  changed its plugin contract; the plugin README's "Keeping it current"
  section is the refresh checklist.
- Skill facts must match the source (the dartdoc in `lib/`, `README.md`,
  `MIGRATION.md`, `lib/fix_data.yaml`). When changing behavior in `lib/`,
  update the affected skill or reference file in the same pull request.
  `test/agent_skill_claims_test.dart` runs every ```` ```dart ```` block of
  the skills (copied verbatim, like the README blocks, and checking each
  `print(...); // output`) and asserts every factual claim of the prose
  against the API; extend it when a skill gains a claim, and never weaken
  it to get a green run: re-check the fact instead.
- Skill code lines must survive `dart format` at the test's indentation
  (about 72 columns, trailing comment included).
- A breaking release must ship its migration hop as a
  `migrate-directory-tree-vX-to-vY` skill before it is tagged.
- The plugin tree, catalogs, `tool/`, the claims test (it reads the
  skills), and this file are excluded from the pub archive (`.pubignore`,
  and pub skips hidden directories). Eval
  results are not committed: run `claude plugin eval` with `--output-dir`
  outside the repository, since `evals/results/` is not gitignored and
  `tool/check_repo.dart` scans untracked files.

## Consumer-relied invariants

`flutter_directory_tree` depends on these. Changing any of them is a
breaking change that needs a major version.

- `TreeRows.expandNode`, `collapseNode`, `toggleNode`, and `reveal` reuse
  every row object outside the changed block (`identical`), and return the
  same `TreeRows` when nothing changes. The row whose state flips is a new
  object. `test/tree_rows_test.dart` ("incremental updates", "reveal", and
  the property test "incremental updates equal a full flatten" through
  `expectUpdate`).
- Expanding an empty directory inserts no rows: only that directory's own
  row is replaced (its `isExpanded` flips) and the expansion states change.
  Covered only by the same property test's block-shape check, on random
  trees that include explicit directory entries; there is no dedicated
  test yet.
- `TreeRows.expansion` includes the ancestors a filter revealed;
  `TreeRows.requestedExpansion` excludes them and is the value to persist.
  `test/tree_rows_test.dart` ("requested expansion").
- `SelectionState.extendTo` iterates the row order once and stops at the
  end of the range. `test/selection_state_test.dart` ("iterates order once
  and stops at the range end").
- `ExpansionState.prune` keeps every exception that is a directory of the
  tree and drops files and unknown ids, without changing `isExpanded` for
  the tree's directories. `test/expansion_state_test.dart` ("prune drops
  ids that are not directories of the tree", "prune keeps answers for
  directories of the tree").
- Unknown ids never throw: lookups return `null`, -1, 0, `false`, or an
  empty result, and row updates and tree-aware state operations return the
  same object. `test/directory_tree_test.dart` ("lookups return null, -1,
  0, false, or empty"), `test/tree_rows_test.dart` ("unknown ids, files,
  and unchanged states return the same rows"),
  `test/selection_state_test.dart` ("unknown ids leave the state
  unchanged"), `test/expansion_state_test.dart` ("subtree operations
  ignore files, unknown ids, and outside ids").
- `flatten` calls the filter once per node, and incremental updates and
  `withExpansion` never call it again. `test/tree_rows_test.dart` ("the
  filter is never called again", "updates never call the filter again").

## Docs

`docs_guide.md` is the documentation standard for dartdoc and private
comments. The README must agree with the dartdoc; check a claim in the
code or with a test before writing it. `README.md` links
`benchmark/RESULTS.md` by absolute GitHub URL because `benchmark/` is not
in the pub archive.

## Benchmarks

`benchmark/` holds separate pub packages that compare 1.0.0 with this code
on generated workloads; see `benchmark/README.md` for running them and for
what each operation measures. `benchmark/RESULTS.md` is generated by
`benchmark/runner`; do not edit it by hand. Refresh the README's
performance table from it after a full run.

## Release process

1. `main` carries stable versions only and `dev` prerelease versions only
   (`-dev.N`); the CI version channel check enforces it. A release lands
   through a pull request into `main` (or `dev` for a prerelease).
2. A release PR bumps `pubspec.yaml` and adds the `CHANGELOG.md` section
   for that version (`tool/check_repo.dart` requires it). Breaking
   releases also update `MIGRATION.md` and ship `dart fix` data
   (`lib/fix_data.yaml` with `test_fixes/` goldens).
3. On merge, `auto-release.yml` sees that the version value changed,
   creates the tag `directory_tree-v<version>` with `TAG_PUSH_PAT` (a tag
   pushed with `GITHUB_TOKEN` would not start the publish workflow), and
   creates the GitHub release (a prerelease from `dev`).
4. The tag starts `publish.yml`, which publishes to pub.dev through
   trusted publishing (OIDC); no credentials are stored.

Never tag or publish by hand. Tags are immutable: never move, delete, or
reuse one. A bad release is fixed with a new version.

## Git safety

- Never run `git reset`, `git restore`, `git checkout -- <path>`,
  `git clean`, or `git stash` unless the user asks for it. Ask before
  discarding any local change.
- Commit or push only when asked. No attribution or co-author lines in
  commits or pull requests.
