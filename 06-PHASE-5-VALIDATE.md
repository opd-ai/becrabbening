# Phase 5 — Validate

**Goal:** Prove that the conversion is correct, ABI-compatible, and doesn't break anything.

Previous: [05-PHASE-4-SWITCHOVER.md](./05-PHASE-4-SWITCHOVER.md) — switchover edits.
Next: [07-PHASE-6-MERGE.md](./07-PHASE-6-MERGE.md) — merge and clean up.

---

## Step-by-Step Instructions

### Step 1 — Run contract tests

Run the contract tests written in Phase 0. These tests must pass **without modification** — you must not change the tests to make them pass.

```bash
# Compile and run against the new Rust-backed implementation
g++ -std=c++17 test_{name}_contract.cpp {name}.cpp -o test_{name}_contract
./test_{name}_contract
```

If a contract test fails:
- Do **not** modify the test.
- Instead, find the bug in the Rust implementation (Phase 1), the C FFI (Phase 2), or the shim (Phase 3) and fix it there.
- After fixing, re-validate from Step 1.

### Step 2 — Run `cargo test` on the Rust crate in isolation

```bash
cd rust/{name}
cargo test
```

All tests must pass. This verifies the Rust logic independent of the FFI layer.

### Step 3 — Run `mach build`

Full Firefox build must succeed with no errors:

```bash
./mach build
```

### Step 4 — Run `mach test`

Full test suite must pass:

```bash
./mach test
```

Pay particular attention to tests in the subsystem that uses `{name}`. If tests were passing before Phase 0 and are now failing, the conversion introduced a regression.

### Step 5 — ABI symbol verification

Compare exported symbols before and after the conversion. They must match.

```bash
# Before (from the original compiled object — retrieve from git if needed)
nm -D lib{name}_original.so | grep ' T ' | sort > /tmp/symbols_before.txt

# After
nm -D lib{name}.so | grep ' T ' | sort > /tmp/symbols_after.txt

# Diff — should show no missing symbols
diff /tmp/symbols_before.txt /tmp/symbols_after.txt
```

Any symbol present before but missing after is a regression. Fix the FFI naming (Phase 1, Step 4) and regenerate the C FFI header (Phase 2).

### Step 6 — Verify header-only downstream compilation

For header-only conversions, verify that all files that include `{name}.h` still compile:

```bash
# Find all includers
grep -r '#include.*{name}.h' . --include='*.cpp' --include='*.h'

# Build them
./mach build path/to/each/includer.cpp
```

### Step 7 — Run component-specific integration tests

If the converted component has its own integration test suite, run it:

```bash
./mach test path/to/{name}/tests/
```

### Step 8 — Verify no new compiler warnings

```bash
./mach build 2>&1 | grep -i warning | grep {name}
```

No new warnings should be introduced by the conversion.

---

## Automated CI Checks

Recommend adding the following as CI jobs to run on every oxidation PR:

| Check | Command | Description |
|---|---|---|
| Rust unit tests | `cargo test` | Verify Rust logic |
| Rust linting | `cargo clippy -- -D warnings` | No warnings |
| C FFI header validity | `gcc -xc -fsyntax-only {name}_ffi.h` | Pure-C compliance |
| Contract tests | `./run_contract_tests.sh {name}` | API contract |
| Full build | `./mach build` | Integration |
| Full tests | `./mach test` | Regression |
| Symbol diff | custom script | ABI verification |

---

## Troubleshooting Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| Symbol mismatch (missing `fox_*` symbol) | Wrong `#[no_mangle]` name in Rust | Fix the name in Phase 1, Step 4 |
| ABI incompatibility (crash or wrong result) | Missing `#[repr(C)]` on boundary type | Add `#[repr(C)]` in Phase 1, Step 5 |
| Panic across FFI (abort or undefined behavior) | Missing `catch_unwind` | Add `catch_unwind` in Phase 1, Step 6 |
| Link error (undefined reference to `fox_*`) | `moz.build` not updated | Fix `moz.build` in Phase 4, Step 3 |
| Contract test fails | Logic bug in Rust port | Fix in Phase 1, Step 3 |
| Compile error in caller | Shim API differs from original | Fix shim in Phase 3 |

---

## If Validation Fails

Fix the bug in the appropriate phase:

- Logic bug → fix in **Phase 1** (Rust implementation)
- Wrong C types or missing functions → fix in **Phase 2** (C FFI) by fixing Rust and regenerating
- Wrong C++ API surface → fix in **Phase 3** (C++ shim)
- Wrong file contents or build system → fix in **Phase 4** (switchover)

After fixing, **re-validate from Step 1** of this phase. Do **not** patch around failures with workarounds.

---

## Output Artifacts

At the end of Phase 5, you should have:

- [ ] Contract tests pass without modification
- [ ] `cargo test` passes
- [ ] `mach build` succeeds
- [ ] `mach test` passes
- [ ] ABI symbol diff shows no missing symbols
- [ ] No new compiler warnings

---

## Cross-References

- [05-PHASE-4-SWITCHOVER.md](./05-PHASE-4-SWITCHOVER.md) — previous phase (switchover)
- [07-PHASE-6-MERGE.md](./07-PHASE-6-MERGE.md) — next phase (merge)
- [01-PHASE-0-PREPARE.md](./01-PHASE-0-PREPARE.md) — contract tests (written in Phase 0)
- [09-CHECKLIST-TEMPLATE.md](./09-CHECKLIST-TEMPLATE.md) — PR checklist
