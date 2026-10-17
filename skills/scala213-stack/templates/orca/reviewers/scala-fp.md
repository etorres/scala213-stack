---
description: Reviews Scala 2.13 code for functional idioms — immutability, total functions, Either/Option over throws and nulls, ADTs and exhaustive matching, domain types with smart constructors, implicit hygiene, explicit dependencies, single-concern functions — following the effect/concurrency style the project already uses.
files: \.(scala|sc)$
---

## Scope

This project is **Scala 2.13 built with sbt 1.x**. This file replaces Orca's built-in
Scala 3 / Ox reviewer. Review only the FP idioms below; other reviewers cover the rest.

Never recommend Scala 3–only features: braceless/indentation syntax, `enum`, `given`/`using`,
`extension` methods, opaque types, union types, `export`, top-level definitions, or Ox.
Exception: syntax the compiler accepts under `-Xsource:3`, and only if that flag is already in
`scalacOptions`. Never recommend switching effect or concurrency library. Judge code against
the style the project already uses (plain `Future`, Akka/Pekko, cats-effect, ZIO, or synchronous code).

## Aspects

- **No shared mutable state**: no `var` fields on classes/objects, no `mutable.Map`/`Buffer`
  as fields. Shared state goes through the project's existing primitive (`AtomicReference`
  updated with `updateAndGet`, never `get` then `set`; `Ref`; an actor). Mutable collections in
  test helpers that simulate external systems are fine.
- **Local mutability is fine if scoped**: a `var` or builder inside a method body that never escapes.
- **Pure functions**: parameters in, value out, no hidden `Instant.now`/`UUID.randomUUID`/`Random`.
  Inject a clock or id generator the way the project already does. Use pattern matching on ADTs for
  control flow, not if/else cascades on flags.
- **One concern per function**: a function that does several steps (validate, transform, persist,
  notify) should read as an orchestrator of named steps.
- **ADTs**: `sealed trait` / `sealed abstract class` + `final case class` / `case object`.
  Matches on sealed types must be exhaustive, with no catch-all `case _` that hides new cases.
  Different entity states are different types, not `Option`/`Boolean` fields whose combinations
  allow impossible states.
- **Domain types + smart constructors**: wrap meaningful `String`/`Int`/`Long` values
  (`final case class OrderId(value: String) extends AnyVal`, or the newtype mechanism the project
  already uses). When the raw value has constraints, the companion's constructor returns
  `Either[Reason, T]` (or the project's validation type, e.g. `ValidatedNel`), and a
  `private` constructor or `sealed abstract case class` prevents bypassing it. No boolean blindness.
- **Failures as values**: recoverable failures are `Either[DomainError, T]` (or the effect's typed
  error channel) with a sealed error hierarchy, never stringly-typed. Foreign exceptions are converted
  at the boundary (`Try(...).toEither`, `Either.catchOnly`, `ZIO.attempt`, `IO.blocking`...). Absence is
  `Option`, never `null` (wrap Java APIs with `Option(...)`). `Option` is never an error. No `.get`
  on `Option`/`Try`/`Either`, and no `head`/`last` on possibly empty collections, outside tests.
- **Implicit hygiene**: implicit defs/vals have explicit result types. No implicit conversions
  (`implicit def a2b`) without strong reason. Use type classes and implicit classes for syntax.
  Implicit instances live in companion objects, or in a clearly named `instances`/`syntax` object.
  Keep implicit scope narrow (no wildcard imports of unrelated implicits). Implicit parameters carry
  context or type classes, not ordinary configuration values.
- **2.13 collections and stdlib**: `scala.jdk.CollectionConverters._` (not the deprecated
  `JavaConverters`), `LazyList` (not `Stream`), `.view` for multi-step transforms of large collections,
  `to(Factory)`/`.toMap`. No `mapValues`/`filterKeys` returning lazy views by accident (use `.view.mapValues(...).toMap`).
- **Syntax hygiene**: no `return` (non-local returns inside lambdas are a bug risk), no procedure
  syntax (`def f() { }` is deprecated in 2.13), explicit return types on public members, no
  `Any`/`AnyRef` inference leaks, `final` on case classes.
- **Concurrency in the project's style**: no raw `Thread`, `synchronized` or `Lock` where the project
  has a higher-level primitive. With `Future`, no `Await.result` in production code, and an explicit,
  appropriate `ExecutionContext` (no `global` for blocking I/O). With an effect system, side effects
  stay suspended in the effect type (no eager effects in `val`s, no `unsafeRun*` outside the edge of the app).
