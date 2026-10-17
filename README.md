# scala213-stack

A Claude Code plugin for agentic development on **Scala 2.13 + sbt 1.x** projects. It takes three
tools from the [VirtusLab Scala Stack](https://vss.virtuslab.com/), whose docs assume Scala 3, sbt 2
and scala-cli, and adapts them to Scala 2.13:

| Tool | What the skill uses it for |
|---|---|
| [Metals MCP](https://scalameta.org/metals/docs/features/mcp) | compile after each edit, run single tests, symbol search, `inspect`, find usages, docs/source of dependencies, scalafmt, scalafix, `find-dep` |
| [Cellar](https://github.com/VirtusLab/cellar) | look up the real API of `_2.13` dependencies (project classpath via sbt, or any Maven coordinate) |
| [Orca](https://github.com/VirtusLab/orca) | delegate plan → code → multi-reviewer → PR flows, with pinned sbt gates and Scala 2.13 reviewers in place of the built-in Scala 3/Ox one |

The skill also covers a stack-agnostic sbt dev loop (sbt client, 2.13 compiler flags, scalafmt,
scalafix, adding dependencies, definition of done). It does not prescribe libraries or an effect
system: agents follow whatever the project already uses.

## Install

```
/plugin marketplace add etorres/scala213-stack
/plugin install scala213-stack@scala213-stack
```

Or copy `skills/scala213-stack/` into `~/.claude/skills/` or `<project>/.claude/skills/`.

Then follow [setup.md](skills/scala213-stack/references/setup.md) to install the tools.

### Running the scripts and copying templates

The easiest way is to ask Claude from your sbt project, e.g. *"run the scala213-stack doctor"* or
*"start the Metals MCP server with the scala213-stack script"*. Once the skill is loaded, Claude knows
its own folder, so you don't need any paths.

To run them yourself, find the skill folder first. A plugin install lives in Claude Code's plugin
cache, under a versioned folder (`.../scala213-stack/<version>/...`). This lookup always picks the
newest installed version:

```bash
S=$(ls -d ~/.claude/plugins/cache/scala213-stack/scala213-stack/*/skills/scala213-stack | sort -V | tail -n 1)
```

If you copied the skill manually instead, use that folder:
`S=~/.claude/skills/scala213-stack` or `S=<project>/.claude/skills/scala213-stack`.

Then, from the sbt project root:

```bash
"$S/scripts/doctor.sh"              # read-only check of tools + project config
"$S/scripts/start-metals-mcp.sh"    # in a separate terminal: Metals MCP on port 7333, writes .mcp.json
mkdir -p .cellar && cp "$S/templates/cellar.conf" .cellar/cellar.conf   # optional templates, see setup.md
```

`~/.claude/plugins/marketplaces/scala213-stack/` also exists. It is Claude Code's clone of this repo, used
to check for updates. Use the cache folder above, which is the copy that is actually installed.

### Optional companion plugins

- `virtuslab/cellar`: `/plugin marketplace add virtuslab/cellar` then `/plugin install cellar@virtuslab-cellar`.
  This plugin's Scala 2.13 rules take precedence over it.
- `VirtusLab/orca`: `/plugin marketplace add VirtusLab/orca` then `/plugin install orca@orca-skills`, for `/orca`.
  Install it after the `orca` CLI, a sandbox, and this skill's `.orca/` templates are in place.

## Layout

```
.claude-plugin/             plugin + marketplace manifests
skills/scala213-stack/
  SKILL.md                  entry point: orientation, tool routing, core loop, 2.13 rules
  references/               metals-mcp, cellar, orca, sbt-workflow, setup, troubleshooting
  templates/                .mcp.json (http/stdio), cellar.conf, plugins.sbt snippet,
                            .orca/settings.properties, .orca/reviewers/{scala-fp,sbt-build}.md,
                            CLAUDE.md snippet
  scripts/                  doctor.sh (read-only checks), start-metals-mcp.sh
```

## Version notes (2026-10-17)

- Metals MCP 1.6.9: tested end to end on a 2.13 project with Bloop (see metals-mcp.md, "Observed behavior"). 2.0.0-RC1 available.
- Cellar 0.1.0-M13: Scala 2 lookups give signatures only. Scaladoc, default values and `get-source`
  for Scala 2 are on Cellar's `main` branch and will arrive in the next release.
- Orca 0.2.0: tested on a 2.13 project; the `scala-fp` override replaces the built-in reviewer (see orca.md, "Observed behavior")

## License

Apache-2.0. See [LICENSE](LICENSE).
