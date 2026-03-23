# TASK: Prepare the target file-pair for oxidation — freeze, snapshot the API, and write contract tests.

## Execution Mode
**Autonomous action** — complete all preparation steps, validate contract tests, then stop.

This prompt operates on a **Firefox source tree**. The target file-pair name is provided above.

## Context
Read the becrabbening documentation to understand the full workflow:
- [00-OVERVIEW.md](./00-OVERVIEW.md) — architecture overview and three-layer sandwich
- [01-PHASE-0-PREPARE.md](./01-PHASE-0-PREPARE.md) — detailed Phase 0 instructions
- [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md) — conflict gate rules
- [examples/nsfoo/](./examples/nsfoo/) — complete worked example

## Workflow

### Phase 0: Identify the Target
1. Read `CURRENT_TARGET.md` or the target name provided at the top of this prompt. This is `{name}` for all subsequent steps.
2. Locate `{name}.h` and `{name}.cpp` in the source tree.
3. If only `{name}.h` exists (header-only), note this for later phases.

### Phase 1: Prerequisites Check
Verify all of the following before proceeding:
1. No other open PR touches `{name}.h` or `{name}.cpp`.
2. Trunk (`origin/main`) is green — CI passes.
3. The file-pair is a leaf node in the dependency graph, or all its dependents are already converted.

If any prerequisite fails, **stop** and report the blocker. Do not proceed.

### Phase 2: Create the Branch
```bash
git fetch origin
git checkout -b oxidize/{name} origin/main
```

### Phase 3: Snapshot the Public API
List every exported symbol from `{name}.h`. For each item, record:
- Class names and their methods (name, parameters, return type, const-ness)
- Free functions (name, parameters, return type)
- Constants and enumerations
- Macros
- Type aliases (`typedef`, `using`)

Tools:
```bash
nm -C {name}.o | grep ' T '
grep -E '^\s*(class|struct|enum|typedef|using|inline|constexpr|#define)' {name}.h
```

Record the snapshot in `/tmp/{name}-api-snapshot.txt` for reference. Do **not** commit this file.

### Phase 4: Write Contract Tests
Create `test_{name}_contract.cpp` that exercises every public symbol from Phase 3:
1. Instantiate every class.
2. Call every public method with representative inputs.
3. Verify return values for normal cases.
4. Check that constants have expected values.

Test only the **public API contract**, not implementation details.

```bash
g++ -std=c++17 test_{name}_contract.cpp {name}.cpp -o test_{name}_contract
./test_{name}_contract
```

Contract tests must compile and pass before proceeding.

### Phase 5: Document the API Surface
Write a concise API summary as a comment block at the top of the contract test file:

```cpp
// CONTRACT: {name} API Surface
// class {Name}
//   {Name}(args)          — constructor description
//   ReturnType Method()   — method description
```

## Output Artifacts
At the end of this task, you should have:
- [ ] Branch `oxidize/{name}` created from a green trunk
- [ ] Contract tests written (`test_{name}_contract.cpp`) and passing
- [ ] API surface documented (in a comment in the test file)

## What NOT to Do
- Do **not** modify any source files. Phase 0 is read-only with respect to the codebase.
- Do **not** start any Rust implementation.
- Do **not** commit scratch files or API snapshots.
