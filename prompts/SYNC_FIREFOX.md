# TASK: Manage the Firefox submodule — sync with upstream, verify state, resolve conflicts.

## Execution Mode
**Autonomous action** — perform the requested submodule operation and report results.

## Context
Read the becrabbening documentation:
- [00-OVERVIEW.md](./00-OVERVIEW.md) — architecture overview
- [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md) — conflict rules and rebase strategy

The Firefox source tree is maintained as a git submodule at `firefox/`.
Use `firefox-sync.sh` for all submodule operations.

## Operations

### Sync with Upstream

Update the Firefox submodule to the latest upstream commit:

```bash
bash firefox-sync.sh sync
```

This fetches from upstream, fast-forwards (or rebases) the local main branch,
and updates the submodule reference in the parent repo.

### Resolve Submodule Conflicts

If the submodule reference conflicts during a rebase:

1. Check the current state:
   ```bash
   bash firefox-sync.sh status
   ```

2. If on an oxidize branch, the branch work must be completed or stashed first.

3. Sync to get back to a clean state:
   ```bash
   bash firefox-sync.sh sync
   ```

4. If conflicts persist in the submodule itself:
   ```bash
   cd firefox/
   git fetch upstream main
   git rebase upstream/main
   # Resolve any conflicts, then:
   git rebase --continue
   cd ..
   git add firefox
   git commit -m "chore: resolve Firefox submodule conflict"
   ```

### Pre-Loop Verification

Before starting `loop.sh`, verify the submodule is ready:

```bash
bash firefox-sync.sh status
```

Expected output:
- Submodule: configured and initialized
- Branch: main (not on an oxidize branch)
- Working tree: clean

If the branch is not `main`, switch back:
```bash
cd firefox/ && git checkout main && cd ..
```

## Output Artifacts
- [ ] Firefox submodule synced to latest upstream
- [ ] Submodule reference committed in parent repo
- [ ] Working tree clean

## What NOT to Do
- Do **not** force-push in the Firefox submodule without verifying state.
- Do **not** delete oxidize branches that haven't been merged.
- Do **not** modify Firefox source files in this task — syncing only.
