# Phase 0 — Prepare

**Goal:** Freeze the target, snapshot its API surface, and establish a contract test baseline.

Previous: start of iteration — see [ROADMAP.md](./ROADMAP.md) for target selection.
Next: [02-PHASE-1-RUST.md](./02-PHASE-1-RUST.md) — Rust implementation.

---

## Prerequisites Checklist

Before starting, verify all of the following:

- [ ] No other open PR touches the target files (`{name}.h`, `{name}.cpp`)
- [ ] Trunk (`origin/main`) is green — all CI checks pass
- [ ] The file-pair is a leaf node in the dependency graph, **or** all of its dependents are already converted
- [ ] The tracking spreadsheet (see [ROADMAP.md](./ROADMAP.md)) shows the file-pair as `Pending`

If any prerequisite fails, **stop**. Do not proceed. Resolve the prerequisite first.

---

## Step-by-Step Instructions

### Step 1 — Create the branch

```bash
git fetch origin
git checkout -b oxidize/{name} origin/main
```

Branch naming is fixed: always `oxidize/{name}` where `{name}` is the base name of the file-pair (e.g., `nsFoo` → `oxidize/nsFoo`).

### Step 2 — Verify no concurrent modifications

Confirm no in-flight work touches the same files:

```bash
# Check local branch history
git log --oneline origin/main..HEAD --name-only | grep {name}

# Check all open PRs (requires gh CLI)
gh pr list --state open | grep {name}
```

If any concurrent work is found, **stop** and coordinate with the other author before proceeding. See [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md) for the conflict gate rules.

### Step 3 — Snapshot the public API

List every exported symbol from the `.h` file. For each item, record:

- Class names and their methods (name, parameters, return type, const-ness)
- Free functions (name, parameters, return type)
- Constants and enumerations
- Macros
- Type aliases (`typedef`, `using`)

**Tools:**

```bash
# Enumerate exported symbols from the compiled object
nm -C {name}.o | grep ' T '        # exported text symbols
nm -C {name}.o | grep ' D '        # exported data symbols
objdump -t {name}.o | grep .text   # alternative

# For a header-only file, read the header directly
grep -E '^\s*(class|struct|enum|typedef|using|inline|constexpr|#define)' {name}.h
```

Record the snapshot in a scratch file (e.g., `/tmp/{name}-api-snapshot.txt`) for reference during Rust porting. Do **not** commit this scratch file.

### Step 4 — Write contract tests

Create a test file (e.g., `test_{name}_contract.cpp`) that exercises every public symbol identified in Step 3. These tests must:

1. **Compile and pass before any changes** — run them now to verify
2. **Continue to compile and pass after conversion** — they are your correctness proof

Test requirements:
- Instantiate every class
- Call every public method with representative inputs
- Verify return values for at least the normal case
- Check that constants have the expected values

**Important:** Do not test implementation details, only the public API contract.

```bash
# Compile and run contract tests against the original C++ implementation
g++ -std=c++17 test_{name}_contract.cpp {name}.cpp -o test_{name}_contract
./test_{name}_contract
```

### Step 5 — Document the API surface

Write a concise summary of the public API in a comment block at the top of your contract test file. This serves as a reference when writing the Rust implementation in Phase 1. For example:

```cpp
// CONTRACT: nsFoo API Surface
// class nsFoo
//   nsFoo(int initial)          — constructor
//   int Bar(int x) const        — returns value_ + x (wrapping)
//   void SetValue(int v)        — sets value_
```

---

## Header-Only Variant

For `.h`-only files (no corresponding `.cpp`), the same process applies with these adjustments:

- There is no compiled object to inspect with `nm` — work from the header directly
- Snapshot all type definitions, inline functions, macros, and constants
- Contract tests may be compile-only (`static_assert`) for type-level guarantees
- There is no `.cpp` to empty out in Phase 4 — only the `.h` will be modified

---

## What NOT to Do

- **Do not modify any source files in this phase.** Phase 0 is read-only with respect to the codebase. The only files you create are test files and scratch notes.
- Do not start Phase 1 until the contract tests are passing.

---

## Output Artifacts

At the end of Phase 0, you should have:

- [ ] Branch `oxidize/{name}` created from a green trunk
- [ ] Contract tests written (`test_{name}_contract.cpp`) and passing
- [ ] API surface documented (in a comment in the test file)

---

## Cross-References

- [00-OVERVIEW.md](./00-OVERVIEW.md) — architecture context and full loop
- [02-PHASE-1-RUST.md](./02-PHASE-1-RUST.md) — next phase
- [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md) — conflict gate and freeze rules
- [ROADMAP.md](./ROADMAP.md) — target selection and prerequisites
