# Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `/mcp` shows `metals` failed / not connected | Server not running, or wrong port | Run `scripts/start-metals-mcp.sh` in another terminal (or in the background) and check that `.mcp.json` has the same port. `curl -s -o /dev/null -w '%{http_code}' http://localhost:7333/mcp` should answer (any HTTP code). |
| Metals tools hang after the server restarted | MCP client lost its session (#7674) | Reconnect `metals` in `/mcp`, or restart the Claude Code session. |
| `metals-mcp` startup blocks ~2 min, then exits | Waiting for BSP. On JDK 17+ with `.java` files, the launcher lacks `--add-exports` (#8812) | Check the server output for BSP errors. Try `sbt bloopInstall` first. For the JDK issue, run it on a JVM with the exports, e.g. `JAVA_OPTS="--add-exports=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED --add-exports=jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED" metals-mcp ...` (if the launcher honors `JAVA_OPTS`), or use editor-mode Metals. |
| `import-build` fails | sbt can't load the build, or Bloop export failed | Run `sbt projects` to see the sbt error. Fix the build, then run `import-build` again. Check that `project/metals.sbt` / sbt-bloop is not pinned to an incompatible version. |
| `list-modules` empty | Build not imported yet | `import-build`, wait, retry. |
| `inspect` returns no members | Missing `fileInFocus` (#8880) | Pass `fileInFocus` with a file from the right module. |
| `get-usages` / `glob-search` empty for code that clearly exists | Not compiled or indexed yet (SemanticDB) | `compile-module`, then retry. Check that the build doesn't disable semanticdb (`semanticdbEnabled := false`). |
| `compile-file` shows old errors | Stale diagnostics after an external edit (#7662) | Call `compile-file` again. If still wrong, run `compile-module`. |
| Tests not found by `test` | Wrong FQN, or the test target isn't compiled | Use the FQN of the suite class. Run `compile-module` on the test target. Fallback: `sbt "proj/testOnly FQN"`. |
| Cellar prints a JSON `needs_input` consent prompt | Telemetry choice not recorded | Ask the user, then run the `cellar telemetry ...` command they pick. |
| `cellar get` says `--module is required` | sbt project needs a module | `--module <sbt project id>` (from `sbt projects` / `list-modules`). |
| `cellar get` symbol not found but code compiles | Wrong scope, stale cache, or package object | `--test` for test deps, `--no-cache` after build changes, `pkg.package` for package-object members. |
| `cellar get-source` fails on 2.13 artifact | Cellar ≤ M13 only supports TASTy/Java sources | Metals `get-source`, or `cs fetch --sources --intransitive <coord>` + `unzip -p`. |
| Cellar output has `= ...` defaults and no docs | Scala 2 on Cellar ≤ M13 | Metals `get-docs`; upgrade Cellar when a newer release exists. |
| Cellar lookup slow every time in project mode | New sbt JVM per call | `.cellar/cellar.conf` → `sbt.extra-args = "--client"` with an sbt server running. |
| Orca reviewers suggest opaque types / braceless syntax / Ox | Built-in Scala 3 `scala-fp` reviewer is active | Add `.orca/reviewers/scala-fp.md` from `templates/orca/reviewers/`. |
| Orca auto-discovered wrong gate commands | No `.orca/settings.properties` | Copy `templates/orca/settings.properties` and adjust. |
| Orca: `cannot skip branch creation: 'main' is a protected branch` | `--skip-branch` on a protected branch | Check out a feature branch first, or drop `--skip-branch`. |
| Orca `review.sc` left new commits on my branch | Review flows commit the uncommitted work they're given, plus stage/progress commits | Review committed ranges (`git diff main...HEAD`), or let Orca create its own branch. Undo with `git reset --soft <base>` if wanted. |
| Orca: `[claude-code:unrecognized_model] {"model":"claude-haiku-..."}` | Installed `claude` CLI doesn't know Orca's helper model id | Harmless (Orca falls back). Upgrade the `claude` CLI, or pin roles in `.orca/settings.properties`. |
| `orca: command not found` right after installing | `~/.local/bin` not on PATH in the current shell | Open a new shell, or call `~/.local/bin/orca`. |
| Orca reviewers can't use Metals | Read-only roles need allowed MCP tools | The user opts in with the `permissions.allow` snippet in `orca.md`. |
| `sbt --client` hangs or errors | Stale server socket, or an old sbt | `sbt --client shutdown`, or delete `project/target/active.json`. Otherwise use plain `sbt "cmd1; cmd2"`. |
| CI fails with warnings that local compile doesn't show | tpolecat mode or `-Wconf` differ between CI and local | `sbt "show core/scalacOptions"` with the CI env (`SBT_TPOLECAT_CI=1`). |
