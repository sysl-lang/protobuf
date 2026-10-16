# What writing protobuf found in sysl

Found against sysl 0.1.0-alpha.12. Two findings had workarounds taken during the first pass; both
came out when the fixes shipped.

## 1. Explicit type arguments on a trait method reached through a bound are refused (bug)

```sysl
viafree[O: Out](o: *O) -> int = o.one[int]()
```

```
error: 'one' is a method of 'Out' — call it with 'one(…)'
```

The same call on a concrete receiver works, and the reference documents `x.pick[int](3)` as legal. The
same failure happens for `self.one[N]()` inside a trait default. **Effect:** the runtime's field writers
were codec associated functions (`Int32.field(out, 1, v)`), not the planned `out.field[Int32](1, v)`.

**Status: Fixed in sysl 0.1.x; workaround removed.** The writers are `Output` methods
(`out.field[Int32](1, v)`).

## 2. `heap = false` checks code nothing reaches (gap)

Under `capabilities { heap = false }`, the allocator check covers every function of every package in
the graph and every trait default for every impl, so a probe that only encodes into a stack slice is
refused through `sh.sysl.parsing`'s `diag.render` and an unused `Str.get` default. The schema and
generator cannot move to a second package either, because `sh.sysl.protobuf.schema` cannot live in
another package (nested module names collide). Meanwhile the freestanding probe builds without
`heap = false`, and its thumb archive still references `malloc`/`free`.

**Status: accepted for alpha.14** (sysl branch `heap-reach`: reach followed function by function,
extending alpha.13's module-level fix, and finding where the `malloc`/`free` references come from).

## 3. An associated function of an instantiated generic type cannot be called (gap)

`Of[int].twice()` is refused ("'Of' cannot be given type arguments where 'twice' is selected from it");
`type OfInt = Of[int]` then `OfInt.twice()` works.

Every generated file used to end with aliases such as `type XCodec = MessageOf[X]`.

**Status: Fixed in sysl 0.1.x; workaround removed.** Generated code writes `MessageOf[X]` where it
needs the codec.

## 4. A trait default's signature is resolved in the implementing module (bug)

A default `many(self) -> Buf[int]` in a module that imports `Buf` fails in an implementing module that
does not: `error: unknown type 'Buf'`, pointing at an unrelated line of the impl.

The generator used to import `sysl.buf.Buf` into every message module as a workaround; that import is
gone, and a test pins that a scalars-only message imports no `sysl.buf`.

**Status: Fixed in 0.1.0-alpha.13.**

## 5. `&T` has no `Display` even when `T` has (gap)

`derives Display` on a struct holding `Option[&Node]` fails. That blocks boxing a message that contains
itself, so the generator refuses such messages with a diagnostic for now.

**Status: Fixed in 0.1.0-alpha.13** (`&T` is `Display` when `T` is). Recursive messages are now
unblocked; the generator still refuses them until that support is built.

## 6. `unit` has no `Eq` or `Display` (gap)

`assert_eq(x, Ok(()))` on a `Result[unit, E]` is refused. The tests compare `.err()`. The same as
`sysl-lang/fat`'s FINDINGS 5.

**Status: Fixed in 0.1.0-alpha.13.**

## 7. `[]int == []const int` is refused (gap)

Comparing only reads, but the conversion rule refuses it. The tests compare element by element.

**Status: accepted for alpha.14** (sysl branch `small-diags`).

## 8. A reserved word as a field name gives a misleading diagnostic

`g.module` reports `error: tuple index expected` instead of naming the reserved word.

**Status: accepted for alpha.14** (sysl branch `small-diags`).
