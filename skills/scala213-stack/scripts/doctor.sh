#!/bin/sh
# Read-only environment and project check for the scala213-stack skill.
# Installs nothing and changes nothing. Run it from the sbt project root (or pass the path as $1).
#
# Output lines: "ok", "warn" (works, but degraded) or "miss" (needed by part of the skill).
set -u

project=${1:-$PWD}
port=${METALS_MCP_PORT:-7333}

ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  warn  %s\n' "$*"; }
miss() { printf '  miss  %s\n' "$*"; }
has()  { command -v "$1" >/dev/null 2>&1; }

echo "== Tools"

if has java; then
  ok "java: $(java -version 2>&1 | head -n 1)"
else
  miss "java (JDK 17+ required)"
fi

if has cs; then ok "coursier: $(cs version 2>/dev/null | head -n 1)"; else miss "coursier (cs): https://get-coursier.io"; fi
if has sbt; then ok "sbt launcher: $(command -v sbt)"; else miss "sbt"; fi

if has metals-mcp; then
  ok "metals-mcp: $(command -v metals-mcp)"
else
  miss "metals-mcp: cs install metals-mcp"
fi

if has cellar; then
  cv=$(cellar --version 2>/dev/null | head -n 1)
  ok "cellar: $cv"
  case "$cv" in
    0.1.0-M[0-9]\ *|0.1.0-M1[0-3]\ *)
      warn "cellar <= M13: Scala 2 gives signatures only (no Scaladoc/defaults, get-source unsupported). Use Metals get-docs/get-source." ;;
  esac
  ts=$(cellar telemetry status 2>/dev/null | head -n 1)
  case "$ts" in
    *enabled*|*disabled*) ok "cellar $ts" ;;
    *) warn "cellar telemetry not decided: commands will return a consent prompt. Ask the user, then run 'cellar telemetry enable|disable [--global]'." ;;
  esac
else
  miss "cellar: cs install --contrib cellar"
fi

if has orca; then ok "orca: $(command -v orca)"; else warn "orca not installed (optional): see references/setup.md"; fi
if has scala-cli; then ok "scala-cli: $(command -v scala-cli)"; else warn "scala-cli not installed (Orca installs it on first run)"; fi
if has gh; then ok "gh: $(command -v gh)"; else warn "gh not installed (only needed for Orca PRs/issues)"; fi

echo
echo "== Project: $project"

if [ ! -f "$project/build.sbt" ]; then
  miss "build.sbt not found: not an sbt project root"
  exit 0
fi
ok "build.sbt"

if [ -f "$project/project/build.properties" ]; then
  sv=$(sed -n 's/^[[:space:]]*sbt\.version[[:space:]]*=[[:space:]]*//p' "$project/project/build.properties" | tr -d '[:space:]')
  case "$sv" in
    1.*) ok "sbt.version=$sv" ;;
    2.*) warn "sbt.version=$sv: sbt 2 builds are Scala 3; this skill targets sbt 1.x" ;;
    *)   warn "sbt.version not readable in project/build.properties" ;;
  esac
else
  warn "project/build.properties missing (sbt version not pinned)"
fi

build_files=$(find "$project" -maxdepth 2 \( -name '*.sbt' -o -path "$project/project/*.scala" \) -not -path '*/target/*' 2>/dev/null)

# shellcheck disable=SC2086
scala_versions=$(grep -hiE 'scala(Version|2|3|_?2_?1[23]|Versions)' $build_files 2>/dev/null \
  | grep -oE '"(2\.1[0-3]|3)\.[0-9]+(\.[0-9]+)?[^"]*"' | tr -d '"' | sort -u | tr '\n' ' ')
case "$scala_versions" in
  *2.13.*) ok "Scala versions referenced in build: $scala_versions" ;;
  "")      warn "no Scala version literal found (may come from a plugin or variable)" ;;
  *)       warn "Scala versions referenced in build: $scala_versions (no 2.13.x found)" ;;
esac

# shellcheck disable=SC2086
if grep -qE -- '-Xsource:3' $build_files 2>/dev/null; then
  warn "-Xsource:3 enabled: some Scala 3 syntax is accepted; match the existing code style"
fi

plugins_file="$project/project/plugins.sbt"
for p in sbt-bloop sbt-scalafmt sbt-scalafix sbt-tpolecat; do
  if grep -qs "$p" "$plugins_file" "$project/project/metals.sbt"; then
    ok "plugin $p"
  else
    case "$p" in
      sbt-bloop)    warn "sbt-bloop not declared (Metals usually injects it via project/metals.sbt on import)" ;;
      sbt-scalafmt) warn "sbt-scalafmt not declared: Orca 'format' gate and scalafmtAll unavailable" ;;
      sbt-scalafix) warn "sbt-scalafix not declared: scalafixAll unavailable (Metals scalafix tools still work)" ;;
      *)            : ;;
    esac
  fi
done

if [ -f "$project/.scalafmt.conf" ]; then
  d=$(sed -n 's/^[[:space:]]*runner\.dialect[[:space:]]*=[[:space:]]*//p' "$project/.scalafmt.conf" | tr -d '[:space:]"')
  case "$d" in
    scala213*|scala212*) ok ".scalafmt.conf dialect=$d" ;;
    "") warn ".scalafmt.conf has no runner.dialect (set scala213 or scala213source3)" ;;
    *)  warn ".scalafmt.conf dialect=$d (expected scala213 or scala213source3)" ;;
  esac
else
  warn ".scalafmt.conf missing"
fi

echo
echo "== Agent config"

if [ -f "$project/.mcp.json" ] && grep -q '"metals"' "$project/.mcp.json"; then
  mport=$(grep -oE 'localhost:[0-9]+' "$project/.mcp.json" | head -n 1 | sed 's/.*://')
  if [ -n "$mport" ]; then
    if has curl && curl -s -o /dev/null --max-time 2 "http://localhost:$mport/mcp"; then
      ok ".mcp.json metals -> port $mport (server answering)"
    else
      warn ".mcp.json metals -> port $mport, but nothing is answering: run scripts/start-metals-mcp.sh"
    fi
  else
    ok ".mcp.json metals (stdio transport)"
  fi
else
  warn ".mcp.json has no 'metals' server: run scripts/start-metals-mcp.sh (default port $port)"
fi

if [ -f "$project/.cellar/cellar.conf" ]; then ok ".cellar/cellar.conf"; else warn ".cellar/cellar.conf missing (optional: templates/cellar.conf)"; fi

if [ -d "$project/.orca" ]; then
  if [ -f "$project/.orca/settings.properties" ]; then ok ".orca/settings.properties"; else warn ".orca/settings.properties missing: Orca will auto-discover gates"; fi
  if [ -f "$project/.orca/reviewers/scala-fp.md" ]; then
    ok ".orca/reviewers/scala-fp.md (2.13 override)"
  else
    warn ".orca/reviewers/scala-fp.md missing: Orca's built-in Scala 3/Ox reviewer will run"
  fi
else
  warn ".orca/ not configured (only needed for Orca): templates/orca/"
fi

if [ -f "$project/CLAUDE.md" ] && grep -qs 'scala213-stack' "$project/CLAUDE.md"; then
  ok "CLAUDE.md mentions scala213-stack"
else
  warn "CLAUDE.md has no scala213-stack pointer (optional: templates/CLAUDE.md.snippet)"
fi

exit 0
