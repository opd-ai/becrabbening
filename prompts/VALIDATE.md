# TASK: Validate that the conversion is correct, ABI-compatible, and introduces no regressions.

## Execution Mode
**Autonomous action** — run all validation checks, diagnose any failures, then stop. If a check fails, identify the root cause and the phase where the fix belongs, but do **not** apply fixes in this prompt.

This prompt operates on a **Firefox source tree**. The target file-pair name is provided above.

## Context
Read the becrabbening documentation:
- [06-PHASE-5-VALIDATE.md](./06-PHASE-5-VALIDATE.md) — detailed Phase 5 instructions
- [09-CHECKLIST-TEMPLATE.md](./09-CHECKLIST-TEMPLATE.md) — PR checklist
- [00-OVERVIEW.md](./00-OVERVIEW.md) — architecture overview

## Workflow

### Check 1: Contract Tests

Run the contract tests from Phase 0. They must pass **without modification**:

```bash
g++ -std=c++17 test_{name}_contract.cpp {name}.cpp -o test_{name}_contract
./test_{name}_contract
```

If a contract test fails:
- Do NOT modify the test.
- Identify the bug in Phase 1 (Rust), Phase 2 (C FFI), or Phase 3 (shim).
- Report the failure with root cause analysis.

### Check 2: Cargo Test

```bash
cd rust/{name}
cargo test
```

All Rust tests must pass.

### Check 3: Cargo Clippy

```bash
cd rust/{name}
cargo clippy -- -D warnings
```

Zero warnings.

### Check 4: C FFI Header Validity

```bash
gcc -xc -fsyntax-only {name}_ffi.h
```

Must compile cleanly as pure C.

### Check 5: C++ Shim Compilation

```bash
g++ -xc++ -std=c++17 -fsyntax-only {name}_shim.h
```

Must compile cleanly.

### Check 6: Full Build (if mach available)

```bash
./mach build
```

Must succeed with no errors.

### Check 7: Full Test Suite (if mach available)

```bash
./mach test
```

Pay attention to tests in the subsystem that uses `{name}`.

### Check 8: ABI Symbol Verification

For static libraries (the default `staticlib` crate type):

```bash
nm rust/{name}/target/release/lib{name}.a | grep ' T ' | grep fox_{name}_ | sort
```

For shared libraries (if applicable):

```bash
nm -D lib{name}.so | grep ' T ' | grep fox_{name}_ | sort
```

All expected `fox_{name}_*` symbols must be present.

### Check 9: No New Warnings

```bash
./mach build 2>&1 | grep -i warning | grep {name}
```

No new warnings should be introduced.

## Troubleshooting

| Symptom | Cause | Fix Phase |
|---------|-------|-----------|
| Missing `fox_*` symbol | Wrong `#[no_mangle]` name | Phase 1 |
| ABI crash or wrong result | Missing `#[repr(C)]` | Phase 1 |
| Panic across FFI | Missing `catch_unwind` | Phase 1 |
| Undefined reference to `fox_*` | `moz.build` not updated | Phase 4 |
| Contract test fails | Logic bug in Rust | Phase 1 |
| Compile error in caller | Shim API differs from original | Phase 3 |

## If Validation Fails

Report the failure with:
1. Which check failed
2. The exact error message
3. Root cause analysis
4. Which phase should fix it (Phase 1, 2, 3, or 4)

After the fix is applied in the correct phase, **re-validate from Check 1**.

## Output
Report the status of each check:

```
Check 1 (Contract tests):  PASS / FAIL — [details]
Check 2 (Cargo test):      PASS / FAIL — [details]
Check 3 (Cargo clippy):    PASS / FAIL — [details]
Check 4 (C FFI header):    PASS / FAIL — [details]
Check 5 (C++ shim):        PASS / FAIL — [details]
Check 6 (mach build):      PASS / FAIL / SKIP — [details]
Check 7 (mach test):       PASS / FAIL / SKIP — [details]
Check 8 (ABI symbols):     PASS / FAIL / SKIP — [details]
Check 9 (No new warnings): PASS / FAIL / SKIP — [details]
```
