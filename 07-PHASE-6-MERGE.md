# Phase 6 — Create PR, Auto-Merge & Clean Up

**Goal:** Create a PR for the conversion, immediately merge it (preserving the PR record), tag the conversion, and prepare for the next iteration.

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

### Step 3 — Rebase and push

Rebase onto trunk and push the branch:

```bash
git fetch origin
git rebase origin/main --autostash
git push --force-with-lease origin oxidize/{name}
```

### Step 4 — Create PR and immediately merge

Create the PR via `gh` CLI and merge it immediately. This is an automated pipeline — PRs are **not subject to human review**. They are created to preserve a record of each conversion, then merged immediately.

```bash
# Create the PR
gh pr create \
    --base main \
    --head "oxidize/{name}" \
    --title "oxidize({name}): replace {name}.cpp with Rust + C shim" \
    --body-file /tmp/{name}-pr-body.md

# Immediately merge — no human review required
gh pr merge "oxidize/{name}" \
    --merge \
    --delete-branch=false \
    --admin
```

**Why immediate merge?** The conversion has already been validated in Phase 5. The PR exists purely as a record of the change — the full checklist, the branch history, and the merge event are all preserved for traceability. Human review would slow down the automated pipeline without adding value, since all quality gates (contract tests, cargo test, clippy, ABI verification) were already enforced.

**Why `--delete-branch=false`?** The `oxidize/{name}` branch is preserved so the PR record remains browsable and the branch can be referenced by the `oxidized/{name}` tag.

**Why `--admin`?** Bypasses any branch protection rules on the fork, since this is our own automated work on our own fork.

**Fallback — local fast-forward merge:** If `gh pr merge` fails (e.g., the `gh` CLI is unavailable or branch protection cannot be bypassed), fall back to a local merge:

```bash
git checkout main
git merge --ff-only oxidize/{name}
git push origin main
```

No merge commits. The commit history should be linear. If `--ff-only` fails, rebase again (Step 3) and retry.

### Step 5 — Tag after merge

After the merge lands on trunk, tag the conversion:

```bash
git tag oxidized/{name}
git push origin oxidized/{name}
```

This tag is used by the conflict gate in Phase 0 of future iterations to verify that a prerequisite conversion is complete.

### Step 6 — Deferred cleanup (separate PR)

**Do NOT** do the following in this PR. Create a separate, future PR for cleanup:

- Delete the original `{name}.cpp` or `{name}.c` file (it is now empty but kept for build-system compatibility)
- Optionally rename `{name}_shim.h` → `{name}.h` if the shim name is awkward

The cleanup PR should have title: `cleanup({name}): remove empty cpp/c after oxidation`

---

## Why PRs Are Auto-Merged

Every conversion is fully validated before Phase 6:

1. **Phase 0** — contract tests verify the public API.
2. **Phase 1** — `cargo test` and `cargo clippy` verify the Rust implementation.
3. **Anti-slop audit** — pedantic linting catches AI-generated code smells.
4. **Phase 2** — `gcc -xc -fsyntax-only` verifies the C FFI header.
5. **Phase 3** — `g++ -xc++ -fsyntax-only` verifies the C++ shim compiles.
6. **Phase 5** — full validation suite: contract tests, ABI symbol diff, `mach build`, `mach test`.

By Phase 6, all quality gates have passed. The PR is created for **traceability** (searchable history, linked branch, checklist record), not for review. Immediate merge keeps the pipeline moving without blocking on human availability.

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
