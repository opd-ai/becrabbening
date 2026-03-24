# TASK: Implement the Rust replacement for the target file-pair with idiomatic Rust and extern "C" FFI exports.

## Execution Mode
**Autonomous action** — implement the full Rust crate, validate with tests and clippy, then stop.

This prompt operates on a **Firefox source tree**. The target file-pair name is provided above.

## Context
Read the becrabbening documentation:
- [02-PHASE-1-RUST.md](./02-PHASE-1-RUST.md) — detailed Phase 1 instructions
- [00-OVERVIEW.md](./00-OVERVIEW.md) — three-layer sandwich architecture
- [examples/nsfoo/lib.rs](./examples/nsfoo/lib.rs) — complete worked example

## Workflow

### Step 1: Create `rust/{name}/Cargo.toml`

```toml
[package]
name = "{name}"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["staticlib"]

[dependencies]
# Add dependencies as needed
```

Use `crate-type = ["staticlib"]` so the Rust code links into Firefox as a static archive.

### Step 2: Create `rust/{name}/src/lib.rs`

See [examples/nsfoo/lib.rs](./examples/nsfoo/lib.rs) for the pattern.

### Step 3: Port the Logic

Port the C/C++ logic into **idiomatic, safe Rust**. This is NOT a line-by-line translation. A rote transliteration of buggy C/C++ code is not acceptable — the purpose of this conversion is to eliminate memory errors and improve safety:
- Use `Result<T, E>` for fallible operations internally.
- Use iterators instead of raw loops.
- Use Rust's ownership model instead of manual memory management.
- Use `String` and `Vec<T>` internally; convert to C types only at the FFI boundary.
- Derive `Debug`, `Clone`, etc. where appropriate.
- Eliminate `unsafe` blocks wherever possible; when `unsafe` is required (FFI boundary), minimize the scope and document the safety invariant with a `// SAFETY:` comment.

Refer to the API surface snapshot from Phase 0 (`test_{name}_contract.cpp` comment block) to ensure every public function is implemented.

### Step 3a: Memory Safety Audit

While porting the C/C++ logic, actively audit the original code for memory handling issues. For every issue you discover, **do not replicate the bug** — resolve it with safe, idiomatic Rust. Common C/C++ memory issues to look for:

- **Use-after-free**: Dangling pointers or references to freed memory → Rust's ownership model prevents this.
- **Double-free**: Multiple `delete` calls on the same pointer → Rust's `Drop` trait handles this.
- **Buffer overflows**: Out-of-bounds array/pointer access → Use checked indexing, slices, or iterators.
- **Null pointer dereferences**: Unchecked raw pointer access → Use `Option<T>` instead of nullable pointers.
- **Uninitialized memory reads**: Use of variables before initialization → Rust prevents this at compile time.
- **Memory leaks**: Missing `delete`/`free` calls → Rust's RAII and `Drop` handle deallocation automatically.
- **Data races**: Concurrent access without synchronization → Rust's `Send`/`Sync` traits and borrow checker prevent this.
- **Integer overflows leading to memory corruption**: Unchecked arithmetic used in allocations → Use checked or saturating arithmetic.

**Document every discovered issue** in a file named `MEMORIES_{name}.cpp.md` (or `MEMORIES_{name}.c.md` for C sources, or `MEMORIES_{name}.h.md` for header-only conversions), placed alongside the original source file (e.g., `firefox/path/to/MEMORIES_{name}.cpp.md`). Each entry should include:

1. **Location**: File, line number, and function name in the original C++ code.
2. **Issue type**: Category from the list above (or a new category if applicable).
3. **Description**: What the bug is and how it could manifest at runtime.
4. **Resolution**: How the Rust implementation prevents or resolves this issue.

This file is a required output artifact of Phase 1 — even if no issues are found, create the file with a note that the audit was performed and no issues were discovered.

### Step 4: Add `extern "C"` FFI Wrappers

For every public function crossing the FFI boundary, create an `extern "C"` wrapper with `#[no_mangle]`:

```rust
#[no_mangle]
pub extern "C" fn fox_{name}_example(ptr: *mut FoxName, x: c_int) -> c_int {
    match catch_unwind(|| {
        let obj = unsafe { &mut (*ptr).0 };
        obj.example(x as i32) as c_int
    }) {
        Ok(v) => v,
        Err(_) => -1,
    }
}
```

### Step 5: FFI-Safe Types

All types crossing the FFI boundary must use `#[repr(C)]`:

```rust
#[repr(C)]
pub enum FoxResult {
    Ok = 0,
    Error = 1,
}
```

For opaque handles, use the opaque pointer pattern:

```rust
pub struct FoxName(Name);
```

Do NOT add `#[repr(C)]` to opaque handle wrappers.

### Step 6: Wrap Every `extern "C"` in `catch_unwind`

Panics must NOT cross the FFI boundary. Every `extern "C"` function body must be wrapped:

```rust
use std::panic::catch_unwind;

match catch_unwind(|| { /* body */ }) {
    Ok(v) => v,
    Err(_) => /* sentinel error value */,
}
```

### Step 7: Lifecycle Functions

Always provide `_new` and `_free` for heap-allocated opaque types:

```rust
#[no_mangle]
pub extern "C" fn fox_{name}_new(/* args */) -> *mut FoxName {
    match catch_unwind(|| {
        Box::into_raw(Box::new(FoxName(Name::new(/* args */))))
    }) {
        Ok(ptr) => ptr,
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn fox_{name}_free(ptr: *mut FoxName) {
    if !ptr.is_null() {
        let _ = catch_unwind(|| {
            let _ = unsafe { Box::from_raw(ptr) };
        });
    }
}
```

### Step 8: Test and Lint

```bash
cd rust/{name}
cargo test
cargo clippy -- -D warnings
```

All tests must pass. Zero clippy warnings.

## FFI Naming Convention

All exported symbols MUST be prefixed `fox_{name}_`:
- `fox_{name}_new`
- `fox_{name}_free`
- `fox_{name}_bar`

This prevents symbol collisions and identifies Rust-backed symbols.

## Output Artifacts
- [ ] `rust/{name}/Cargo.toml` created
- [ ] `rust/{name}/src/lib.rs` with idiomatic Rust implementation
- [ ] All FFI exports use `#[no_mangle] extern "C"`
- [ ] All boundary types use `#[repr(C)]` or opaque pointer pattern
- [ ] All `extern "C"` bodies wrapped in `catch_unwind`
- [ ] `MEMORIES_{name}.cpp.md` (or `MEMORIES_{name}.c.md` / `MEMORIES_{name}.h.md`) created alongside the original source file with memory safety audit results
- [ ] `cargo test` passes
- [ ] `cargo clippy` passes with no warnings

## What NOT to Do
- Do **not** modify any existing C/C++ files. This phase is purely additive.
- Do **not** add `rust/{name}` to `moz.build` yet. That happens in Phase 4.
- Do **not** use C++ types or semantics in the Rust code.
- Do **not** blindly replicate C/C++ memory bugs in Rust — fix them using idiomatic, safe Rust patterns.
