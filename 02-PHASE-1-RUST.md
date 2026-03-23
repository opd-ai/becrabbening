# Phase 1 — Rust Implementation

**Goal:** Create an idiomatic Rust replacement for the C++ logic.

Previous: [01-PHASE-0-PREPARE.md](./01-PHASE-0-PREPARE.md) — API snapshot and contract tests.
Next: [03-PHASE-2-C-FFI.md](./03-PHASE-2-C-FFI.md) — C FFI header generation.

---

## Step-by-Step Instructions

### Step 1 — Create `rust/{name}/Cargo.toml`

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

Use `crate-type = ["staticlib"]` so the Rust code links into the Firefox build as a static archive.

### Step 2 — Create `rust/{name}/src/lib.rs`

This is the main implementation file. See [examples/nsfoo/lib.rs](./examples/nsfoo/lib.rs) for a complete worked example.

### Step 3 — Port the logic

Port the logic from the `.cpp` file into idiomatic Rust. This is **NOT** a line-by-line translation. Write Rust as Rust:

- Use `Result<T, E>` for fallible operations internally
- Use iterators instead of raw loops
- Use Rust's ownership model instead of manual memory management
- Use `String` and `Vec<T>` internally; convert to C types only at the FFI boundary
- Derive `Debug`, `Clone`, etc. where appropriate

Refer to the API surface snapshot from Phase 0 to ensure every public function is implemented.

### Step 4 — Add `extern "C"` FFI wrappers

For every public function that needs to cross the FFI boundary, create an `extern "C"` wrapper with `#[no_mangle]`. Place these at the bottom of `lib.rs`, clearly separated from the Rust-native implementation.

```rust
#[no_mangle]
pub extern "C" fn fox_{name}_example(ptr: *mut FoxName, x: c_int) -> c_int {
    catch_unwind_or_abort(|| {
        // SAFETY: caller guarantees ptr is valid and non-null
        let obj = unsafe { &mut (*ptr).0 };
        obj.example(x as i32) as c_int
    })
}
```

### Step 5 — FFI-safe types

All types that cross the FFI boundary must use `#[repr(C)]`:

```rust
#[repr(C)]
pub enum FoxResult {
    Ok = 0,
    Error = 1,
}
```

For opaque handles, use the opaque pointer pattern (see below) — no `#[repr(C)]` needed on the inner type.

### Step 6 — Wrap every `extern "C"` function in `catch_unwind`

Rust panics **must not** unwind across the FFI boundary — this is undefined behavior. Wrap every `extern "C"` function body:

```rust
use std::panic::catch_unwind;

#[no_mangle]
pub extern "C" fn fox_{name}_bar(ptr: *mut FoxName, x: c_int) -> c_int {
    match catch_unwind(|| {
        // SAFETY: caller guarantees ptr is valid
        let obj = unsafe { &(*ptr).0 };
        obj.bar(x as i32) as c_int
    }) {
        Ok(v) => v,
        Err(_) => -1,  // or a sentinel error value
    }
}
```

### Step 7 — Opaque pointer pattern

Create a newtype wrapper struct that cbindgen will emit as an opaque `typedef struct`:

```rust
/// Opaque handle for C callers. cbindgen emits: typedef struct FoxName FoxName;
pub struct FoxName(Name);
```

Do **not** add `#[repr(C)]` to the outer struct — it should remain opaque (cbindgen handles this).

### Step 8 — Lifecycle functions

Always provide `_new` and `_free` for heap-allocated opaque types:

```rust
#[no_mangle]
pub extern "C" fn fox_{name}_new(/* constructor args */) -> *mut FoxName {
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
            // SAFETY: ptr was created by fox_{name}_new
            let _ = unsafe { Box::from_raw(ptr) };
        });
    }
}
```

### Step 9 — Test and lint

```bash
cd rust/{name}
cargo test
cargo clippy -- -D warnings
```

All tests must pass. Zero clippy warnings.

---

## FFI Naming Convention

All exported symbols must be prefixed with `fox_{name}_`. For example:

- `fox_nsfoo_new`
- `fox_nsfoo_free`
- `fox_nsfoo_bar`
- `fox_nsfoo_set_value`

This prefix prevents symbol collisions in the linked binary and makes it obvious which symbols are Rust-backed.

---

## Error Handling Strategy

| Boundary | Mechanism |
|---|---|
| Internal Rust code | Rich `Result<T, E>` — use `?` freely |
| At the FFI boundary | Return codes (`c_int`) or `FoxResult` enum |
| Panics | Caught by `catch_unwind`, converted to sentinel error value |

Never propagate a Rust `Error` type across the FFI boundary directly — it is not ABI-stable.

---

## What NOT to Do

- **Do not modify any existing C++ files.** This phase is purely additive.
- **Do not add `rust/{name}` to `moz.build` yet.** That happens in Phase 4.
- Do not use C++ types or semantics in the Rust code — write idiomatic Rust.

---

## Output Artifacts

At the end of Phase 1, you should have:

- [ ] `rust/{name}/Cargo.toml` created
- [ ] `rust/{name}/src/lib.rs` created with idiomatic Rust implementation
- [ ] All FFI exports use `#[no_mangle] extern "C"`
- [ ] All boundary types use `#[repr(C)]` or the opaque pointer pattern
- [ ] All `extern "C"` bodies wrapped in `catch_unwind`
- [ ] `cargo test` passes
- [ ] `cargo clippy` passes with no warnings

---

## Cross-References

- [01-PHASE-0-PREPARE.md](./01-PHASE-0-PREPARE.md) — previous phase (API snapshot)
- [03-PHASE-2-C-FFI.md](./03-PHASE-2-C-FFI.md) — next phase (C FFI header)
- [00-OVERVIEW.md](./00-OVERVIEW.md) — architecture overview and three-layer sandwich
- [examples/nsfoo/lib.rs](./examples/nsfoo/lib.rs) — complete worked example
