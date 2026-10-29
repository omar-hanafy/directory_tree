# directory-tree agent plugin

Teaches AI coding agents the
[directory_tree](https://pub.dev/packages/directory_tree) Dart package: the
exact 2.0.0 API and its traps, and how to upgrade a project from 1.x. It
installs in Claude Code, Codex, and Google Antigravity from this
repository.

The plugin contains skills only: markdown instructions, with no hooks, MCP
servers, scripts, or network access.

## Skills

| Skill | Loads for requests about |
|---|---|
| `use-directory-tree` | Building trees from paths or typed entries, `DirectoryTreeBuilder`, paths and `PathPolicy`, roots, ordering, issues, ids and lookups, rows and incremental expansion (persisting `requestedExpansion`), search syntax and highlighting, filters, selection and tri-state checkboxes, `ListDiff` and `TreeDiff`, text rendering, and the `DirectoryScanner` |
| `migrate-directory-tree-v1-to-v2` | The 2.0.0 upgrade: `dart fix --apply` for the three renames, the manual mapping of every 1.x declaration, and the behavior checklist (case-sensitive paths, canonical-path ids, no synthetic root, immutable state, default expansion, natural order, search syntax) |

An agent loads a skill when a request matches it. In Claude Code you can also
call one directly, for example `/directory-tree:use-directory-tree`.

## Install, update, and remove

### Claude Code

In a session:

```text
/plugin marketplace add omar-hanafy/directory_tree
/plugin install directory-tree@directory-tree-tools
```

Or from a shell:

```bash
claude plugin marketplace add omar-hanafy/directory_tree
claude plugin install directory-tree@directory-tree-tools
```

Run `/reload-plugins` or start a new session to load it.

- Update: `claude plugin marketplace update directory-tree-tools`, then
  `claude plugin update directory-tree@directory-tree-tools`. Claude Code
  leaves automatic updates off for third-party marketplaces; to turn them
  on, run `/plugin`, open **Marketplaces**, select `directory-tree-tools`,
  and choose **Enable auto-update**.
- Remove: `claude plugin uninstall directory-tree@directory-tree-tools`,
  or `claude plugin marketplace remove directory-tree-tools` to remove the
  marketplace and its plugin together.

### Codex

```bash
codex plugin marketplace add omar-hanafy/directory_tree
codex plugin add directory-tree@directory-tree-tools
```

Start a new Codex session; an open session does not pick up new skills.

- Update: `codex plugin marketplace upgrade directory-tree-tools`
  refreshes the marketplace and the installed copy.
- Remove: `codex plugin remove directory-tree@directory-tree-tools`. To
  drop the marketplace as well, run
  `codex plugin marketplace remove directory-tree-tools` afterwards; on its
  own, that command leaves the plugin installed.

Where a Codex surface has no plugin support, its `$skill-installer` skill can
install the folders under `tooling/ai/directory-tree/skills/` directly.

### Google Antigravity

```bash
agy plugin install https://github.com/omar-hanafy/directory_tree/tree/main/tooling/ai/directory-tree
```

The command installs the plugin into `~/.gemini/config/plugins/`, which the
`agy` CLI, the Antigravity IDE, and the desktop app all read. Start a new
session to load it. Use the full URL above: the plugin lives in a subfolder,
so the bare repository URL finds nothing to install.

- Update: run the same install command again; it replaces the installed copy.
  Antigravity has no third-party marketplace yet, so nothing updates on its
  own.
- Remove: `agy plugin uninstall directory-tree`.

### Other agents

The plugin has an [Agent Plugins 1.0](https://agent-plugins.org/) manifest
(`plugin.json`), and each skill is a standard
[Agent Skills](https://agentskills.io/) folder, so agents that read either
format can load this folder directly. Only the three hosts above are tested.

## Example prompts

- "Upgrade this project from directory_tree 1.0.0 to 2.0.0 and check the
  behavior changes that affect us."
- "Show these file paths as a collapsible tree view with directory_tree and
  keep the expanded folders across restarts."
- "Add a search box to this directory_tree explorer that highlights the
  matched part of each row."
- "Turn this file picker into a checkbox tree where checking a folder
  checks every file in it."

## Permissions and trust

The skills tell the agent to run ordinary Dart tooling in your project, such
as `dart pub get`, `dart fix --dry-run`, `dart analyze`, `dart test`, and
`grep`, through your agent's usual approval prompts. The plugin itself runs
nothing and sends nothing anywhere.

## Compatibility

- Documents directory_tree 2.x; the plugin version always equals the package
  version it documents. The migration skill covers projects on 1.x.
- Installation is tested with Claude Code 2.1.312, Codex 0.165.0, and the
  Antigravity CLI 1.4.9 (October 2026). A weekly CI job repeats the test
  with each host's current release.

## For maintainers

```text
tooling/ai/directory-tree/
  plugin.json                  Agent Plugins 1.0 manifest: Codex, Antigravity, other clients
  .claude-plugin/plugin.json   Claude Code manifest
  .codex-plugin/plugin.json    legacy manifest for Codex releases before Agent Plugins
  assets/icon.png              icon for all three manifests
  skills/<skill>/SKILL.md      one folder per skill
  evals/<case>/                cases for claude plugin eval
```

The marketplace catalogs live at the repository root:
`.claude-plugin/marketplace.json` for Claude Code and
`.agents/plugins/marketplace.json` for Codex. Antigravity installs the plugin
folder itself.

Rules:

- The three manifests share their metadata, and their `version` equals the
  `pubspec.yaml` version; bump them together.
- Codex reads its interface (display name, prompts, icons) from
  `extensions["com.openai"].interface` in `plugin.json`, and older releases
  read the legacy manifest's `interface`; keep the two identical.
- Skill facts must match the source. Change a skill in the same pull request
  as the behavior it describes. `test/agent_skill_claims_test.dart` runs
  every Dart block of the skills, checks each `print(...); // output`
  comment, and asserts the claims the prose makes against the API.
- A breaking package release ships its migration hop, as a new
  `migrate-directory-tree-vX-to-vY` skill, before it is tagged.

Checks, run from the repository root:

| Check | Command | Where it runs |
|---|---|---|
| Skill facts against the API | `dart test test/agent_skill_claims_test.dart` | CI on every pull request (part of `dart test`) |
| Files, manifests, catalogs, and README commands | `dart run tool/validate_agent_plugin.dart` | Agent plugin workflow |
| Install in each host, plus each host's strict validator | `dart run tool/verify_agent_hosts.dart --require claude,codex,agy` | Agent plugin workflow: pull requests and pushes to `main` that touch the plugin, weekly, and on demand |
| Install from GitHub the way users do | `dart run tool/verify_agent_hosts.dart --github main` | Agent plugin workflow on `main`: pushes that touch the plugin, weekly, and on demand |
| Skill behavior against a no-plugin baseline | `claude plugin eval tooling/ai/directory-tree --no-publish --output-dir <dir outside the repo>` | By hand; it calls the model on your account |

The host check uses throwaway profiles, so it never touches your own Claude
Code, Codex, or Antigravity setup and needs no sign-in. Without `--require`,
it skips any host that is not on PATH.

### Keeping it current

Hosts and their plugin formats change every few weeks. When the weekly
Agent plugin workflow fails, and before each package release:

1. Read what changed in each host since the versions listed under
   Compatibility (`agy changelog` prints Antigravity's notes), and check
   [agent-plugins.org](https://agent-plugins.org/) and
   [agentskills.io](https://agentskills.io/) for new spec versions.
2. Run the checks above, and
   `claude plugin details directory-tree@directory-tree-tools` after a
   local install to see the always-on token cost.
3. Run the eval suite and compare it with the last run.
4. Update the tested versions under Compatibility and in the package README.
