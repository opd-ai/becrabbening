# TASK: Perform the minimal atomic edit to existing files that redirects them to the Rust-backed shim.

## Execution Mode
**Autonomous action** — edit the original `.h` and `.cpp`, update `moz.build`, verify diff sizes, create a single atomic commit, then stop.

This prompt operates on a **Firefox source tree**. The target file-pair name is provided above.

> ⚠️ **This is the ONLY phase that modifies existing files.** All previous phases were purely additive.

## Context
Read the becrabbening documentation:
- [05-PHASE-4-SWITCHOVER.md](./05-PHASE-4-SWITCHOVER.md) — detailed Phase 4 instructions
- [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md) — why complete replacement avoids conflicts
- [00-OVERVIEW.md](./00-OVERVIEW.md) — architecture overview

## Workflow

### Step 1: Edit `{name}.h`

Replace the **entire** file contents with just the include guard and a single `#include` redirect:

```cpp
#pragma once
#include "{name}_shim.h"
```

If the original used a traditional include guard, preserve that style:

```cpp
#ifndef {NAME}_H
#define {NAME}_H
#include "{name}_shim.h"
#endif  // {NAME}_H
```

The resulting diff should show: **many deletions, 1–2 additions**.

### Step 2: Edit `{name}.cpp`

Replace the **entire** file contents with a comment and a single include:

```cpp
// Implementation now lives in rust/{name}/src/lib.rs
#include "{name}.h"
```

The resulting diff should show: **many deletions, 2 additions**.

The `.cpp` is kept (not deleted) to preserve build-system compatibility. Deletion is deferred to a cleanup PR.

### Step 3: Update `moz.build`

Add the Rust crate to the build. The total diff to `moz.build` should be **fewer than 5 lines**:

```python
RUST_LIBRARY_FEATURES += ["{name}"]
```

If the `moz.build` change requires more than 5 lines, stop and split it into a separate PR.

### Step 4: Verify Diff Sizes

```bash
git diff --stat
```

Expected:
- `{name}.h` — many deletions, 1–2 insertions
- `{name}.cpp` — many deletions, 2 insertions
- `moz.build` — 0 deletions, fewer than 5 insertions

If the diff is larger than expected, review the shim for completeness.

### Step 5: Atomic Commit

All edits must be in a **single commit**:

```bash
git add {name}.h {name}.cpp moz.build
git commit -m "oxidize({name}): switchover to Rust implementation via shim"
```

Never split Phase 4 edits across multiple commits.

## Output Artifacts
- [ ] `{name}.h` modified: contains only `#include "{name}_shim.h"` (plus include guard)
- [ ] `{name}.cpp` modified: contains only `#include "{name}.h"` (plus comment)
- [ ] `moz.build` updated: Rust crate and shim added (< 5 line diff)
- [ ] All three changes in a single atomic commit

## What NOT to Do
- Do **not** delete the old files. Deletion is deferred to a cleanup PR.
- Do **not** rename files. Renames are the most conflict-prone git operation.
- Do **not** change any files other than `{name}.h`, `{name}.cpp`, and `moz.build`.
- Do **not** combine Phase 4 edits with Phase 3 additions in the same commit.
