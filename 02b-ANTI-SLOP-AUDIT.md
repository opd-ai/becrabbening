# Anti-Slop Audit — Rust Quality Gate

**Goal:** Identify and remediate common AI-generated "slop" patterns in the Phase 1 Rust output before proceeding to C FFI header generation.

Previous: [02-PHASE-1-RUST.md](./02-PHASE-1-RUST.md) — Rust implementation.
Next: [03-PHASE-2-C-FFI.md](./03-PHASE-2-C-FFI.md) — C FFI header generation.

---

## Why This Step Exists

AI-assisted code generation produces characteristic patterns of low-quality Rust that compiles and passes basic tests but is non-idiomatic, wasteful, or subtly incorrect. These patterns — collectively called **slop** — undermine the safety and maintainability goals of the C++-to-Rust conversion. Catching them before Phase 2 is cheaper than fixing them after the FFI header and shim have been built on top.

---

## Step-by-Step Instructions

### Step 1 — Run cargo clippy (strict)

```bash
cd rust/{name}
cargo clippy -- -D warnings -W clippy::pedantic -W clippy::nursery
```

Fix every warning. Clippy's pedantic and nursery lints catch many of the patterns listed below automatically. Suppress individual lints only with a `// RATIONALE:` comment explaining why the suppression is necessary.

### Step 2 — Scan for slop patterns

