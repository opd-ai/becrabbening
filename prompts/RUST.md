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

Port the C++ logic into **idiomatic Rust**. This is NOT a line-by-line translation:
- Use `Result<T, E>` for fallible operations internally.
- Use iterators instead of raw loops.
- Use Rust's ownership model instead of manual memory management.
- Use `String` and `Vec<T>` internally; convert to C types only at the FFI boundary.
- Derive `Debug`, `Clone`, etc. where appropriate.

Refer to the API surface snapshot from Phase 0 (`test_{name}_contract.cpp` comment block) to ensure every public function is implemented.

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
- [ ] `cargo test` passes
- [ ] `cargo clippy` passes with no warnings

## What NOT to Do
- Do **not** modify any existing C++ files. This phase is purely additive.
- Do **not** add `rust/{name}` to `moz.build` yet. That happens in Phase 4.
- Do **not** use C++ types or semantics in the Rust code.
