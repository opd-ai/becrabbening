# 🦀 The Becrabbening

> **Everything returns to crab.**

A systematic methodology for incrementally replacing C++ and C in Firefox with Rust — one file-pair at a time — while maintaining full backward-compatibility and avoiding merge conflicts.

---

## What Is This?

The Becrabbening is a conflict-free workflow for converting Firefox C/C++ code to Rust. The key insight is a **three-layer sandwich** architecture that lets you swap out the C/C++ internals of any file-pair without touching a single existing caller:

```
┌──────────────────────────────────────────┐
│  Existing C/C++ callers (unchanged)      │
├──────────────────────────────────────────┤
│  Layer 3: C/C++ Shim (backward compat)   │
├──────────────────────────────────────────┤
│  Layer 2: C FFI    (ABI boundary)        │
├──────────────────────────────────────────┤
│  Layer 1: Rust     (the real logic)      │
└──────────────────────────────────────────┘
```

Each iteration converts exactly **one file-pair** (`.cpp` + `.h`, `.c` + `.h`, or just `.h`) through 7 phases (0–6). The workflow is designed to avoid merge conflicts at all costs by using additive-only changes for new files and minimal atomic edits to existing files.

---

## Core Principles

| Principle | Description |
|---|---|
| **One pair at a time** | Each PR converts exactly one `.cpp`+`.h`, `.c`+`.h`, or `.h`-only file-pair. Never bundle multiple conversions. |
| **Additive before subtractive** | New files are created first (zero conflict risk). Existing files are edited last, minimally. Deletions are deferred. |
| **Three-layer sandwich** | Rust → C FFI → C/C++ Shim. Callers never know anything changed. |
| **Zero conflict tolerance** | If a conflict could arise, the workflow is redesigned to eliminate it, not work around it. |
| **Leaf-first ordering** | Always convert files with no unconverted dependents first. Work up the dependency tree. |
| **Independently revertable** | Every PR can be reverted cleanly without affecting other conversions. |

---

## Documentation

| # | Document | Phase | Summary |
|---|---|---|---|
| — | [ROADMAP.md](./ROADMAP.md) | Planning | Milestones, target selection strategy, parallelization rules |
| — | [00-OVERVIEW.md](./00-OVERVIEW.md) | Overview | Full loop at a glance, flowchart, file layout diagrams |
| 0 | [01-PHASE-0-PREPARE.md](./01-PHASE-0-PREPARE.md) | Prepare | Freeze target, snapshot API surface, write contract tests |
| 1 | [02-PHASE-1-RUST.md](./02-PHASE-1-RUST.md) | Rust | Implement idiomatic Rust replacement, FFI exports |
| — | [02b-ANTI-SLOP-AUDIT.md](./02b-ANTI-SLOP-AUDIT.md) | Anti-Slop Audit | Detect and fix AI-generated slop patterns in Rust code |
| 2 | [03-PHASE-2-C-FFI.md](./03-PHASE-2-C-FFI.md) | C FFI | Generate pure-C header via cbindgen |
| 3 | [04-PHASE-3-CPP-SHIM.md](./04-PHASE-3-CPP-SHIM.md) | C/C++ Shim | Build C/C++ wrapper with identical public API |
| 4 | [05-PHASE-4-SWITCHOVER.md](./05-PHASE-4-SWITCHOVER.md) | Switchover | Minimal atomic edit to redirect existing files |
| 5 | [06-PHASE-5-VALIDATE.md](./06-PHASE-5-VALIDATE.md) | Validate | Prove correctness, ABI compatibility, no regressions |
| 6 | [07-PHASE-6-MERGE.md](./07-PHASE-6-MERGE.md) | Merge | Create PR, auto-merge, tag, defer cleanup |
| — | [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md) | Rules | Seven rules for eliminating merge conflicts |
| — | [09-CHECKLIST-TEMPLATE.md](./09-CHECKLIST-TEMPLATE.md) | Template | Copy-paste PR checklist for every oxidation PR |

---

## Worked Example (`nsFoo`)

A complete worked example lives in [`examples/nsfoo/`](./examples/nsfoo/):

| File | Description |
|---|---|
| [`examples/nsfoo/lib.rs`](./examples/nsfoo/lib.rs) | Layer 1: Rust implementation |
| [`examples/nsfoo/cbindgen.toml`](./examples/nsfoo/cbindgen.toml) | cbindgen configuration |
| [`examples/nsfoo/nsfoo_ffi.h`](./examples/nsfoo/nsfoo_ffi.h) | Layer 2: Generated C FFI header |
| [`examples/nsfoo/nsfoo_shim.h`](./examples/nsfoo/nsfoo_shim.h) | Layer 3: C++ shim header |
| [`examples/nsfoo/nsFoo.h`](./examples/nsfoo/nsFoo.h) | Original header after switchover |
| [`examples/nsfoo/nsFoo.cpp`](./examples/nsfoo/nsFoo.cpp) | Original source after switchover |

---

## Quick Start

1. Read [00-OVERVIEW.md](./00-OVERVIEW.md) for the full picture
2. Check [ROADMAP.md](./ROADMAP.md) to select your target file-pair
3. Copy [09-CHECKLIST-TEMPLATE.md](./09-CHECKLIST-TEMPLATE.md) into your PR description
4. Follow phases 0–6 in order

---

## Why "Becrabbening"?

[Carcinization](https://en.wikipedia.org/wiki/Carcinisation) is the evolutionary tendency of crustaceans to independently converge on a crab-like body plan — nature's way of saying crabs are optimal. The Rust community adopted this as a meme: everything eventually gets rewritten in Rust. The Becrabbening is that process, made systematic and safe for a large codebase.

---

## License

MIT — see [LICENSE](./LICENSE).
