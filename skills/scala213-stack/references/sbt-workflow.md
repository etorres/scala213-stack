# sbt 1.x dev loop for Scala 2.13 (stack-agnostic)

These commands are the fallback when Metals MCP is unavailable, and the final check before
finishing a task. The skill does not prescribe libraries or an effect system: follow whatever the
project already uses.

## Ground rules

- **Read the build before changing code:** `build.sbt`, `project/*.sbt`, `project/*.scala`,
  `project/build.properties`, `.scalafmt.conf`, `.scalafix.conf`.
- **Don't change** `scalaVersion`, `scalacOptions`, plugin versions or dependency versions unless the
  task requires it. If it does, say so explicitly in your summary.
- **No warnings introduced.** Many 2.13 builds use `-Xfatal-warnings`/`-Werror`, and new warnings
  fail CI.
- Never use `~` (watch mode) or interactive `console` from an agent; they never return.

## Avoid cold starts

Each `sbt <cmd>` starts a JVM and loads the build (10–60 s). Prefer a running server:

```bash
sbt --client "core/Test/compile"      # starts a server the first time, reuses it afterwards (also: sbtn)
sbt --client shutdown                 # when done
```

If `--client` misbehaves (old sbt, or custom launchers), batch commands into one invocation:
`sbt "core/Test/compile; core/testOnly com.acme.FooSpec"`.

## Everyday commands

| Goal | Command |
|---|---|
| List projects | `sbt projects` |
| Compile main + test sources of one module (no tests run) | `sbt core/Test/compile` |
| Run one suite | `sbt "core/testOnly com.acme.FooSpec"` |
| Run one test (munit) | `sbt "core/testOnly com.acme.FooSuite -- --tests=name"` (glob also works: `-- *name*`) |
| Run one test (ScalaTest) | `sbt "core/testOnly com.acme.FooSpec -- -z \"test name\""` |
| Run one test (weaver / utest / zio-test) | weaver: `-- -o "name"`; utest: `sbt "core/testOnly -- com.acme.FooTests.name"`; zio-test: `-- -t "name"` |
| Run one test (specs2) | `sbt "core/testOnly com.acme.FooSpec -- ex 'name'"` |
| Re-run failed/changed tests | `sbt core/testQuick` |
| All tests | `sbt test` (can be slow: scope to modules first) |
| Integration tests (if configured) | `sbt core/IntegrationTest/test`, or a dedicated `it` project in newer builds |
| After editing the build | `sbt reload` (server), then Metals `import-build` |
| Show a setting | `sbt "show core/scalacOptions"`, `sbt "show core/libraryDependencies"` |
| Dependency tree / evictions | `sbt core/dependencyTree` (sbt ≥ 1.4 built-in), `sbt core/evicted` |
| Format | `sbt scalafmtAll scalafmtSbt`; check only: `sbt scalafmtCheckAll scalafmtSbtCheck` |
| Lint / rewrite | `sbt "scalafixAll --check"`, `sbt "core/scalafix RemoveUnused"` |
| Cross-build | `sbt +test`, or `sbt "++2.13.18 core/test"` |

## Scala 2.13 compiler flags you will meet

Recognize these flags; don't add or remove them on your own:

| Flag | Meaning |
|---|---|
| `-Xlint` / `-Xlint:_` | Bundle of lint warnings (adapted args, infer-any, ...). |
| `-Wunused:imports,privates,locals,implicits,explicits,params,patvars` | Unused warnings. Scala 2.13 spelling; Scala 3 uses `-Wunused:all`. |
| `-Wvalue-discard`, `-Wdead-code`, `-Wnumeric-widen` | Common extra warnings. |
| `-Werror` / `-Xfatal-warnings` | Warnings fail the build. |
| `-Wconf:...` | Per-category/per-file warning configuration. Read it before "fixing" a warning by suppression. |
| `-Xsource:3` (+ `-Xsource-features:...` on 2.13.13+) | Scala 3 migration mode: some Scala 3 syntax is accepted (e.g. `import x.*`, `?` wildcards in types, `import a.{b as c}`) and some semantics change (`-Xsource:3-cross` adopts more of them). **Only use Scala 3 syntax if the project already has this flag.** |
| `-Ymacro-annotations` | Replaces macro paradise on 2.13 (simulacrum, newtype, derevo, ...). |
| `-P:kind-projector:...` / `addCompilerPlugin(...)` | Compiler plugins: kind-projector (`*` / `?` syntax), better-monadic-for. |

sbt-tpolecat (`org.typelevel % sbt-tpolecat`) is a common way to manage these flags. It's fine
when present; don't add it unasked. Its modes (`tpolecatDevMode`, `tpolecatCiMode`,
`tpolecatReleaseMode`) change how strict the flags are, so check `tpolecatDefaultOptionsMode`
when CI fails but local compilation passes.

## scalafmt for 2.13

`.scalafmt.conf` should declare the dialect:

```hocon
version = "3.x.y"            # keep whatever the project pins
runner.dialect = scala213    # or scala213source3 when the build uses -Xsource:3
```

If the file is missing, don't create one unasked, and don't format files the task doesn't touch.
Format only the files you changed: Metals `format-file` (one `fileInFocus` per call in 1.6.9; `files: [...]` in newer versions), or the scalafmt CLI on those paths.

## scalafix for 2.13

Semantic rules need SemanticDB:

```scala
ThisBuild / semanticdbEnabled := true
ThisBuild / semanticdbVersion := scalafixSemanticdb.revision
```

- `RemoveUnused` also needs `-Wunused:...` enabled. `OrganizeImports` is built in since scalafix 0.11.
- Use Metals `run-scalafix-rule` for one file, and `sbt "scalafixAll RuleName"` for the repo.

## Adding a dependency

1. Find the coordinate and version: Metals `find-dep` (`organization`, `name: "<artifact>_2.13"`,
   `version: "latest"`), or `cellar get-external <g>:<a>_2.13:latest <some.Fqn>`.
2. Check that the API you need exists in that version: `cellar get-external <g>:<a>_2.13:<v> <fqn>`.
3. Add it with `%%` for Scala libraries and `%` for Java libraries, and the correct scope (`% Test`).
   Follow the build's conventions (a `Dependencies.scala` object, version vals, and so on).
4. `sbt reload`, Metals `import-build`, then `compile-module`.
5. Check evictions: `sbt core/evicted`. Look especially for binary-incompatible bumps of
   cats, circe, akka/pekko or scala-collection-compat.
6. Mention the new dependency (and any eviction) in your summary.

## Definition of done

1. `sbt <affected modules>/Test/compile` passes with no new warnings.
2. The affected tests pass (targeted `testOnly`, then the module's `test` if feasible).
3. Changed files are formatted (`scalafmtCheckAll` clean for those files).
4. If the build changed, Metals `import-build` succeeded.
