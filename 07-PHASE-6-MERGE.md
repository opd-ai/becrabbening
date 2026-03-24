# Phase 6 — Merge & Clean Up

**Goal:** Safely land the PR and prepare for the next iteration.

Previous: [06-PHASE-5-VALIDATE.md](./06-PHASE-5-VALIDATE.md) — validation.
Next: Return to [01-PHASE-0-PREPARE.md](./01-PHASE-0-PREPARE.md) for the next file-pair.

---

## Step-by-Step Instructions

> ⚠️ **Fork-Only Rule:** PRs and pushes must **only** target your own Firefox
> fork — never Mozilla's upstream repository or anyone else's fork.
> Verify that `origin` points to your fork before pushing:
> ```bash
> cd firefox && git remote get-url origin
> ```
> If it shows a `mozilla` URL, reconfigure with `FIREFOX_FORK` (see [USAGE.md](./USAGE.md)).

### Step 1 — PR title convention

Use this exact format for the PR title:

```
oxidize({name}): replace {name}.cpp with Rust + C shim
```

For C source conversions:

```
oxidize({name}): replace {name}.c with Rust + C shim
```

For header-only conversions:

```
oxidize({name}): replace {name}.h with Rust + C shim
```

### Step 2 — PR description

Copy the checklist from [09-CHECKLIST-TEMPLATE.md](./09-CHECKLIST-TEMPLATE.md) into the PR description. Fill in `{name}` with the component name. Check off each item as you verify it.

### Step 3 — Rebase before requesting review

Rebase onto trunk immediately before requesting review:

```bash
git fetch origin
git rebase origin/main --autostash
```

Push the rebased branch:

```bash
git push --force-with-lease origin oxidize/{name}
```

Verify the CI passes on the rebased branch before requesting review.

### Step 4 — Rebase again immediately before merge

Rebase again within 1 hour of merging:

```bash
git fetch origin
git rebase origin/main --autostash
git push --force-with-lease origin oxidize/{name}
```

This minimizes the window during which trunk can diverge and cause a conflict. See [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md) for the rebase window rules.

### Step 5 — Merge using fast-forward only

```bash
git checkout main
git merge --ff-only oxidize/{name}
git push origin main
```

No merge commits. The commit history should be linear. If `--ff-only` fails, rebase again (Step 4) and retry.

### Step 6 — Tag after merge

After the merge lands on trunk, tag the conversion:

```bash
git tag oxidized/{name}
git push origin oxidized/{name}
```

This tag is used by the conflict gate in Phase 0 of future iterations to verify that a prerequisite conversion is complete.

### Step 7 — Deferred cleanup (separate PR)

**Do NOT** do the following in this PR. Create a separate, future PR for cleanup:

- Delete the original `{name}.cpp` or `{name}.c` file (it is now empty but kept for build-system compatibility)
- Optionally rename `{name}_shim.h` → `{name}.h` if the shim name is awkward

The cleanup PR should have title: `cleanup({name}): remove empty cpp/c after oxidation`

---

## Why Cleanup Is Deferred

Separating the functional change (Phases 0–5) from file deletion/renaming has two benefits:

1. **Each PR is independently revertable.** If a regression is found after merge, reverting the conversion PR is clean — there are no deletion/rename changes mixed in.
2. **Deletion PRs are trivial to resolve if they conflict.** A PR that only deletes an empty file has no logic changes, so any conflict with another PR is trivially resolved.

---

## Post-Merge Verification

After the PR lands on trunk, pull and verify:

```bash
git checkout main
git pull origin main
./mach build && ./mach test
```

If anything fails post-merge, file a follow-up issue immediately and consider a revert.

---

## Update Tracking

Mark the file-pair as "Merged" in the tracking spreadsheet (see [ROADMAP.md](./ROADMAP.md) — Tracking section).

---

## Picking the Next Target

Return to [ROADMAP.md](./ROADMAP.md) and select the next leaf-node file-pair. Verify the conflict gate (see [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md)) and begin Phase 0.

---

## Cross-References

- [06-PHASE-5-VALIDATE.md](./06-PHASE-5-VALIDATE.md) — previous phase (validation)
- [01-PHASE-0-PREPARE.md](./01-PHASE-0-PREPARE.md) — start the next iteration
- [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md) — rebase window and conflict rules
- [09-CHECKLIST-TEMPLATE.md](./09-CHECKLIST-TEMPLATE.md) — PR checklist
- [ROADMAP.md](./ROADMAP.md) — tracking and next target selection
- [00-OVERVIEW.md](./00-OVERVIEW.md) — architecture overview
