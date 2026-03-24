# Usage Guide

How to run the becrabbening loop — the automated pipeline that converts Firefox C/C++ file-pairs to Rust one at a time.

---

## Prerequisites

Install these tools before starting:

| Tool | Purpose |
|------|---------|
| **bash** | Shell (all scripts require Bash, not POSIX sh) |
| **cargo** | Build and test Rust crates |
| **cbindgen** | Generate C FFI headers from Rust |
| **gcc** | Validate generated C headers |
| **g++** | Validate C++ shim headers |
| **copilot** | GitHub Copilot CLI — runs the AI-driven phase prompts |
| **gh** *(optional)* | GitHub CLI — enables the open-PR conflict gate |

---

## Step 1 — Fork Firefox and set up the submodule

> ⚠️ **Fork-Only Rule:** All work, PRs, and pushes must target your own Firefox
> fork — never upstream Mozilla. See [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md#rule-8-fork-only-prs).

First, [fork](https://docs.github.com/en/get-started/quickstart/fork-a-repo) the Firefox repository on GitHub. Then set `FIREFOX_FORK` to your fork's URL:

```bash
export FIREFOX_FORK=https://github.com/YOUR_USERNAME/firefox
bash firefox-sync.sh init
```

This clones your fork as a submodule into `firefox/` and adds upstream Mozilla as a read-only remote for syncing. Only needed once.

---

## Step 2 — Generate conversion targets

```bash
bash generate-targets.sh
```

This scans the Firefox source tree, builds a dependency graph, identifies leaf-node C/C++ file-pairs, and writes `TARGETS.md`.

Review `TARGETS.md` before continuing — remove or reorder entries as needed.

**Environment overrides:**

| Variable | Default | Description |
|----------|---------|-------------|
| `SOURCE_DIR` | `firefox/` | Firefox source tree to scan |
| `MAX_TARGETS` | `20` | Maximum pending targets to include |
| `OUTPUT_FILE` | `TARGETS.md` | Output file path |
| `SKIP_PR_CHECK` | `0` | Set to `1` to skip the open-PR conflict gate |

---

## Step 3 — Run the loop

```bash
bash loop.sh
```

The loop reads `TARGETS.md` and processes each unchecked target through Phases 0–6:

| Phase | Prompt | What happens |
|-------|--------|-------------|
| 0 | `PREPARE.md` | Snapshot API, write contract tests |
| 1 | `RUST.md` | Implement Rust replacement + FFI exports |
| — | `ANTI_SLOP.md` | Audit Rust code for AI slop patterns, fix violations |
| 2 | `C_FFI.md` | Generate C header via cbindgen |
| 3 | `CPP_SHIM.md` | Build C++ shim with identical API |
| 4 | `SWITCHOVER.md` | Redirect original files to the shim |
| 5 | `VALIDATE.md` | Run all tests, verify ABI compatibility |
| 6 | `MERGE.md` | Create PR, merge, tag |

After each of Phases 1–3 and 5, and the anti-slop audit, the script runs automated validation (cargo test, gcc/g++ syntax checks, contract tests). If validation fails, it delegates `FAIL.md` for a fix attempt, then re-validates. If the fix doesn't work, the target is skipped and left unchecked in `TARGETS.md` for retry.

**Environment overrides:**

| Variable | Default | Description |
|----------|---------|-------------|
| `PROMPT_DIR` | `prompts/` | Directory containing the `.md` prompt files |
| `MAX_TARGETS` | `50` | Maximum targets to process in one run |
| `FIREFOX_DIR` | `firefox` | Path to the Firefox submodule |

---

## Interrupting and resuming

Press **Ctrl+C** at any time. The loop prints a summary and exits. Targets that haven't been marked complete stay unchecked in `TARGETS.md`.

Re-run `bash loop.sh` to resume from where you left off. Already-completed targets (checked `[x]`) are skipped automatically.

---

## Syncing with upstream Firefox

Between iterations the loop automatically syncs the submodule. You can also sync manually:

```bash
bash firefox-sync.sh sync      # fast-forward to latest upstream
bash firefox-sync.sh status    # show submodule state, branches, tags
```

---

## End-to-end example

```bash
# First-time setup (fork Firefox on GitHub first!)
export FIREFOX_FORK=https://github.com/YOUR_USERNAME/firefox
bash firefox-sync.sh init

# Generate targets
bash generate-targets.sh

# Review and edit TARGETS.md as needed, then start the loop
bash loop.sh

# Check progress at any time
bash firefox-sync.sh status
```

---

## Logs

The loop writes detailed logs to `loop.log` and per-target test output to `test-output.txt` (cleaned up on completion).

---

## Further reading

- [00-OVERVIEW.md](./00-OVERVIEW.md) — Architecture and phase flowchart
- [ROADMAP.md](./ROADMAP.md) — Target selection strategy and milestones
- [09-CHECKLIST-TEMPLATE.md](./09-CHECKLIST-TEMPLATE.md) — PR checklist template
- [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md) — Conflict-avoidance rules
- [AUDIT-REPORT.md](./AUDIT-REPORT.md) — Workflow audit findings and status
