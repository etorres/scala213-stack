# Cellar on Scala 2.13 + sbt

Cellar prints the public API of any JVM dependency (signatures, members, docs) as Markdown.
Use it **before** calling an unfamiliar library method. Never guess signatures, and don't unzip jars.

If the upstream `cellar` plugin/skill is installed, follow it for general command syntax.
This file adds the Scala 2.13 / sbt layer.

## Pre-flight

```bash
cellar --version            # 0.1.0-M13 is the latest release as of 2026-10-17
cellar telemetry status     # if undecided, every command returns a JSON consent prompt instead of output
```

If you get the consent JSON (`"status": "needs_input"`), stop and ask the user which option
they want (AskUserQuestion with the four options it lists). Never choose for them.

## Which mode?

| Situation | Command |
|---|---|
| Library is already a dependency of the project. You want the **exact resolved version** | `cellar get --module <sbtProject> <fqn>` |
| Test-only dependency (munit, scalatest, testcontainers...) | `cellar get --module <sbtProject> --test <fqn>` |
| Library not yet added, or comparing versions | `cellar get-external <group>:<artifact>_2.13:<version> <fqn>` |
| Java library | `cellar get-external <group>:<artifact>:<version> <fqn>` (no suffix) |
| sbt plugin API | `cellar get-external <group>:<artifact>_2.12_1.0:<version> <fqn>` |

- `--module` is **required** with sbt. It is the sbt project id (as in `sbt projects`), not the
  directory name. Metals `list-modules` shows the same names.
- Project mode extracts `<module>/Compile/fullClasspath` (or `Test/` with `--test`) by running sbt.
  The first call is slow; later calls are cached. Use `--no-cache` after changing dependencies.
- With `.cellar/cellar.conf` → `sbt.extra-args = "--client"`, Cellar reuses the running sbt server.

## Coordinates for Scala 2.13

- Always write the full binary suffix: `org.typelevel:cats-core_2.13:2.10.0`.
  The `::` shorthand is **not** supported, and `%%` is an sbt concept, not a Cellar one.
- `latest` works as a version: `cellar get-external io.circe:circe-core_2.13:latest io.circe.Decoder`.
- The suffix selects the Scala 2 pickles. `_3` gives you the Scala 3 API, which may differ
  (givens vs implicits, extension methods vs implicit classes). **Never look up `_3` for a 2.13 project.**

## Workflow

1. Don't know the package → `cellar search[-external] ... <substring>`
2. Know the package → `cellar list[-external] ... <package>` (`-l 200` to raise the 50-result cap)
3. Know the type → `cellar get[-external] --hide-inherited ... <fqn>`
4. Need the implementation → see "Sources" below.
5. Need the dependency tree → `cellar deps <coordinate>`. `cellar meta <coordinate>` prints POM info (license, SCM).

Use `--hide-inherited` by default: Scala 2 collection-like types inherit hundreds of members.
Use `--group-inherited` when you need to know which trait a method comes from.

## What Scala 2 output looks like (M13)

Verified with `cellar get-external --hide-inherited org.typelevel:cats-core_2.13:2.10.0 cats.data.NonEmptyList`:

```scala
class NonEmptyList[+A] extends NonEmptyCollection[A, List, NonEmptyList] with Product with Serializable
def map[B](f: A => B): NonEmptyList[B] // [Scala 2 — limited type information]
def toNem[T, U](implicit ev: A <:< (T, U), order: Order[T]): NonEmptyMap[T, U] // [Scala 2 — limited type information]
```

How to read it:

- **Signatures are accurate.** The study in PR #146 found 95% identical to TASTy and no lost types.
  Implicit parameter lists, variance, bounds and higher-kinded types are all present.
- The `// [Scala 2 — limited type information]` suffix is noise. Ignore it.
- **No Scaladoc** and default arguments print as `= ...` in M13. Use Metals `get-docs` for docs.
- `<init>` lines are constructors.
- **Known gaps:** sealed traits don't list their subtypes (use `cellar list` on the package, or
  Metals `get-source`). Case classes show synthetic members (`productElementNames`, `copy$default$1`).
  Methods of implicit classes (syntax enrichments such as `cats.syntax.all._`) can be missing. For
  those, look up the `*Ops` class in the syntax package, or use Metals `inspect`/`get-source`.

Newer Cellar builds (after M13) add Scaladoc, default values and `get-source` for Scala 2, and drop
the marker. Check `cellar --version` before assuming either behavior.

## Sources (implementation, scaladoc)

`cellar get-source` on a 2.13 artifact in M13 fails with
`No source position for '...'. Only Scala 3 (TASTy) and Java symbols are supported.`
Fallbacks, in order:

1. Metals `get-source` (`fqcn`, `fileInFocus`, `detailed: true`), if the library is a project dependency.
2. Coursier source jar, without unpacking to disk:
   ```bash
   jar=$(cs fetch --sources --intransitive org.typelevel:cats-core_2.13:2.10.0 2>/dev/null | grep sources)
   unzip -l "$jar" | grep NonEmptyList
   unzip -p "$jar" cats/data/NonEmptyList.scala | sed -n '1,120p'
   ```

## Cellar or Metals?

| Need | Use |
|---|---|
| API of a dependency (in the build or not) | Cellar |
| API of the project's own code | Metals `inspect` / `get-docs` |
| Scaladoc of a 2.13 dependency | Metals `get-docs` (Cellar M13 has none) |
| Source of a 2.13 dependency | Metals `get-source`, or the source jar |
| Which versions exist | Metals `find-dep`, or `cellar get-external ...:latest` |
| Transitive deps of a coordinate | `cellar deps` |
| References, compile, test | Metals |

## Errors

- `--module is required` → add `--module <sbtProject>`.
- Symbol not found: check the FQN (package objects are `pkg.package`; companion objects use the same
  FQN as the class), and check that the `_2.13` artifact actually contains it (`cellar list`).
- sbt failures in project mode → run with `--debug`, and make sure `sbt <module>/fullClasspath` works.
- Corporate proxy: Coursier proxy settings are not respected (#176). Use a `-r` mirror URL.
