# Merge-Conflict Avoidance Rules

Merge conflicts are the #1 risk to any incremental C/C++ → Rust conversion. A conflict in a widely-included header can block the entire conversion effort and force painful three-way merges across dozens of files. The Becrabbening workflow is designed from the ground up to eliminate this risk, not just reduce it.

This document enumerates the seven rules that make conflict-free conversion possible.

See also: [00-OVERVIEW.md](./00-OVERVIEW.md) for the overall architecture, [05-PHASE-4-SWITCHOVER.md](./05-PHASE-4-SWITCHOVER.md) for the minimal edit strategy, and [ROADMAP.md](./ROADMAP.md) for serialization rules.

---

## Rule 1: One-Pair-at-a-Time Serialization

Before starting `oxidize/bar`, verify all of the following at the **conflict gate**:

- [ ] `oxidize/foo` (if a prerequisite) is merged and tagged with `git tag oxidized/foo`
- [ ] No open PR anywhere in the repository touches `bar.h`, `bar.cpp`, or `bar.c`
- [ ] Trunk (`origin/main`) is green — all CI checks pass

```
                    ┌──────────────────────────┐
                    │     CONFLICT GATE        │
                    │                          │
    START  ────────►│  oxidize/foo merged?  Y  ├──────► begin oxidize/bar
                    │  No open PR on bar.*? Y  │
                    │  Trunk green?         Y  │
                    │                          │
                    │  Any answer is N?        ├──────► STOP. Wait.
                    └──────────────────────────┘
```

**How to check for open PRs on a file:**

```bash
gh pr list --state open --json headRefName,files \
    --jq '.[] | select(.files[].path | test("{name}"))'
```

If any prerequisite answer is "No", do not proceed. Wait for the prerequisite to resolve.

---

## Rule 2: Additive Before Subtractive

The most powerful conflict-avoidance technique is to not touch existing files until the very last moment.

| Phase | Operation | Conflict Risk |
|---|---|---|
| 0 — Prepare | Add test files | Zero |
| 1 — Rust | Add `rust/{name}/` | Zero |
| 2 — C FFI | Add `{name}_ffi.h` | Zero |
| 3 — C++ Shim | Add `{name}_shim.h` | Zero |
| 4 — Switchover | **Edit** `{name}.h`, `{name}.cpp`/`{name}.c`, `moz.build` | Minimal |
| 6 — Cleanup | **Delete** `{name}.cpp`/`{name}.c` | Deferred |

New files cannot conflict with anything. They simply don't exist yet in anyone else's branch. Only when we edit existing files (Phase 4) does conflict risk appear — and Rule 5 below explains how to minimize it.

---

## Rule 3: Never Touch Shared Build Files in the Same PR as Logic

`moz.build` and similar build system files are edited by every developer constantly. If a conversion PR makes a large change to `moz.build`, it will conflict with nearly every other in-flight PR.

**The rule:** If the `moz.build` diff is more than 5 lines, split it into a separate PR.

**Two-PR strategy:**

1. **PR A** — "Add Rust build support for `{name}`" — only `moz.build` changes, no logic. Land this first.
2. **PR B** — "oxidize({name}): replace with Rust + C shim" — no `moz.build` changes (already landed).

PR A is trivially rebased if it conflicts because it contains no logic. PR B has no `moz.build` risk.

---

## Rule 4: Rebase Window

Rebase as late as possible — immediately before creating and merging the PR. Since PRs are auto-merged (no human review), there is no separate "before review" step. The rebase and merge happen in one continuous operation.

**Before PR creation and auto-merge:**

```bash
git fetch origin
git rebase origin/main --autostash
git push --force-with-lease origin oxidize/{name}
# Then immediately: gh pr create ... && gh pr merge ...
```

**If a conflict appears at merge time:**

1. `git rebase --abort`
2. Re-read the current `origin/main` version of `{name}.h`
3. Re-apply Phase 4 (gut the file, replace with a single `#include`) — this is a trivial redo because the new content is always just one line
4. Push and re-attempt the PR creation + auto-merge

