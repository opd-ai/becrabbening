# TASK: Audit the Phase 1 Rust output for AI-generated slop patterns and remediate every violation.

## Execution Mode
**Autonomous action** — scan the Rust crate for slop patterns, fix every violation, re-run tests and clippy, then stop.

This prompt operates on a **Firefox source tree**. The target file-pair name is provided above.

## Context
Read the becrabbening documentation:
- [02b-ANTI-SLOP-AUDIT.md](./02b-ANTI-SLOP-AUDIT.md) — full anti-slop audit instructions and pattern catalogue
- [02-PHASE-1-RUST.md](./02-PHASE-1-RUST.md) — Phase 1 Rust implementation (context)
- [examples/nsfoo/lib.rs](./examples/nsfoo/lib.rs) — clean worked example

## Workflow

### Step 1: Run Strict Clippy

```bash
cd rust/{name}
cargo clippy -- -D warnings -W clippy::pedantic -W clippy::nursery
```

Fix every warning. Suppress individual lints only with a `// RATIONALE:` comment.

### Step 2: Scan for Slop Patterns

Review `rust/{name}/src/lib.rs` (and any submodules) against the full catalogue in [02b-ANTI-SLOP-AUDIT.md](./02b-ANTI-SLOP-AUDIT.md). Check for:

- **S-01 Gratuitous `.clone()`** — remove unnecessary clones; use references or borrows.
- **S-02 Reckless `.unwrap()` / `.expect()`** — replace with `?`, `.unwrap_or()`, or pattern matching (outside tests).
- **S-03 Stringly-typed interfaces** — replace `String`/`&str` with enums or newtypes where values are constrained.
- **S-04 Oversized `unsafe` blocks** — narrow every `unsafe` block to the minimum required expression.
- **S-05 Cargo-cult derives** — remove unused derives; keep only traits the code actually uses.
- **S-06 `todo!()` / `unimplemented!()` stubs** — implement fully or return an explicit error with a `// TODO:` comment.
- **S-07 Redundant closures** — pass function pointers directly to `.map()`, `.filter()`, etc.
- **S-08 Lossy `as` casts** — replace with `TryFrom`/`Into` except at documented FFI boundaries.
- **S-09 `pub` on internal items** — reduce visibility to minimum required; only FFI exports need `pub`.
- **S-10 Boilerplate comments** — remove comments that merely restate the function name; add meaningful doc comments.
- **S-11 `Arc<Mutex<T>>` overuse** — use single ownership unless shared concurrent access is demonstrated.
- **S-12 Empty or trivial `impl` blocks** — replace with `#[derive(...)]` or remove.
- **S-13 Commented-out code** — delete dead code in comments; use version control for history.
- **S-14 Overly generic type parameters** — use concrete types when only one type is passed.
- **S-15 Missing `#[must_use]`** — add `#[must_use]` on non-`Result` return types that should not be silently discarded.

For each violation found, apply the fix documented in the catalogue.

### Step 3: Verify FFI Boundary Hygiene

Audit every `extern "C"` function:

- [ ] Every `unsafe` block has a `// SAFETY:` comment.
- [ ] `unsafe` scope is minimal (single expression, not full function body).
- [ ] No silent truncation in `as` casts — ranges are documented or covered by contract tests.
- [ ] Null checks present before every raw-pointer dereference.
- [ ] No `CString` pointers returned whose backing storage has been dropped.

### Step 4: Re-run Tests and Clippy

```bash
cd rust/{name}
cargo test
cargo clippy -- -D warnings
```

All tests must pass. Zero clippy warnings.

## Output Artifacts
- [ ] `cargo clippy -- -D warnings -W clippy::pedantic -W clippy::nursery` passes (or has documented suppressions)
- [ ] Every slop pattern checked — no violations remain
- [ ] FFI boundary hygiene verified
- [ ] `cargo test` still passes
- [ ] No new files created — this step only modifies existing Rust source files

## What NOT to Do
- Do **not** modify any existing C++ files.
- Do **not** change FFI function signatures (that is a Phase 1 re-do, not slop cleanup).
- Do **not** suppress clippy warnings without a `// RATIONALE:` comment.
- Do **not** add new crate dependencies to fix slop.
