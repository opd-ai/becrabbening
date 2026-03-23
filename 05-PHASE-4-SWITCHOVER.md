# Phase 4 — Switchover

> ⚠️ **This is the ONLY phase that modifies existing files.** ⚠️
>
> All previous phases were purely additive. This phase makes the minimal possible edit to existing files to redirect them to the new Rust-backed implementation. Keep edits as small as possible.

**Goal:** Perform the minimal atomic edit to existing files that redirects them to the new Rust-backed shim.

Previous: [04-PHASE-3-CPP-SHIM.md](./04-PHASE-3-CPP-SHIM.md) — C++ shim layer.
Next: [06-PHASE-5-VALIDATE.md](./06-PHASE-5-VALIDATE.md) — Validation.

---

## Step-by-Step Instructions

### Step 1 — Edit the original `{name}.h`

Gut the entire body of the header. Replace the entire file contents with just the include guard and a single `#include` redirect:

```cpp
// Before: hundreds of lines of class definitions, method declarations, etc.

// After:
#pragma once
#include "{name}_shim.h"
```

The resulting diff should show: **many deletions, 1–2 additions**.

If the original used a traditional include guard instead of `#pragma once`, preserve that style:

```cpp
#ifndef {NAME}_H
#define {NAME}_H
#include "{name}_shim.h"
#endif  // {NAME}_H
```

### Step 2 — Edit the original `{name}.cpp`

Gut the entire body of the source file. Replace with just a comment and a single include:

```cpp
// Implementation now lives in rust/{name}/src/lib.rs
#include "{name}.h"
```

The resulting diff should show: **many deletions, 2 additions**.

The `.cpp` file is kept (not deleted) to preserve build-system compatibility — the build system already knows about this file. Deleting it is deferred to the cleanup PR.

### Step 3 — Update `moz.build`

Add the Rust crate to the build, the shim source files, and the cbindgen header generation step. The total diff to `moz.build` should be **fewer than 5 lines**:

```python
# Add to moz.build:
RUST_LIBRARY_FEATURES += ["{name}"]

# Or for a standalone Rust crate:
LOCAL_INCLUDES += ["{name}_ffi.h"]
```

If the `moz.build` change requires more than 5 lines, split it into a separate PR first. See [Rule 3 in 08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md#rule-3-never-touch-shared-build-files-in-the-same-pr-as-logic).

### Step 4 — Verify the diff sizes

```bash
git diff --stat

# Expected:
# {name}.h     | 80 deletions, 2 insertions
# {name}.cpp   | 40 deletions, 2 insertions
# moz.build    | 0 deletions, 3 insertions
```

If the diff is larger than expected, review whether the shim is complete and correct.

### Step 5 — Atomic commit

All three file edits must be in a **single commit**:

```bash
git add {name}.h {name}.cpp moz.build
git commit -m "oxidize({name}): switchover to Rust implementation via shim"
```

Never split Phase 4 edits across multiple commits.

---

## Why This Minimizes Conflicts

The edit to `{name}.h` is a **complete replacement** of file contents, not a partial edit. From git's perspective:

- It sees the old content deleted and a single new line added.
- There is nothing to conflict with on the new line — it is just an `#include`.
- Even if another developer adds to the original `{name}.h` simultaneously, when that PR is rebased or merged, the conflict resolution is trivial: the correct resolution is always the single `#include` line.

Compare this to a **partial edit** (removing some methods, adding some methods), where git may produce complex three-way merge conflicts. The complete replacement avoids this entirely.

See [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md) for the full explanation (Rule 5).

---

## What NOT to Do

- **Do not delete the old files** in this PR. File deletion is deferred to a separate cleanup PR after merge. Deleting files causes unnecessary conflict risk.
- **Do not rename files.** Renames are the most conflict-prone git operation. Deferred.
- **Do not change any files other than `{name}.h`, `{name}.cpp`, and `moz.build`** in this commit.
- Do not put Phase 4 edits and Phase 3 shim additions in the same commit — keep them as separate commits for bisectability.

---

## Output Artifacts

At the end of Phase 4, you should have:

- [ ] `{name}.h` modified: now contains only `#include "{name}_shim.h"` (plus include guard)
- [ ] `{name}.cpp` modified: now contains only `#include "{name}.h"` (plus a comment)
- [ ] `moz.build` updated: Rust crate and shim added (< 5 line diff)
- [ ] All three changes in a single atomic commit

---

## Cross-References

- [04-PHASE-3-CPP-SHIM.md](./04-PHASE-3-CPP-SHIM.md) — previous phase (C++ shim)
- [06-PHASE-5-VALIDATE.md](./06-PHASE-5-VALIDATE.md) — next phase (validation)
- [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md) — why this approach avoids conflicts
- [00-OVERVIEW.md](./00-OVERVIEW.md) — architecture overview