This works because Phase 4 is a **complete replacement** (see Rule 5), not a patch. Redoing it from scratch is fast and correct regardless of what changed on trunk.

---

## Rule 5: Complete Replacement Over Partial Edit

When Phase 4 modifies `{name}.h`, it replaces the **entire file contents** with a single line. This is deliberately more than necessary — but it is the safest possible edit.

**Why this works:**

A partial edit (removing some methods, adding some methods) is conflict-prone. If another developer edits the same methods on a different branch, git produces a complex three-way merge conflict.

A complete replacement produces a trivial conflict: git sees the old content as fully deleted and a new single line as added. Even if another developer edited the old content, the correct resolution is always the same single `#include` line. There is nothing to merge.

**Intuition:** You can't have a conflict about content that no longer exists.

---

## Rule 6: No Renames, No Deletes in Conversion PRs

File renames and deletes are the most conflict-prone git operations:

- A rename causes conflicts for anyone who has modified the old file
- A delete causes conflicts for anyone who has added to the old file

Both operations are **deferred to a separate cleanup PR** after the conversion is merged and stable. The cleanup PR contains no logic changes — only the structural filesystem change — so it is trivially rebased if it conflicts.

**Forbidden in conversion PRs:**
- `git mv {name}.cpp rust/{name}/`
- `git rm {name}.cpp`
- `git rm {name}.c`
- Renaming `{name}_shim.h` to `{name}.h`

All of these are fine in a follow-up cleanup PR.

---

## Rule 7: Parallel Subtree Independence

Multiple conversions can proceed in parallel if and only if the file-pairs are in **non-overlapping subtrees** of the dependency graph — meaning they share no common header.

**Safe to parallelize:**

```
util/foo.h ───► (no shared headers) ◄─── util/bar.h
  ↑                                            ↑
  |                                            |
oxidize/foo          AND          oxidize/bar  (concurrent, safe)
```

**Must be serialized:**

```
              shared/common.h
             /               \
      util/foo.h           util/bar.h
         ↑                     ↑
         |                     |
  oxidize/foo   THEN   oxidize/bar   (must be sequential)
```

If `util/foo.h` and `util/bar.h` both include `shared/common.h`, and both conversions might modify `shared/common.h` (e.g., to remove an include), they must be serialized. See [ROADMAP.md](./ROADMAP.md) for the dependency graph and parallelization tracking.

---

## Rule 8: Fork-Only PRs

All PRs and pushes must target the **owner's own Firefox fork** — never upstream Mozilla or anyone else's fork. This prevents accidental noise on upstream repositories.

Before any push or PR:

```bash
# Verify origin is your fork
cd firefox && git remote get-url origin
# Must NOT contain "mozilla" — should be your GitHub username/org
```

If `origin` points to upstream, reconfigure:

```bash
FIREFOX_FORK=https://github.com/YOU/firefox bash firefox-sync.sh init
```

See [USAGE.md](./USAGE.md) for setup details.

---

## Emergency Procedures

If a conflict does arise despite all precautions:

1. **Do not resolve the conflict manually in the branch.** Manual resolution is error-prone for large files.
2. **Abort the rebase:** `git rebase --abort`
3. **Identify which of Rules 1–8 was violated** and why.
4. **Re-do Phase 4 from scratch on fresh trunk.** It is always safe because the new content is a single line.
5. **If `moz.build` conflicts:** use the two-PR strategy from Rule 3.
6. **If shim conflicts:** the shim is a new file — it cannot conflict. If it appears to conflict, you may have named it the same as another new file. Rename it.

---

## Cross-References

- [00-OVERVIEW.md](./00-OVERVIEW.md) — full conversion loop
- [05-PHASE-4-SWITCHOVER.md](./05-PHASE-4-SWITCHOVER.md) — the minimal edit strategy
- [07-PHASE-6-MERGE.md](./07-PHASE-6-MERGE.md) — rebase and merge procedures
- [ROADMAP.md](./ROADMAP.md) — dependency graph and serialization tracking
