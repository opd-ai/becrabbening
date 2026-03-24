# Roadmap — The Becrabbening

Planning document for the systematic conversion of Firefox C/C++ to Rust.

See [00-OVERVIEW.md](./00-OVERVIEW.md) for the full conversion loop, and [01-PHASE-0-PREPARE.md](./01-PHASE-0-PREPARE.md) for how each iteration begins.

---

## Milestones

### M0 — Tooling & Infrastructure

**Goal:** Establish the scaffolding needed before any conversions begin.

- [ ] Integrate `cbindgen` into the Firefox build system (`moz.build` templates)
- [ ] Create CI templates for oxidation PRs (contract test runner, ABI symbol diff)
- [ ] Document and enforce naming conventions (`fox_{name}_*` FFI prefix)
- [ ] Set up tracking spreadsheet (see [Tracking](#tracking) below)
- [ ] Validate the full workflow end-to-end on a trivial file-pair

**Definition of Done:** A CI-verified end-to-end conversion of one leaf-node utility passes all checks.

---

### M1 — Leaf Nodes: Standalone Utilities

**Target:** Isolated utility files with no downstream dependents (or whose only dependents are already converted).

Examples: small string helpers, math utilities, standalone data-structure implementations.

**Why first?** Leaf nodes have no dependencies on unconverted code. A leaf-node conversion PR is guaranteed to have zero downstream impact.

**Definition of Done:** All identified leaf-node file-pairs are converted, merged, and tagged. Trunk builds and tests remain green.

---

### M2 — Mid-Tree: Shared Components

**Target:** Files with moderate fan-in (used by several other files), after all their dependents have been converted via M1.

Examples: utility classes used across multiple subsystems, shared data structures.

**Definition of Done:** All mid-tree targets converted. Full test suite passes. No C++ code remains in the targeted component subtrees.

---

### M3 — Core: Foundational Headers

**Target:** Widely-included core headers — the last to be converted because they have the highest fan-in.

Examples: base types, fundamental utilities, cross-cutting concerns.

**Definition of Done:** All M3 targets converted. The codebase contains only the thin C++ shim layer as C++ code in converted areas.

---

## Target Selection Strategy

Conversions must follow a **leaf-first topological ordering** of the include dependency graph. Never convert a file before all files that include it (its "callers") are already converted — or before confirming that callers can be updated in the same PR.

```
                  ┌─────────────┐
                  │  core/base  │  ← M3: convert last
                  └──────┬──────┘
             ┌───────────┼───────────┐
      ┌──────┴──────┐         ┌──────┴──────┐
      │  shared/A   │         │  shared/B   │  ← M2
      └──────┬──────┘         └──────┬──────┘
      ┌──────┴──────┐    ┌───────────┴──────┐
      │  util/X     │    │  util/Y  │util/Z  │  ← M1: convert first
      └─────────────┘    └──────────┴────────┘
```

**Conversion ordering rules:**

1. Never convert a file before all its dependents (callers) are converted.
2. Prefer files with a smaller public API surface — less to shim, less to test.
3. Prefer files with existing test coverage — the contract tests are easier to write.

---

## Parallelization Rules

Multiple engineers can work on separate conversions simultaneously, subject to these constraints:

- **Non-overlapping subtrees** in the dependency graph can be converted in parallel. For example, `util/X` and `util/Y` can be converted concurrently if they share no headers.
- **Files sharing a common header** must be serialized. If `util/X` and `util/Y` both include `shared/A.h`, convert them one at a time.
- **Never open two PRs that modify the same file.** Use the conflict gate in [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md) to verify before starting.

---

## Tracking

Maintain a spreadsheet or wiki table with the following columns for every candidate file-pair:

| File Pair | Status | PR Link | Assignee | Dependencies |
|---|---|---|---|---|
| `util/foo.cpp` + `util/foo.h` | Pending | — | — | none |
| `util/bar.cpp` + `util/bar.h` | In Progress | #1234 | @dev | util/foo |
| `shared/baz.h` | Merged | #1100 | @dev2 | util/foo, util/bar |
| `core/qux.c` + `core/qux.h` | Pending | — | — | none |
| `core/quux.cpp` + `core/quux.h` | Cleaned | #1050 | @dev3 | shared/baz |

**Status values:**

- `Pending` — identified as a target, not yet started
- `In Progress` — branch created, PR open
- `Merged` — conversion PR landed, cleanup deferred
- `Cleaned` — cleanup PR (delete old `.cpp`/`.c`) also landed

---

## Cross-References

- [00-OVERVIEW.md](./00-OVERVIEW.md) — the full conversion loop
- [01-PHASE-0-PREPARE.md](./01-PHASE-0-PREPARE.md) — how each iteration starts
- [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md) — conflict gate and serialization rules