Review `rust/{name}/src/lib.rs` (and any submodules) against the checklist in the [Slop Pattern Catalogue](#slop-pattern-catalogue) below. For each violation found, apply the documented fix.

### Step 3 — Verify FFI boundary hygiene

Separately audit every `extern "C"` function for FFI-specific slop:

- [ ] No unnecessary `unsafe` scope — each `unsafe` block wraps the minimum required expression, not the entire function body.
- [ ] Every `unsafe` block has a `// SAFETY:` comment.
- [ ] No raw-pointer arithmetic outside of `unsafe` blocks.
- [ ] No `as` casts that could silently truncate or sign-extend — prefer `c_int::from(x)` or `i32::try_from(x)` where applicable.
- [ ] No returned `CString` pointers whose backing storage has been dropped (use-after-free via FFI).
- [ ] Null checks are present before every raw-pointer dereference.

### Step 4 — Re-run tests and clippy

```bash
cd rust/{name}
cargo test
cargo clippy -- -D warnings
```

All tests must still pass. Zero clippy warnings.

---

## Slop Pattern Catalogue

Each entry describes a common AI-generated anti-pattern, why it is harmful, and how to fix it.

---

### S-01 — Gratuitous `.clone()`

**Pattern:** Calling `.clone()` to satisfy the borrow checker instead of restructuring ownership or using references.

```rust
// SLOP
fn process(data: &MyStruct) -> String {
    let owned = data.name.clone();   // unnecessary allocation
    owned.to_uppercase()
}
```

**Fix:** Use a reference or borrow where the owned value is not needed.

```rust
fn process(data: &MyStruct) -> String {
    data.name.to_uppercase()  // borrows directly
}
```

**Why it matters:** Unnecessary clones add heap allocations that accumulate in hot paths. In a browser engine, every allocation counts.

---

### S-02 — Reckless `.unwrap()` / `.expect()`

**Pattern:** Using `.unwrap()` or `.expect()` outside of tests, where a `None` or `Err` is reachable.

```rust
// SLOP
fn get_value(map: &HashMap<String, i32>, key: &str) -> i32 {
    *map.get(key).unwrap()  // panics if key is missing
}
```

**Fix:** Use `?`, `.unwrap_or()`, `.unwrap_or_default()`, or pattern matching.

```rust
fn get_value(map: &HashMap<String, i32>, key: &str) -> Option<i32> {
    map.get(key).copied()
}
```

**Exception:** `.unwrap()` is acceptable in `#[cfg(test)]` code and in situations where the invariant is proven (document with a comment).

---

### S-03 — Stringly-typed interfaces

**Pattern:** Using `String` or `&str` where an enum, newtype, or typed identifier would prevent misuse.

```rust
// SLOP
fn set_mode(mode: &str) { /* "read", "write", "append" */ }
```

**Fix:** Define an enum.

```rust
enum Mode { Read, Write, Append }
fn set_mode(mode: Mode) { /* ... */ }
```

**Why it matters:** Stringly-typed APIs accept invalid values at runtime that an enum would reject at compile time.

---

### S-04 — Oversized `unsafe` blocks

**Pattern:** Wrapping an entire function body in `unsafe` when only one expression requires it.

```rust
// SLOP
pub extern "C" fn fox_example(ptr: *const FoxThing) -> c_int {
    unsafe {
        let thing = &(*ptr).0;
        let result = thing.compute();  // safe code inside unsafe block
        result as c_int
    }
}
```

**Fix:** Narrow the `unsafe` block to just the pointer dereference.

```rust
pub extern "C" fn fox_example(ptr: *const FoxThing) -> c_int {
    // SAFETY: caller guarantees ptr is non-null and valid
    let thing = unsafe { &(*ptr).0 };
    let result = thing.compute();
    result as c_int
}
```

**Why it matters:** An oversized `unsafe` block hides which specific operation is actually unsafe, making auditing harder and bugs more likely.

---

### S-05 — Cargo-cult derives

**Pattern:** Applying `#[derive(Debug, Clone, PartialEq, Eq, Hash, Default)]` to every struct without considering which traits are actually needed.

```rust
// SLOP
#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, PartialOrd, Ord)]
pub struct ConnectionHandle {
    id: u64,
}
```

**Fix:** Derive only the traits that are required by the code. Add traits incrementally when the compiler requests them.

```rust
#[derive(Debug)]
pub struct ConnectionHandle {
    id: u64,
}
```

**Why it matters:** Unnecessary derives increase compile time, bloat the binary with unused trait implementations, and can introduce unintended semantics (e.g., a derived `PartialEq` on a handle type that should use identity comparison).

---

### S-06 — `todo!()` / `unimplemented!()` stubs

**Pattern:** AI leaves placeholder macros that panic at runtime.

```rust
// SLOP
fn handle_error(&self, code: i32) -> Result<(), Error> {
    todo!("implement error handling")
}
```

**Fix:** Implement the function fully or, if deferral is truly necessary, return an explicit error with a `// TODO:` comment explaining the deferral reason.

```rust
fn handle_error(&self, code: i32) -> Result<(), Error> {
    // TODO: Map vendor-specific error codes once the mapping table is finalized.
    Err(Error::Unimplemented(code))
}
```

**Why it matters:** `todo!()` and `unimplemented!()` panic, which violates the `catch_unwind` safety model at the FFI boundary and would abort the Firefox process.

---

### S-07 — Redundant closures

**Pattern:** Wrapping a function call in a closure that adds no value.

```rust
// SLOP
let values: Vec<_> = items.iter().map(|x| convert(x)).collect();
```

**Fix:** Pass the function directly.

```rust
let values: Vec<_> = items.iter().map(convert).collect();
```

---

### S-08 — Lossy `as` casts

**Pattern:** Using `as` for numeric conversions that could silently truncate or change sign.

```rust
// SLOP
let size: u64 = get_size();
let len: usize = size as usize;  // truncates on 32-bit
```

**Fix:** Use `TryFrom`/`TryInto` for fallible conversions, or `From`/`Into` for infallible ones.

```rust
let len: usize = usize::try_from(size).expect("size exceeds platform pointer width");
```

**Exception:** `as c_int` and `as i32` casts at the FFI boundary are acceptable when the value range is documented and the Phase 0 contract tests cover boundary values.

---

### S-09 — `pub` on internal items

**Pattern:** Making every function, struct, and field `pub` regardless of whether external access is needed.

```rust
// SLOP
pub struct InternalHelper {
    pub cache: HashMap<String, Vec<u8>>,
    pub counter: usize,
}
```

**Fix:** Use the minimum visibility: `pub(crate)`, `pub(super)`, or no modifier. Only items that cross the FFI boundary need `pub`.

```rust
struct InternalHelper {
    cache: HashMap<String, Vec<u8>>,
    counter: usize,
}
```

---

### S-10 — Boilerplate comments restating the function name

**Pattern:** Every function has a doc comment that merely restates the function name in prose.

```rust
// SLOP
/// Creates a new instance.
pub fn new() -> Self { /* ... */ }

/// Returns the value.
pub fn value(&self) -> i32 { /* ... */ }
```

**Fix:** Either add a meaningful doc comment that explains behavior, edge cases, or panics — or remove the comment entirely if the function is self-documenting.

```rust
/// Allocate an `NsFoo` with `initial` as the starting accumulator value.
pub fn new(initial: i32) -> Self { /* ... */ }
```

---

### S-11 — `Arc<Mutex<T>>` when single ownership suffices

**Pattern:** Defaulting to shared mutable state instead of moving ownership or using `&mut`.

```rust
// SLOP
let data = Arc::new(Mutex::new(Vec::new()));
// ... only ever accessed from one thread
```

**Fix:** Use owned values or `&mut` references. Introduce `Arc<Mutex<T>>` only when shared concurrent access is demonstrably needed.

---

### S-12 — Empty or trivial `impl` blocks

**Pattern:** Implementing traits with no-op methods or pass-through delegation that adds no value.

```rust
// SLOP
impl Default for Config {
    fn default() -> Self {
        Config { value: 0 }
    }
}
// when #[derive(Default)] would produce the same result
```

**Fix:** Use `#[derive(Default)]` when the derived implementation is correct. Remove no-op trait implementations that serve no purpose.

---

### S-13 — Commented-out code

**Pattern:** AI leaves dead code from previous iterations behind comments.

```rust
// SLOP
fn compute(&self) -> i32 {
    // let old_result = self.legacy_compute();
    // if old_result > 0 { return old_result; }
    self.new_compute()
}
```

**Fix:** Delete commented-out code. Use version control history to recover old implementations if needed.

---

### S-14 — Overly generic type parameters

**Pattern:** Using generics where concrete types suffice, adding complexity without flexibility.

```rust
// SLOP
fn process<T: AsRef<str>>(input: T) -> String {
    input.as_ref().to_uppercase()
}
// when only called with &str
```

**Fix:** Use concrete types unless the generic is called with multiple concrete types or is part of a public API that must be generic.

```rust
fn process(input: &str) -> String {
    input.to_uppercase()
}
```

---

### S-15 — Missing `#[must_use]` on important return values

**Pattern:** Functions returning `Result` or important values without `#[must_use]`, allowing callers to silently ignore errors.

```rust
// SLOP
pub fn validate(&self) -> Result<(), ValidationError> { /* ... */ }
```

**Fix:** Add `#[must_use]` to functions whose return values should not be silently discarded.

```rust
#[must_use]
pub fn validate(&self) -> Result<(), ValidationError> { /* ... */ }
```

**Note:** `Result` itself has `#[must_use]` in the standard library, so the compiler already warns. This pattern is most relevant for non-`Result` return types that still carry important information.

---

## What NOT to Do

- **Do not modify any existing C++ files.** This step is purely a quality gate on Rust code.
- **Do not modify the FFI function signatures.** Fixing slop should not change the public API surface. If you discover a signature that is fundamentally wrong, file it as a Phase 1 re-do, not a slop fix.
- **Do not suppress clippy warnings without a documented rationale.**
- **Do not add new dependencies** to fix slop. If the fix requires a new crate, that is a Phase 1 design issue, not slop.

---

## Output Artifacts

At the end of the anti-slop audit, you should have:

- [ ] `cargo clippy -- -D warnings -W clippy::pedantic -W clippy::nursery` passes (or has documented suppressions)
- [ ] Every item in the Slop Pattern Catalogue has been checked — no violations remain
- [ ] FFI boundary hygiene verified (Step 3 checklist complete)
- [ ] `cargo test` still passes
- [ ] No new files created — this step only modifies `rust/{name}/src/lib.rs` and submodules

---

## Cross-References

- [02-PHASE-1-RUST.md](./02-PHASE-1-RUST.md) — previous phase (Rust implementation)
- [03-PHASE-2-C-FFI.md](./03-PHASE-2-C-FFI.md) — next phase (C FFI header)
- [00-OVERVIEW.md](./00-OVERVIEW.md) — architecture overview
- [examples/nsfoo/lib.rs](./examples/nsfoo/lib.rs) — complete worked example
