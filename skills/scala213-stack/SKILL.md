---
name: scala213-stack
description: >
  Tooling workflow for Scala 2.13 projects built with sbt 1.x, using the VirtusLab Scala Stack
  tools adapted to Scala 2: Metals MCP (compile, test, navigate, find usages, format, scalafix),
  Cellar (look up dependency APIs from _2.13 artifacts), and Orca (delegate plan/code/review
  flows with sbt gates and Scala 2.13 reviewers). Use whenever writing, refactoring, compiling,
  testing or reviewing code in a Scala 2.13 / sbt repository, adding or upgrading a dependency,
  looking up a library signature, finding usages before a change, setting up Metals MCP, Cellar
  or Orca for a 2.13 project, or delegating Scala work to Orca. Not for Scala 3 or sbt 2 projects.
---

# Scala 2.13 + sbt with Metals MCP, Cellar and Orca

Goal: work on Scala 2.13 code with real compiler feedback and real API data instead of guessing.
Compile after every edit, look up every unfamiliar signature, and review with 2.13-aware rules.

VirtusLab's docs (vss.virtuslab.com) assume Scala 3, sbt 2, scala-cli and Ox. **Do not copy their
Scala-3-only advice** into this project: no braceless syntax, `given`/`using`, `enum`, extension
methods, opaque types, `-Wunused:all`, or sbt 2 output paths. Keep the effect and concurrency style
the project already uses.

## 1. Orient (start of every task)

1. Confirm this is a 2.13 / sbt 1.x project: `build.sbt`, `project/build.properties`,
   `scalaVersion`/`crossScalaVersions`. Note `-Xsource:3`, `-Werror`/`-Xfatal-warnings`,
   compiler plugins and `.scalafmt.conf`.
2. Run `scripts/doctor.sh` (read-only) once per session to see which tools are available.
   Paths in this skill are relative to the skill directory.
3. Use what is available and degrade gracefully. Each row in the routing table has a fallback.
   Do not install tools, start servers, or change settings without asking the user.

## 2. Routing: which tool for which job

| Task | Preferred | Fallback |
|---|---|---|
| List sbt modules / build targets | Metals `list-modules` | `sbt projects` |
| Compile after an edit | Metals `compile-file` (`fileInFocus`) | `sbt --client <proj>/Test/compile` |
| Compile a module, including its tests | Metals `compile-module` (test target) | `sbt --client <proj>/Test/compile` |
| Run one suite or test | Metals `test` (`testClass`, `testName`) | `sbt "<proj>/testOnly <FQN>"`; one test: munit `-- --tests=name`, ScalaTest `-- -z "name"` (others: sbt-workflow.md) |
| Find a symbol by name | Metals `glob-search` / `typed-glob-search` (unqualified name) | Scalex skill, then grep |
| Members of a project type | Metals `inspect` with `fileInFocus` | read the source |
| Who uses X (before changing it) | Metals `get-usages` | Scalex refs, then grep |
| API of a dependency | `cellar get --module <proj> <fqn>` (resolved version) | `cellar get-external <g>:<a>_2.13:<v> <fqn>` |
| Scaladoc / source of a 2.13 dependency | Metals `get-docs` / `get-source` | `cs fetch --sources` + `unzip -p` (see cellar.md) |
| Which versions exist | Metals `find-dep` (`name: "<a>_2.13"`) | `cellar get-external <g>:<a>_2.13:latest <fqn>`, `cs complete-dep` |
| Transitive deps / evictions | `cellar deps <coord>` | `sbt <proj>/dependencyTree`, `sbt <proj>/evicted` |
| Format changed files | Metals `format-file` (`fileInFocus`, one file per call in 1.6.9) | `sbt scalafmtAll scalafmtSbt` |
| Mechanical rewrite across files | Metals `run-scalafix-rule` / `generate-scalafix-rule` | `sbt "scalafixAll <Rule>"` |
| After editing build files | `sbt reload` + Metals `import-build` | `sbt reload` |
| Large, well-specified task to delegate | Orca (`/orca`, or `orca run implement.sc`), **after asking the user** | do it yourself |
| Review a branch or PR with several reviewers | `git diff main...HEAD \| orca run review.sc`, **after asking the user** (it commits uncommitted work) | review it yourself |

Metals tool names in Claude Code look like `mcp__metals__compile-file`.

## 3. Core loop

1. **Locate**: `list-modules`, then `glob-search`/`typed-glob-search`, then `inspect`
   (always pass `fileInFocus`), then `get-docs`.
2. **Before changing a signature**: `get-usages` on it. An empty result right after import may
   mean "not indexed yet": compile and retry before trusting it.
