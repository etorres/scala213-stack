# Orca for Scala 2.13 + sbt projects

Orca (VirtusLab, 0.2.0) runs **deterministic plan → code → review → PR flows**. Separate planning,
coding and review agents run through the agent CLIs you already use (`claude`, `codex`,
`opencode`, `gemini`, `pi`). Orca owns git: each stage is a commit, and runs are resumable from
`.orca/runs/<key>.progress.json`.

Orca does not care what language the project uses. Its flow scripts are Scala 3 / scala-cli, but
they run on their own JVM, **outside** your sbt build. A Scala 2.13 project needs no changes,
only the settings and reviewer overrides below.

If the upstream `orca` plugin is installed, `/orca <prompt>` handles flow selection and background
execution. This file covers what to configure first, and how to write prompts for 2.13 work.

## When to delegate to Orca (and when not to)

Delegate:

- Well-specified features or fixes that span several files and should get independent review.
- GitHub issues: `orca run resolve.sc "owner/repo#123"`.
- Review-only passes: `git diff main...HEAD | orca run review.sc`, or `orca run review.sc "owner/repo#42"` for a PR.
  Note: `review.sc` still commits any uncommitted work it is given (see "Observed behavior" below).

Don't delegate:

- Exploratory or interactive work, or anything needing the user's decisions mid-way.
- Small edits you can make and compile in a few steps.

**Ask the user before starting any `orca run`.** Flows create branches and commits (even
`review.sc` commits uncommitted work it is given), cost real money in agent tokens, and the coding
flows run agents with full tool access and auto-approve. The docs recommend
running it in a sandbox (Sandcat, Docker or a VM).

## Built-in flows

| Flow | What it does |
|---|---|
| `quick.sc` | No planning: one task, code, then a review loop. |
| `implement.sc` (default) | Plan into tasks, review each task, final review loop, then a PR. |
| `epics.sc` | Large work: epics outline plus a critic, then tasks. |
| `resolve.sc` | Request or GitHub issue: triage, failing test first for bugs, then fix. |
| `review.sc` | Review only (stdin diff or PR reference). |

Run options: `--branch <name>`, `--skip-branch`, `--worktree` (isolated `.orca/worktrees/<key>`),
`--keep-changes`. Resume an aborted run by running the same command again, or interactively with `orca continue`.

## Project configuration (commit these)

### `.orca/settings.properties`: pin the sbt gates

Copy `templates/orca/settings.properties`. Pinning the commands stops Orca's auto-discovery from guessing:

```properties
format = sbt scalafmtAll scalafmtSbt
lint   = sbt Test/compile
test   = sbt test
```

- `lint` must type-check test sources **without running tests**. `Test/compile` does exactly that.
- The review loop runs `format` before each round and `lint` next to the reviewers. **It never runs `test`.**
  Custom flows run tests in their own stage, via `summon[FlowContext].stackSettings.test`.
- No sbt-scalafmt in the project? Remove `format`, or point it at `scalafmt` (native CLI).
- Every gate starts a new JVM. For big builds, use `sbt --client ...` while an sbt server is running,
  and keep it running for the whole Orca run.
- Agent roles: `planningAgent`, `codingAgent`, `reviewAgent` (e.g. `claude:opus`), in the project or in
  `~/.config/orca/settings.properties`.

### `.orca/reviewers/scala-fp.md`: replace the Scala 3 reviewer (required)

Orca's built-in `scala-fp` reviewer fires on every `.scala` file. It asks for opaque types,
braceless syntax and Ox, and tells reviewers to load the `direct-style-scala` skill. On a 2.13
codebase that produces wrong findings. Copy `templates/orca/reviewers/scala-fp.md`. It reviews
2.13 idioms and follows whatever effect style the project already uses.

How overriding works: a reviewer's identity is its **filename stem** (case-insensitive), and any
`name:` key is ignored. Project beats global, and global beats built-in. A shadowing file runs
only where the built-in ran (`scala-fp` is not in `minimalReviewers`). At the start of each run,
Orca prints `discovered reviewers: ... scala-fp (project, shadows built-in)`; check that line.
Every non-`_`-prefixed `.md` file in `.orca/reviewers/` must be a valid reviewer, or the run aborts.

### `.orca/reviewers/sbt-build.md`: build reviewer (recommended)

