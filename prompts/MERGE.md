# TASK: Prepare the conversion PR for merge — rebase, create PR, tag, and update tracking.

## Execution Mode
**Autonomous action** — rebase the branch, prepare the PR, verify CI, then stop.

This prompt operates on a **Firefox source tree**. The target file-pair name is provided above.

## Context
Read the becrabbening documentation:
- [07-PHASE-6-MERGE.md](./07-PHASE-6-MERGE.md) — detailed Phase 6 instructions
- [09-CHECKLIST-TEMPLATE.md](./09-CHECKLIST-TEMPLATE.md) — PR checklist template
- [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md) — rebase window rules

## Workflow

### Step 1: PR Title

Use this exact format:

```
oxidize({name}): replace {name}.cpp with Rust + C shim
```

For header-only conversions:

```
oxidize({name}): replace {name}.h with Rust + C shim
```

### Step 2: PR Description

Copy the checklist from [09-CHECKLIST-TEMPLATE.md](./09-CHECKLIST-TEMPLATE.md) into the PR description. Replace `{name}` with the component name. Check off each verified item.

### Step 3: Rebase Before Review

```bash
git fetch origin
git rebase origin/main --autostash
git push --force-with-lease origin oxidize/{name}
```

Verify CI passes on the rebased branch.

### Step 4: Rebase Before Merge

Rebase again within 1 hour of merging:

```bash
git fetch origin
git rebase origin/main --autostash
git push --force-with-lease origin oxidize/{name}
```

### Step 5: Merge (Fast-Forward Only)

```bash
git checkout main
git merge --ff-only oxidize/{name}
git push origin main
```

No merge commits. If `--ff-only` fails, rebase again and retry.

### Step 6: Tag

```bash
git tag oxidized/{name}
git push origin oxidized/{name}
```

### Step 7: Update Tracking

Mark the file-pair as "Merged" in the tracking spreadsheet or TARGETS.md.

### Step 8: Deferred Cleanup

Do NOT do the following in this PR. Create a separate future PR:
- Delete the original `{name}.cpp` file
- Optionally rename `{name}_shim.h` → `{name}.h`

The cleanup PR should have title: `cleanup({name}): remove empty cpp after oxidation`

## Output Artifacts
- [ ] Branch rebased onto trunk within 1 hour of merge
- [ ] Merge uses `--ff-only` — no merge commits
- [ ] Tag `oxidized/{name}` created and pushed
- [ ] Tracking updated to "Merged"
- [ ] Cleanup PR filed as a follow-up (not included in this PR)

## What NOT to Do
- Do **not** delete files in this PR.
- Do **not** rename files in this PR.
- Do **not** combine cleanup with the conversion.
