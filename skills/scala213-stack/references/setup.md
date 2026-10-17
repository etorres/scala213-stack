# One-time setup (Scala 2.13 + sbt 1.x)

> Versions checked 2026-10-17: Metals MCP 1.6.9 (2.0.0-RC1 available), Cellar 0.1.0-M13,
> Orca 0.2.0, sbt-bloop 2.1.2, sbt 1.13.0, Scala 2.13.18. Run `scripts/doctor.sh` to see what
> is actually installed. Never install or upgrade tools without asking the user first.

Paths: `scripts/...` and `templates/...` are relative to the skill folder. Claude knows that folder
once the skill is loaded. In a terminal, set `$S` to it first. For a plugin install:
`S=$(ls -d ~/.claude/plugins/cache/scala213-stack/scala213-stack/*/skills/scala213-stack | sort -V | tail -n 1)`.
Run every command from the sbt project root.

## 0. Prerequisites

- JDK 17+ (JDK 21 recommended; Orca runs its own JVM 21 through scala-cli).
- Coursier (`cs`), sbt 1.x, git. Optional: `gh` (for Orca PRs), scala-cli (installed by Orca if missing).

```bash
cs setup            # if Coursier itself is missing: https://get-coursier.io
```

## 1. Metals MCP (standalone, no editor needed)

```bash
cs install metals-mcp          # installs the latest stable launcher
metals-mcp --version
```

Bloop is the default build server for sbt. Make sure the project can export to Bloop:

```scala
// project/plugins.sbt (Metals adds this automatically in most setups, add it if it doesn't)
addSbtPlugin("ch.epfl.scala" % "sbt-bloop" % "2.1.2")
```

```bash
sbt -Dbloop.export-jar-classifiers=sources bloopInstall   # optional: lets Metals do it on import-build
```

Start the server from the project root with a **fixed port**, so `.mcp.json` stays valid across restarts:

```bash
scripts/start-metals-mcp.sh                 # = metals-mcp --workspace "$PWD" --port 7333 --client claude
```

`--client claude` writes `./.mcp.json`:

```json
{ "mcpServers": { "metals": { "type": "http", "url": "http://localhost:7333/mcp" } } }
```

Alternatives:

- Register by hand: `claude mcp add --transport http metals http://localhost:7333/mcp`
- stdio (Claude Code starts and stops the server itself, so no port to manage): copy `templates/mcp.stdio.json`.
  The cost is a cold start (build import) on every new session.
- Editor mode (VS Code + Metals): set `"metals.startMcpServer": true`. The port is in
  `.metals/mcp.json` and changes between restarts:
  `claude mcp add --transport http metals "http://localhost:$(grep -oE 'localhost:[0-9]+' .metals/mcp.json | head -n1 | sed 's/.*://')/mcp"`

Use **sbt BSP** instead of Bloop only if the project cannot use Bloop (for example, custom tasks
generate sources that Bloop doesn't see): start with `metals-mcp --workspace . --default-bsp-to-build-tool ...`.

Add the server's working files to `.gitignore`: `.metals/`, `.bloop/`, `.bsp/`, `project/metals.sbt`, `project/project/`.
Commit `.mcp.json` only if the team agrees on the fixed port.

## 2. Cellar

```bash
cs install --contrib cellar
cellar --version
cellar telemetry status                 # MUST be decided before agent use
```

If no telemetry choice is recorded, every cellar command prints a JSON consent request instead of
running. Ask the user which option they want (`cellar telemetry enable|disable [--global]`).
Never pick one on their behalf.

Speed up project-aware mode by reusing a running sbt server. Copy `templates/cellar.conf` to `.cellar/cellar.conf`:

```hocon
sbt.extra-args = "--client"
```

Private repositories: Cellar reads Coursier credentials (`~/.config/coursier/credentials.properties`
or `COURSIER_CREDENTIALS`). Extra repositories go in `maven.repositories` or `-r <url>`.

**Version note:** 0.1.0-M13 (the latest release as of 2026-10-17) gives *signatures only* for Scala 2.
Scaladoc, default values and `get-source` for 2.13 artifacts arrived on `main` after M13.
Run `cs update cellar` when a newer release is out.

## 3. Orca

```bash
curl -fsSL https://raw.githubusercontent.com/VirtusLab/orca/master/install.sh | bash   # -> ~/.local/bin/orca
orca --help
```

Orca drives the agent CLIs (`claude`, `codex`, ...) with full tool access and auto-approve.
**Run it in a sandbox** (Sandcat, Docker, or a VM) for anything beyond `review.sc`.

Per project, copy the templates:

```bash
mkdir -p .orca/reviewers
cp "$S/templates/orca/settings.properties"   .orca/settings.properties
cp "$S/templates/orca/reviewers/"*.md         .orca/reviewers/
```

Optional: the upstream Claude Code skill (`/orca`):

```
/plugin marketplace add VirtusLab/orca
/plugin install orca@orca-skills
```

## 4. Project-level CLAUDE.md

Append `templates/CLAUDE.md.snippet` to the project's `CLAUDE.md`. It uses "if available"
phrasing, so it also works in headless Orca runs where nobody can answer questions.

## 5. Verify

```bash
scripts/doctor.sh
```

Then in Claude Code: `/mcp` should list `metals` as connected, and the `list-modules` tool should
return the sbt projects.