Copy `templates/orca/reviewers/sbt-build.md`. It fires only on `build.sbt` / `project/` changes, and
checks `%%` vs `%`, version pinning, scope (`% Test`), plugin compatibility and cross-build settings.
As a new name, it joins both `allReviewers` and `minimalReviewers`. Its `files:` regex keeps it
quiet on diffs that don't touch the build.

## Making Claude-backed Orca agents use this toolchain

Orca's agents are ordinary Claude Code sessions in the repo, so they load the project `CLAUDE.md`,
`.mcp.json` and installed plugins (including this skill).

- Use **"if available"** phrasing in CLAUDE.md (see `templates/CLAUDE.md.snippet`), and remove
  "ask me before X" rules: nobody can answer during a run.
- The read-only roles (planner, reviewers) can only call MCP tools that are allowed in
  `.claude/settings.json`. To let them use Metals, the user can **opt in** by adding read-only tools only:
  ```json
  {
    "permissions": {
      "allow": [
        "mcp__metals__list-modules",
        "mcp__metals__glob-search",
        "mcp__metals__typed-glob-search",
        "mcp__metals__inspect",
        "mcp__metals__get-docs",
        "mcp__metals__get-source",
        "mcp__metals__get-usages",
        "mcp__metals__find-dep"
      ]
    }
  }
  ```
  Don't edit the user's settings files yourself. Show the snippet and let them decide.
- The Metals MCP server must already be running on the fixed port before the run starts.

## Writing the Orca prompt

Orca's agents don't see this conversation. The prompt must stand on its own:

- Goal and acceptance criteria (behavior, plus the tests that must pass).
- sbt project(s) affected, key files and packages, and the spec path if there is one.
- Constraints: "Scala 2.13, sbt 1.x; do not use Scala 3 syntax; keep the existing effect style
  (<what the project uses>); do not change scalacOptions or dependency versions unless stated."
- How to verify: `sbt <proj>/Test/compile`, `sbt "<proj>/testOnly com.acme.FooSpec"`.

Example:

```bash
log=$(mktemp -t orca-run.XXXXXX)
orca run implement.sc --worktree > "$log" 2>&1 <<'ORCA_PROMPT'
Add pagination to ListingRepository.search in module `listings` (Scala 2.13, sbt 1.x).
- New signature: search(q: Query, page: Page): F[Paged[Listing]] — keep the existing F[_] style.
- Page(offset: Int, limit: Int) with limit capped at 100; put it in com.acme.listings.model.
- Update ListingRepositorySpec with tests for first page, last page, and limit capping.
Constraints: no Scala 3 syntax, no new dependencies, don't touch scalacOptions.
Verify with: sbt listings/Test/compile && sbt "listings/testOnly com.acme.listings.ListingRepositorySpec"
ORCA_PROMPT
echo "orca exit code: $?" >> "$log"
```

When it finishes, show any "Open review findings" section to the user word for word.

## Observed behavior (verified with Orca 0.2.0 on a 2.13 / sbt 1.11 project, 2026-10-17)

- **`review.sc` commits uncommitted changes.** Piping a diff of staged or unstaged work into `review.sc`
  makes Orca commit that work (an agent-written message), then add `stage:` and progress-log
  commits. With `--skip-branch`, those commits land on **your current branch**. To review work
  in progress without touching your branch, either run without `--skip-branch` (Orca creates its
  own branch), or commit first and review a range: `git diff main...HEAD | orca run review.sc`.
  Tell the user about this before running it.
- **`--skip-branch` is refused on a protected branch** such as `main`: `cannot skip branch creation: 'main' is a protected branch`.
  Check out a feature branch first, or drop the flag.
- **Override check passed**: the run printed `discovered reviewers: sbt-build (project); scala-fp (project, shadows built-in)`.
  The `scala-fp` findings used 2.13 idioms only (`extends AnyVal` value class, `sealed trait` + `case object`,
  `Either` + `filterOrElse`). No opaque types, `enum`, braceless syntax or Ox.
- **`unrecognized_model` errors for a Haiku model** (`claude-haiku-5-5`) for Orca's internal picker
  and helper roles can show up when the installed `claude` CLI doesn't know that model id. Orca
  falls back and the run still completes. Upgrade the `claude` CLI, or pin the roles in `settings.properties`.
- **Cost**: reviewing one 12-line file with the default roles (Opus, unpinned) cost about $3.20, almost all
  of it reviewer input tokens. For routine reviews, pin a cheaper `reviewAgent` (e.g. `claude:sonnet`).
