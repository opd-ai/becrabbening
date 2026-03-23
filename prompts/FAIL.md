# TASK: Diagnose and fix build or test failures for the current oxidation target.

## Execution Mode
**Autonomous action** — identify the root cause of each failure, apply the minimal fix in the correct layer, validate the fix, then stop.

This prompt operates on a **Firefox source tree**. The target file-pair name is provided above.

## Context
Read the becrabbening documentation:
- [06-PHASE-5-VALIDATE.md](./06-PHASE-5-VALIDATE.md) — troubleshooting table
- [02-PHASE-1-RUST.md](./02-PHASE-1-RUST.md) — Rust layer details
- [03-PHASE-2-C-FFI.md](./03-PHASE-2-C-FFI.md) — C FFI layer details
- [04-PHASE-3-CPP-SHIM.md](./04-PHASE-3-CPP-SHIM.md) — C++ shim layer details

## Workflow

### Phase 1: Identify All Failures

Run the full validation suite and collect all failures:

```bash
# Rust tests
cd rust/{name} && cargo test 2>&1 | tee /tmp/rust-test-output.txt
cd ../..

# Clippy
cd rust/{name} && cargo clippy -- -D warnings 2>&1 | tee /tmp/clippy-output.txt
cd ../..

# C FFI header
gcc -xc -fsyntax-only {name}_ffi.h 2>&1 | tee /tmp/ffi-output.txt

# C++ shim
g++ -xc++ -std=c++17 -fsyntax-only {name}_shim.h 2>&1 | tee /tmp/shim-output.txt

# Contract tests
g++ -std=c++17 test_{name}_contract.cpp {name}.cpp -o test_{name}_contract 2>&1 | tee /tmp/contract-build.txt
./test_{name}_contract 2>&1 | tee /tmp/contract-output.txt
```

### Phase 2: Classify Each Failure

For each failure, determine:

| Category | Description | Fix Layer |
|----------|-------------|-----------|
| **Rust logic bug** | Rust test fails, contract test fails | Fix in `rust/{name}/src/lib.rs` |
| **FFI naming error** | Missing `fox_*` symbol, link error | Fix `#[no_mangle]` names in `lib.rs` |
| **FFI type error** | ABI crash, wrong values | Add `#[repr(C)]` or fix type conversion in `lib.rs` |
| **Panic across FFI** | Abort or undefined behavior | Add `catch_unwind` wrapper in `lib.rs` |
| **C header error** | `gcc -xc` fails | Fix `cbindgen.toml` and regenerate header |
| **Shim API mismatch** | Compile error in callers | Fix `{name}_shim.h` to match original API |
| **Build system error** | Link error, undefined reference | Fix `moz.build` entry |

### Phase 3: Fix Each Failure

Apply fixes in the correct layer. Fix order:
1. **Layer 1 (Rust)** — logic bugs and FFI export issues first
2. **Layer 2 (C FFI)** — regenerate header after Rust fixes
3. **Layer 3 (C++ Shim)** — API surface fixes
4. **Build system** — `moz.build` and linking

For each fix:
1. Apply the minimal change.
2. Run the specific validation for that layer.
3. Confirm the fix resolves the failure.

### Phase 4: Full Re-validation

After all fixes:

```bash
# Rust
cd rust/{name} && cargo test && cargo clippy -- -D warnings
cd ../..

# C FFI
gcc -xc -fsyntax-only {name}_ffi.h

# C++ shim
g++ -xc++ -std=c++17 -fsyntax-only {name}_shim.h

# Contract tests
g++ -std=c++17 test_{name}_contract.cpp {name}.cpp -o test_{name}_contract
./test_{name}_contract
```

All checks must pass.

## Fix Rules

- Never delete a failing test — fix the implementation or update the test expectation.
- Fixes must not change any public API signatures.
- Fixes must match the project's existing conventions.
- If a fix requires more than 20 lines of new code, report the issue as needing manual intervention.

## Output Format

```
[Layer N] [Failure description] — [root cause]
  File: [path:line]
  Fix: [description of change]
  Status: PASS / FAIL
```

## Tiebreaker

Fix failures in the deepest layer first (Rust → C FFI → C++ Shim → Build system).
