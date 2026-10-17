# Metals MCP on Scala 2.13 + sbt

Metals MCP exposes Metals (BSP compilation, SemanticDB index, presentation compiler) as MCP tools.
Nothing in the MCP layer is Scala-3-specific. On 2.13, the compiler plugin `semanticdb-scalac`
provides SemanticDB, and Metals enables it automatically through Bloop or sbt BSP.

Tool names in Claude Code are prefixed with the server name, e.g. `mcp__metals__compile-file`.

## Tool reference (17 tools, Metals 1.6.9)

`*` = required parameter.

### Build and compile

| Tool | Params | Use it for |
|---|---|---|
| `list-modules` | — | First call in a session: sbt project / build target names (`core`, `core-test`, ...). |
| `import-build` | — | **After every change** to `build.sbt`, `project/*.sbt`, `project/*.scala` or `build.properties`. |
| `compile-file` | `fileInFocus` (path) | After each edit. Returns errors in the file, otherwise errors in its module, and reports upstream failures. |
| `compile-module` | `module`* | Compile one target, e.g. a test target after changing main code. |
| `compile-full` | — | Whole workspace. Output can be huge (#8253): prefer `compile-module`. |

### Tests

| Tool | Params | Notes |
|---|---|---|
| `test` | `testClass`* (FQN), `testFile`, `testName`, `verbose` | Runs one suite, or one test with `testName`. Works with munit, ScalaTest, specs2, utest and weaver through BSP. Pass `testFile` when the class name is ambiguous. |

### Search and inspect

| Tool | Params | Notes |
|---|---|---|
| `glob-search` | `query`* | **Unqualified** name only (`UserRepo`, not `com.acme.UserRepo`). `*` and `?` match literally. Case-insensitive, matches at word boundaries (`Repo` finds `UserRepo`). Searches all modules and dependencies. Capped at 100 results. |
| `typed-glob-search` | `query`*, `symbolType`* (`package` `class` `object` `function` `method` `trait`) | Same matching, filtered by kind. |
| `inspect` | `fqcn`*, `fileInFocus`, `module`, `searchAllTargets` | Members and signatures of a type or object. **Always pass `fileInFocus`** (any file in the right module). Without it, `inspect` may return empty members (#8880). |
| `get-docs` | `fqcn`*, `fileInFocus`, `module` | Scaladoc for project *and* dependency symbols (uses source jars). |
| `get-source` | `fqcn`*, `fileInFocus`, `module`, `detailed` | Source of a symbol, including from dependency source jars. `detailed=false` replaces bodies with `???`. **This works for Scala 2.13 dependencies, while Cellar M13's `get-source` does not.** |
| `get-usages` | `fqcn`*, `fileInFocus`, `module` | References across the workspace. Needs a compiled, indexed workspace. |

### Dependencies

| Tool | Params | Notes |
|---|---|---|
| `find-dep` | `organization`*, `name`, `version` (prefix or `latest`), `fileInFocus` | Version and artifact discovery. For 2.13 artifacts use the full name, e.g. `name: "circe-core_2.13"`. Results for sbt plugins can be wrong (#8251); cross-check with `cs complete-dep org:name_2.12_1.0:`. |

### Formatting and refactoring

| Tool | Params | Notes |
|---|---|---|
| `format-file` | 1.6.9: `fileInFocus` (one file per call). Newer versions: `files` (array), `all` (bool) | scalafmt using the project's `.scalafmt.conf`. Returns `<path> was formatted`. In 1.6.9, passing `files` fails with `Missing fileInFocus and failed to infer it`: call it once per changed file. Check the schema in `tools/list` if unsure. |
| `list-scalafix-rules` | — | Built-in rules, project rules, and generated rules in `.metals/rules`. |
| `run-scalafix-rule` | `ruleName`*, `fileToRunOn` | e.g. `RemoveUnused`, `OrganizeImports`, `ProcedureSyntax`, `ExplicitResultTypes`. |
| `generate-scalafix-rule` | `ruleImplementation`*, `description`*, `targets`, `sampleCode`, `fileToRunOn` | Write a one-off semantic rule for a mechanical, repo-wide rewrite. Write the rule for Scala 2.13 input (set the scalameta dialect accordingly). |

There are **no** rename or edit tools: edit files with normal file tools, then run `compile-file`.

## Recommended sequences

**Orient:** `list-modules` → `glob-search` / `typed-glob-search` → `inspect` (with `fileInFocus`) → `get-docs`.

**Change code:**
1. `get-usages` on anything whose signature you change.
2. Edit.
3. `compile-file` on each edited file.
4. `compile-module <x>-test` (or the test target name from `list-modules`).
5. `test` for the affected suites.
6. `format-file` for each edited file.

**Change the build:** edit `build.sbt` → `import-build` → wait → `compile-module`.
Look up dependency versions with `find-dep` or `cellar deps` before writing them.

## Scala 2.13 specifics

- Cross-built projects (`crossScalaVersions := Seq("2.13.x", "2.12.x")`): Metals imports one
  Scala version per target. If `list-modules` shows both, pass `module` explicitly.
- `-Xsource:3`: Metals compiles with the project's flags, so diagnostics already reflect it.
- Compiler plugins (kind-projector, better-monadic-for, macro paradise for 2.13 via `-Ymacro-annotations`)
  work through Bloop. If macro-generated members are missing from `inspect`, compile first.
- SemanticDB is generated on compile. Right after `import-build`, an empty `get-usages` or `glob-search`
  means "not indexed yet", not "no results". Run `compile-module` and retry.

## Observed behavior (verified with metals-mcp 1.6.9, Bloop, sbt 1.11.7, Scala 2.13.18, JDK 25, 2026-10-17)

- **Startup**: the HTTP endpoint answers within seconds. Metals then runs `sbt bloopInstall` itself
  (and writes `project/metals.sbt`), so the first tool calls wait for the import. `--client claude`
  wrote `.mcp.json` as documented.
- **`list-modules`** shows sbt projects plus `-test` targets and meta-build targets
  (`<root>-build`, `<root>-build-build`). Use `core` / `core-test` for the module parameters.
- **`compile-file`** reports errors with **0-based** positions (`L6:C51` is line 7 of the file).
  Warnings promoted by `-Werror` appear as `[Error]` (e.g. `Unused import`).
- **`test`**: suite and single-test (`testName`) runs work with munit. The very first call (which
  compiled the test target) returned an empty result once; just call it again.
- **`glob-search`**: a qualified query (`demo.UserService`) returns `No symbols found.`. Results mix in
  JDK and dependency classes, with project classes listed first.
- **`inspect`** with only `module` (no `fileInFocus`) worked here. Bug #8880 didn't reproduce, but
  passing `fileInFocus` is cheap, so keep doing it.
- **`get-docs`** on a method FQN (`cats.data.NonEmptyList.fromList`) returned the *class* Scaladoc.
  For member docs, use `get-source` (Scaladoc comments are included) or Cellar on newer releases.
- **`get-source`** on a 2.13 dependency (`cats.data.NonEmptyList`) returned the real source with Scaladoc.
  This is the replacement for Cellar M13's missing Scala 2 `get-source`.
- **`find-dep`** with `version: "latest"` returned a **pre-release** (`circe-core_2.13` → `0.15.0-M1`).
  Pick a stable version yourself: list them with `cs complete-dep io.circe:circe-core_2.13:`.
- **`import-build`** answered `Reconnected to build server`.

## Gotchas and workarounds

| Problem | Workaround |
|---|---|
| `inspect` returns no members (#8880) | Pass `fileInFocus` with any `.scala` file of the target module. |
| Startup hangs ~2 min, then dies, on JDK 17+ with `.java` files (#8812) | Launcher misses `--add-exports=jdk.compiler/...`. Start with `JAVA_OPTS`/`-J` flags (see troubleshooting.md), or use editor-mode Metals. |
| Calls hang after the Metals server restarted (#7674) | Reconnect: `/mcp` → reconnect `metals`, or restart the Claude Code session. |
| Stale diagnostics after the agent edited files (#7662) | Always call `compile-file` explicitly after writing; don't rely on pushed diagnostics. |
| Port changed, `.mcp.json` stale | Use a fixed `--port` (`scripts/start-metals-mcp.sh`). |
| One workspace per server (#8935) | Start one server per repository, each with its own port and server name. |
| `compile-full` floods the context | Use `compile-module` per target. |
