# TASK: Create the conversion PR, immediately merge it, tag, and update tracking.

## Execution Mode
**Autonomous action** — rebase the branch, create the PR, immediately merge it (no human review), tag, and update tracking, then stop.

This prompt operates on a **Firefox source tree**. The target file-pair name is provided above.

> ⚠️ **Fork-Only Rule:** All PRs and pushes MUST target the owner's own Firefox
> fork — NEVER Mozilla's upstream or anyone else's fork. Before pushing, verify
> that `origin` points to your fork:
> ```bash
> git remote get-url origin   # Must NOT contain "mozilla"
> ```
> If `origin` points to an upstream Mozilla repo, stop immediately and
> reconfigure (set `FIREFOX_FORK` and re-run `firefox-sync.sh init`).

## Context
Read the becrabbening documentation:
- [07-PHASE-6-MERGE.md](./07-PHASE-6-MERGE.md) — detailed Phase 6 instructions
- [09-CHECKLIST-TEMPLATE.md](./09-CHECKLIST-TEMPLATE.md) — PR checklist template
- [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md) — rebase window rules

## Workflow

### Step 0: Verify Fork Remote

Before any push, confirm that `origin` is the owner's fork:

```bash
origin_url="$(git remote get-url origin)"
if echo "$origin_url" | grep -qi 'mozilla'; then
    echo "ERROR: origin points to upstream ($origin_url). Refusing to push." >&2
    exit 1
fi
```

### Step 1: PR Title

Use this exact format:

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

### Step 2: PR Description

Copy the checklist from [09-CHECKLIST-TEMPLATE.md](./09-CHECKLIST-TEMPLATE.md) into the PR description. Replace `{name}` with the component name. Check off each verified item.

### Step 3: Rebase and Push

```bash
git fetch origin
git rebase origin/main --autostash
git push --force-with-lease origin oxidize/{name}
```

### Step 4: Create PR and Immediately Merge

Create the PR and merge it in one continuous operation. The PR is **not** subject to human review — it is merged immediately to preserve the record while keeping the pipeline fully automated.

```bash
# Create the PR
gh pr create \
    --base main \
    --head "oxidize/{name}" \
    --title "oxidize({name}): replace {name}.cpp with Rust + C shim" \
    --body-file /tmp/{name}-pr-body.md

# Immediately merge the PR (preserving the PR record and branch)
gh pr merge "oxidize/{name}" \
    --merge \
    --delete-branch=false \
    --admin
```

> **Why `--merge` instead of `--squash` or `--rebase`?** A merge commit preserves
> the full branch history in the PR record. `--delete-branch=false` keeps the
> `oxidize/{name}` branch ref so the work remains browsable.  `--admin` bypasses
> any branch protection rules on the fork since this is our own automated work.

If `gh pr merge` fails (e.g., merge conflicts), fall back to local fast-forward:

```bash
git checkout main
git merge --ff-only oxidize/{name}
git push origin main
```

### Step 5: Tag

```bash
git tag oxidized/{name}
git push origin oxidized/{name}
```

### Step 6: Update Tracking

Mark the file-pair as "Merged" in the tracking spreadsheet or TARGETS.md.

### Step 7: Deferred Cleanup

Do NOT do the following in this PR. Create a separate future PR:
- Delete the original `{name}.cpp` or `{name}.c` file
- Optionally rename `{name}_shim.h` → `{name}.h`

The cleanup PR should have title: `cleanup({name}): remove empty cpp/c after oxidation`

## Output Artifacts
- [ ] Branch rebased onto trunk and pushed
- [ ] PR created via `gh pr create`
- [ ] PR immediately merged via `gh pr merge` (no human review)
- [ ] Branch `oxidize/{name}` preserved (not deleted)
- [ ] Tag `oxidized/{name}` created and pushed
- [ ] Tracking updated to "Merged"
- [ ] Cleanup PR filed as a follow-up (not included in this PR)

## What NOT to Do
- Do **not** push to or create PRs against upstream Mozilla or anyone else's fork.
- Do **not** wait for human review — merge immediately after PR creation.
- Do **not** delete the `oxidize/{name}` branch — keep it for the PR record.
- Do **not** delete source files in this PR.
- Do **not** rename files in this PR.
- Do **not** combine cleanup with the conversion.
