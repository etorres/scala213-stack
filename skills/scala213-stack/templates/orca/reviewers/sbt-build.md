---
description: Reviews sbt 1.x build changes for Scala 2.13 projects — dependency coordinates and scopes, version management, evictions, plugin compatibility, scalacOptions and cross-build settings.
files: (^|/)(build\.sbt|project/[^/]+\.(sbt|scala)|project/build\.properties)$
---

## Scope

Review only build-definition changes. Ignore application code.

## Aspects

- **Coordinates**: `%%` for Scala libraries (resolves `_2.13`), `%` for Java libraries and
  `%%%` only in Scala.js/Native cross projects. Never hard-code `_2.13` together with `%%`.
- **Scopes**: test-only libraries use `% Test`. Compile-time-only libraries (annotations, macros)
  use `% Provided` or `% "compile-internal"` where appropriate. No test frameworks in `Compile`.
- **Versions**: follow the existing convention (a `Dependencies.scala` object, version vals, a
  BOM). No `latest.integration`, ranges or snapshots. Modules of one library family
  (circe-*, http4s-*, akka-*, pekko-*, cats-effect-*) share a single version.
- **Binary compatibility**: new dependencies or bumps must not evict a binary-incompatible version
  of a library already in the build (cats, cats-effect, circe, akka/pekko, scala-collection-compat,
  scala-java8-compat). Ask for `sbt evicted` output when unsure. A Scala 3 artifact (`_3`) must not be
  added to a 2.13 module unless the build intentionally uses `CrossVersion.for3Use2_13` or the
  reverse, with a clear comment.
- **Plugins**: `addSbtPlugin` versions must be compatible with the sbt version in
  `project/build.properties`. Avoid duplicate or conflicting plugins (two formatters, two
  dependency-update plugins).
- **scalacOptions**: no silent removal of warnings, `-Werror`/`-Xfatal-warnings` or `-Wconf`
  rules to make a change compile. New `-Xsource:3` or compiler plugins need a stated reason.
- **Cross-building**: `crossScalaVersions` stays consistent with `scalaVersion`. Version-specific
  sources and settings use `CrossVersion.partialVersion` or `scala-2.13/` source directories.
- **Settings scoping**: `ThisBuild /` for build-wide settings, per-project settings in a shared
  `Seq[Setting[_]]`, not copy-pasted. New modules are aggregated in the root project.