3. **Before calling a library API you haven't seen in this codebase**: run Cellar on the exact
   version (project mode). Look up the `_2.13` artifact, never `_3`.
4. **Edit**, matching the existing style (imports, braces, implicits, effect type, test framework).
5. **After each edited file**: `compile-file`. Fix errors *and new warnings* before moving on.
6. **After editing the build**: `import-build`, then `compile-module`.
7. **Test**: `test` for the affected suites. Add or extend tests in the project's framework.
8. **Format**: `format-file` on each file you changed (don't reformat untouched files).
9. **Done** when: affected modules pass `Test/compile` with no new warnings, affected tests are
   green, and changed files are formatted. Report anything you couldn't verify.

## 4. Scala 2.13 rules for using these tools

- **Coordinates**: Cellar and `find-dep` need the full suffix (`cats-core_2.13`, Java libraries
  have none, sbt plugins use `_2.12_1.0`). In `build.sbt` use `%%` for Scala libraries and `%` for Java.
- **Cellar on Scala 2** (≤ M13): signatures are accurate; ignore the
  `// [Scala 2 — limited type information]` marker. It shows no Scaladoc, prints defaults as `= ...`,
  `get-source` fails, sealed subtypes aren't listed, and implicit-class methods can be missing.
  Use Metals `get-docs`/`get-source` for those. If Cellar prints a JSON telemetry consent
  request, ask the user to choose. Never choose for them.
- **Metals**: `glob-search` takes an unqualified name, and wildcards match literally. `inspect` needs
  `fileInFocus`. Call `compile-file` explicitly after writing files (pushed diagnostics go stale).
  Prefer `compile-module` over `compile-full` (huge output). `compile-file` positions are 0-based
  (`L6` is line 7). `get-docs` resolves to the type level: for a method's docs, read `get-source`.
  `find-dep` "latest" can return a pre-release, so pick a stable version. If calls hang after a
  server restart, reconnect the server via `/mcp`.
- **sbt**: prefer `sbt --client` (or one batched `sbt "a; b"`) over many cold starts. Never use `~`
  or `console`. Don't change `scalacOptions`, `scalaVersion`, or plugin and dependency versions
  unless the task needs it, and call it out when you do.
- **Syntax**: Scala 3 syntax is only acceptable where the build has `-Xsource:3` *and* the code
  already uses it. Otherwise write plain 2.13 (braces, `implicit`, `sealed trait` + `case object`,
  `extends AnyVal` value classes).

## 5. Orca (delegation)

Use Orca only when the user agrees, for well-specified multi-file work or multi-reviewer reviews.
Every flow creates commits: even `review.sc` commits the uncommitted work it is given, and with
`--skip-branch` it does so on the current branch. Runs cost real tokens, and the coding flows run
agents with auto-approve, so run those in a sandbox. Before the first
run in a repo, make sure `.orca/settings.properties` pins the sbt gates, and that
`.orca/reviewers/scala-fp.md` replaces Orca's built-in Scala 3/Ox reviewer (templates in
`templates/orca/`). The Orca prompt must stand on its own: goal, acceptance tests, modules,
the "Scala 2.13, no Scala 3 syntax, keep existing effect style" constraint, and the verification
commands. Details: [references/orca.md](references/orca.md).

## 6. Setting up a project

When the user asks to set up the toolchain, follow [references/setup.md](references/setup.md):

- Metals MCP: `scripts/start-metals-mcp.sh`, fixed port 7333, writes `.mcp.json`.
- Cellar: install, telemetry decision, `templates/cellar.conf`.
- Orca: `templates/orca/`.
- `templates/CLAUDE.md.snippet` for the project's CLAUDE.md.
- `templates/plugins.sbt.snippet` for missing sbt plugins.

Show diffs to the user before writing into their project's config files.

## Reference files

- [references/metals-mcp.md](references/metals-mcp.md): all 17 tools, parameters, sequences, 2.13 notes, gotchas
- [references/cellar.md](references/cellar.md): project vs external mode, `_2.13` coordinates, Scala 2 output, source fallbacks
- [references/orca.md](references/orca.md): flows, sbt gates, 2.13 reviewers, MCP permissions, prompt template
- [references/sbt-workflow.md](references/sbt-workflow.md): sbt commands, 2.13 compiler flags, scalafmt/scalafix, adding dependencies
- [references/setup.md](references/setup.md): installation and per-project setup
- [references/troubleshooting.md](references/troubleshooting.md): symptom → cause → fix

If the upstream `cellar` or `orca` Claude Code plugins are also installed, use them for general
command syntax. The Scala 2.13 rules in this skill take precedence.
