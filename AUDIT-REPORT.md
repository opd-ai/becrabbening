# Oxidation Loop Audit Report

Generated: 2026-03-23

---

## Summary Verdict

**PASS WITH WARNINGS** — The becrabbening workflow is logically sound and internally consistent at the documentation layer. Phase numbering, cross-references, and design invariants are all properly maintained. Shell script orchestration is functional and interruptible, but contains several recoverable issues in error propagation, dependency detection, and converted-file identification that could cause incorrect behavior under specific edge conditions.

---

## Findings

### WARNING — Phases 1–3 validation failures do not halt the pipeline

- **Location**: `loop.sh:381-431`
- **Issue**: When `run_validation` fails after Phases 1, 2, or 3 and `FAIL.md` does not fix the problem, the loop logs `"FAIL (persisted)"` but continues unconditionally to the next phase. A target with a broken Rust crate (Phase 1 fail) proceeds through Phases 2–4 producing potentially invalid artifacts. **Mitigating factor**: Phase 5's validation gate (line 454) would catch most such failures (e.g., `cargo test` fails on the broken crate) and the `continue` at line 464 would prevent marking the target complete. However, an edge case exists: if all phases fail to produce _any_ artifacts, `run_validation` conditionally skips all checks (lines 187, 200, 213, 226 — each guarded by file-existence tests) and returns success, allowing the target to reach Phase 6 and be marked complete despite having no valid output.
- **Impact**: In the common case, Phase 5 acts as a safety net. In the edge case where no artifacts are produced, a hollow target can be marked "complete" in `TARGETS.md`, preventing retry. Intermediate phases (2–4) waste Copilot CLI invocations on a broken foundation regardless.
- **Suggested fix**: After the FAIL.md retry at Phases 1–3, if validation still fails, either (a) execute `continue` to skip to the next target (matching Phase 5 behavior), or (b) add a `--strict` mode flag that halts the pipeline on persisted failures at any phase. Additionally, `run_validation` should return failure if _no_ checks were actually executed (no artifacts found to validate).

### WARNING — Converted-file heuristic fails for `#ifndef`/`#define`/`#endif` include guards

- **Location**: `generate-targets.sh:122-133`
- **Issue**: The "already converted" detection counts substantive lines (line 128–129) by excluding only `#pragma` and empty lines. The `#ifndef`, `#define`, and `#endif` directives used in traditional include guards are counted as substantive. For a converted header using traditional guards:
  ```cpp
  #ifndef NSFOO_H
  #define NSFOO_H
  #include "nsfoo_shim.h"
  #endif
  ```
  `substantive_lines` = 4, `shim_includes` = 1, so `4 > 1` → file is **not** detected as converted. The worked example (`examples/nsfoo/nsFoo.h`) uses `#pragma once`, which works correctly because `#pragma` is excluded.
- **Impact**: `generate-targets.sh` would re-list already-converted files that use traditional include guards as unconverted candidates, potentially causing duplicate conversion attempts.
- **Suggested fix**: Extend the exclusion pattern on line 129 to also exclude `#ifndef`, `#define`, `#endif`, and `#include` directives:
  ```bash
  grep -cvE '^[[:space:]]*(#pragma|#ifndef|#define|#endif|#include|$)' 2>/dev/null || true
  ```
  Or alternatively, count only non-preprocessor substantive lines.

### WARNING — `#include` path extraction excludes path-prefixed includes

- **Location**: `generate-targets.sh:239`
- **Issue**: The regex `[^"<>/]+\.h` in `scan_includes()` uses a character class that excludes `/`, so any `#include "path/to/file.h"` directive is silently skipped. Only bare basenames like `#include "file.h"` are captured.
- **Impact**: Dependency edges between files connected by path-prefixed includes are missing from the dependency graph. This could cause a depended-upon file to be misidentified as a leaf node, allowing it to be converted before its dependents — potentially breaking the leaf-first ordering guarantee.
- **Suggested fix**: Extract just the basename from path-prefixed includes. Change the sed extraction to:
  ```bash
  sed -E 's/^[[:space:]]*#include[[:space:]]*["<]([^">]+)[">].*/\1/' | \
      sed 's|.*/||' | \
  ```
  This strips the directory prefix to yield just the filename for the index lookup.

### WARNING — PR conflict gate uses substring match

- **Location**: `generate-targets.sh:324`
- **Issue**: `grep -c "$target_name"` matches substrings, not whole words. A target named `nsString` would match files containing `nsStringBundle`, `nsStringFwd`, etc., causing false-positive conflict detection that skips valid candidates.
- **Impact**: Legitimate conversion candidates may be incorrectly skipped when an unrelated PR touches a file whose name contains the target name as a substring.
- **Suggested fix**: Use word-boundary or full-path matching:
  ```bash
  grep -cE "(^|/)${target_name}\.(h|cpp)($|[[:space:]])" || true
  ```

### WARNING — `firefox-sync.sh` `cmd_sync` rebase fallback contradicts documentation

- **Location**: `firefox-sync.sh:107-110` vs. `07-PHASE-6-MERGE.md:59-65` and `08-CONFLICT-AVOIDANCE.md`
- **Issue**: The documentation consistently states `--ff-only` merges with no fallback. However, `cmd_sync()` on line 107–110 falls back to `git rebase` when `--ff-only` fails. This is in contrast to `cmd_merge()` on line 191, which correctly dies on `--ff-only` failure.
- **Impact**: The `cmd_sync` rebase fallback could silently succeed in situations where the documentation says the operation should fail, potentially masking diverged history. The rebase may also fail partway through, leaving the submodule in an incomplete rebase state.
- **Suggested fix**: Either (a) update the documentation to explicitly note that `cmd_sync` (upstream tracking) permits rebase fallback while `cmd_merge` (oxidize branch merging) does not, or (b) remove the rebase fallback and fail hard, matching the documented behavior.

### WARNING — `firefox-sync.sh` `cmd_branch` silent fallback on missing branch

- **Location**: `firefox-sync.sh:158`
- **Issue**: `git checkout "$FIREFOX_BRANCH" 2>/dev/null || git checkout main 2>/dev/null || true` silently succeeds even if neither `FIREFOX_BRANCH` nor `main` exist. The subsequent `git checkout -b "oxidize/$name"` on line 159 would create the branch from whatever HEAD happens to be (potentially a detached HEAD or an unrelated branch).
- **Impact**: An oxidize branch could be created from an unexpected base commit if the expected branch does not exist, leading to incorrect merge bases.
- **Suggested fix**: Replace with an explicit check:
  ```bash
  if ! git checkout "$FIREFOX_BRANCH" 2>/dev/null; then
      if ! git checkout main 2>/dev/null; then
          die "Cannot find branch $FIREFOX_BRANCH or main to base oxidize/$name on."
      fi
  fi
  ```

### WARNING — Multi-line comment stripping is incomplete

- **Location**: `generate-targets.sh:128`
- **Issue**: `sed 's|/\*.*\*/||'` only removes `/* ... */` comments that start and end on the same line. Multi-line block comments are not stripped, causing their content to be counted as substantive lines.
- **Impact**: A converted header with a multi-line block comment above the `#include` redirect would have inflated `substantive_lines`, causing it to not be detected as converted. This is unlikely in practice (Phase 4 produces minimal files) but not impossible if someone adds a documentation comment.
- **Suggested fix**: For this specific use case (counting lines in a thin redirect file), the impact is low. If needed, pipe through `awk` for proper multi-line comment removal, or simply count only `#include` lines and preprocessor guard lines rather than trying to exclude everything else.

### INFO — Checklist template omits explicit Phase 0 contract-test-creation check

- **Location**: `09-CHECKLIST-TEMPLATE.md:9-13` (Scope section)
- **Issue**: Phase 0 exit criteria (from `01-PHASE-0-PREPARE.md:125-131`) include "contract tests written and passing" and "API surface documented." The checklist template's Scope section covers the conflict-gate prerequisites (one file-pair, no conflicting PRs, trunk is green) but does not have a checkbox for "contract tests written" or "API surface snapshot created." The Validation section (line 51) checks "contract tests pass" but not that they were written in Phase 0.
- **Impact**: A reviewer could miss the case where contract tests were never written if they rely solely on the checklist. The Phase 5 validation gate (`run_validation` in `loop.sh`) would catch this if contract test files don't exist (since the test compilation block at line 226 is conditional on file existence).
- **Suggested fix**: Add to the Scope section:
  ```markdown
  - [ ] Contract tests `test_{name}_contract.cpp` written and passing (Phase 0)
  - [ ] API surface snapshot documented
  ```

### INFO — `generate-targets.sh` leaf-node fallback uses all candidates

- **Location**: `generate-targets.sh:296-300`
- **Issue**: When no pure leaf nodes are found (every candidate is depended upon by another unconverted candidate — a circular or fully interconnected dependency subgraph), the fallback at line 299 copies all candidates to `LEAF_NODES`. This could produce a large target list that includes files with many unconverted dependents.
- **Impact**: Converting a non-leaf target means its dependents still reference the original header, which after switchover is a thin redirect. This should still work (the shim preserves the API), but it violates the documented leaf-first ordering strategy from `ROADMAP.md`.
- **Suggested fix**: When no pure leaves exist, rank candidates by the number of times they appear in column 1 of the dependency graph (fewest dependents first), rather than using all candidates equally. Add a comment documenting this fallback behavior.

### WARNING — Phase 6 failure still marks target as complete

- **Location**: `loop.sh:468-486`
- **Issue**: If Phase 6 (Merge) delegation fails (line 471 returns non-zero), the loop logs `"WARNING"` at line 474 but continues to `mark_target_complete` at line 482. Unlike Phase 5 (which uses `continue` to skip marking), Phase 6 failure does not prevent the target from being marked complete. There is no validation gate after Phase 6.
- **Impact**: A target whose merge failed (e.g., PR creation failed, `--ff-only` merge rejected) is marked as complete in `TARGETS.md`. On re-run, this target will be skipped rather than retried. Manual intervention is required to uncheck the target in `TARGETS.md` and retry.
- **Suggested fix**: After Phase 6 failure, either (a) skip `mark_target_complete` (via `continue`), or (b) add a post-merge verification check (e.g., verify the `oxidized/{name}` tag exists in the submodule before marking complete).

### INFO — `loop.sh` creates oxidize branch before Phase 0 delegation

- **Location**: `loop.sh:358`
- **Issue**: `firefox_create_branch` is called at line 358, before Phase 0 delegation starts at line 363. If Phase 0 fails (returns non-zero), the oxidize branch exists but may never be populated or merged. The branch is not cleaned up on Phase 0 failure.
- **Impact**: Orphaned `oxidize/*` branches accumulate in the Firefox submodule for targets that failed Phase 0. These are harmless but create clutter visible in `firefox-sync.sh status`.
- **Suggested fix**: Move branch creation to after Phase 0 succeeds, or add cleanup logic that deletes the branch if Phase 0 fails. Alternatively, document this as expected behavior — orphaned branches serve as evidence of attempted conversions.

### INFO — `run_validation` runs cumulative checks across all phases

- **Location**: `loop.sh:179-248`
- **Issue**: `run_validation` always runs all four checks (cargo test, C FFI header, C++ shim, contract tests) regardless of which phase just completed. After Phase 1, only the cargo test is relevant (the C FFI header and shim don't exist yet). The function handles this correctly via `if [ -f ... ]` guards, but it means validation after Phase 1 logs `"All validations PASSED"` even though only `cargo test` actually ran.
- **Impact**: No functional impact — the guards prevent false failures. However, the log messages may give an inflated impression of validation coverage at early phases.
- **Suggested fix**: Consider logging which checks were actually executed vs. skipped, or parametrize the validation function to accept a phase number and run only the relevant checks.

### INFO — `PIPESTATUS` in `delegate()` requires Bash, not POSIX sh

- **Location**: `loop.sh:170`
- **Issue**: `${PIPESTATUS[1]}` is a Bash-specific array. The shebang (`#!/usr/bin/env bash`) correctly specifies Bash, so this works. However, if the script were ever sourced from or invoked by a POSIX shell, it would fail silently.
- **Impact**: None under normal usage — the shebang ensures Bash. This is a portability note only.
- **Suggested fix**: No change needed; the shebang is correct. Add a comment noting the Bash requirement if desired.

---

## Cross-Reference Matrix

| Phase | Doc File | Prompt File | `loop.sh` delegate call | Validation gate |
|-------|----------|-------------|--------------------------|-----------------|
| 0 — Prepare | ✅ `01-PHASE-0-PREPARE.md` | ✅ `PREPARE.md` | ✅ `delegate "PREPARE.md"` (line 363) | ❌ None (no `run_validation` after Phase 0) |
| 1 — Rust | ✅ `02-PHASE-1-RUST.md` | ✅ `RUST.md` | ✅ `delegate "RUST.md"` (line 373) | ✅ `run_validation` (line 381) + FAIL.md retry |
| — Anti-Slop | ✅ `02b-ANTI-SLOP-AUDIT.md` | ✅ `ANTI_SLOP.md` | ✅ `delegate "ANTI_SLOP.md"` | ✅ `run_validation` + FAIL.md retry |
| 2 — C FFI | ✅ `03-PHASE-2-C-FFI.md` | ✅ `C_FFI.md` | ✅ `delegate "C_FFI.md"` (line 394) | ✅ `run_validation` (line 402) + FAIL.md retry |
| 3 — C++ Shim | ✅ `04-PHASE-3-CPP-SHIM.md` | ✅ `CPP_SHIM.md` | ✅ `delegate "CPP_SHIM.md"` (line 415) | ✅ `run_validation` (line 423) + FAIL.md retry |
| 4 — Switchover | ✅ `05-PHASE-4-SWITCHOVER.md` | ✅ `SWITCHOVER.md` | ✅ `delegate "SWITCHOVER.md"` (line 436) | ❌ None (no `run_validation` after Phase 4) |
| 5 — Validate | ✅ `06-PHASE-5-VALIDATE.md` | ✅ `VALIDATE.md` | ✅ `delegate "VALIDATE.md"` (line 446) | ✅ `run_validation` (line 454) + FAIL.md retry + `continue` on fail |
| 6 — Merge | ✅ `07-PHASE-6-MERGE.md` | ✅ `MERGE.md` | ✅ `delegate "MERGE.md"` (line 471) | ❌ None (no `run_validation` after Phase 6) |
| — Failure | N/A | ✅ `FAIL.md` | ✅ `delegate "FAIL.md"` (lines 384, 405, 426, 457) | N/A (invoked as a retry handler) |
| — Targets | N/A | ✅ `GENERATE_TARGETS.md` | N/A (separate script) | N/A |
| — Sync | N/A | ✅ `SYNC_FIREFOX.md` | N/A (separate script) | N/A |

**Prompt existence check**: All 11 prompt files exist. All 9 required by `loop.sh` (line 114) are verified at startup.

**Phase 0 and 4 lack validation gates**: This is by design — Phase 0 is read-only preparation and Phase 4 is a mechanical edit. Phase 5 provides the comprehensive validation gate before Phase 6 merge.

---

## Interrupt & Resume Safety

| Scenario | Behavior | Data Loss Risk |
|----------|----------|----------------|
| Ctrl+C during any phase | `trap cleanup INT TERM` (line 43) prints summary and exits 130 | ✅ None — target remains unchecked in TARGETS.md |
| Re-run after interrupt | `get_pending_targets()` reads unchecked items; resumes from first pending | ✅ Idempotent |
| Phase 5 `continue` skip | Target stays unchecked in TARGETS.md (line 464 skips `mark_target_complete`) | ✅ Target retried on re-run |
| Phase 6 failure | Target is still marked complete (line 482 runs unconditionally after Phase 6) | ⚠️ See WARNING finding: "Phase 6 failure still marks target as complete" |
| `TARGETS.md` corruption | `sed` uses temp file + `mv` (lines 266–268) — atomic replacement | ✅ No partial writes |

---

## Design Invariant Enforceability

| # | Invariant | Enforced By | Enforceable? |
|---|-----------|-------------|--------------|
| 1 | Callers never change | Phase 3 API fidelity checklist; Phase 5 contract tests | ✅ Yes — contract tests catch regressions |
| 2 | Public API is identical | Phase 3 shim construction; Phase 5 ABI symbol diff | ✅ Yes — `nm` check validates at ABI level |
| 3 | One PR, one file-pair | `TARGETS.md` one-at-a-time iteration; checklist Scope section | ✅ Yes — structural enforcement via loop |
| 4 | Phase 4 is only phase editing existing files | Phases 0–3 are additive by prompt instructions; Phase 4 docs are explicit | ⚠️ Partially — relies on Copilot compliance; no automated file-edit detection. Could be strengthened by comparing `git status` output before/after each phase to verify Phases 0–3 only create new files |
| 5 | Panics must not cross FFI boundary | Phase 1 prompt requires `catch_unwind`; Phase 5 validates | ⚠️ Partially — `run_validation` doesn't test for panic propagation directly |
| 6 | FFI boundary is pure C | Phase 2 `gcc -xc -fsyntax-only` validation | ✅ Yes — compiler enforces C-only syntax |

---

## Script Interaction Consistency

| Integration Point | `loop.sh` | `firefox-sync.sh` | Consistent? |
|---|---|---|---|
| Branch naming | `oxidize/{name}` (line 288) | `oxidize/$name` (line 159) | ✅ Yes |
| Tag naming | Delegates to `firefox-sync.sh merge` | `oxidized/$name` (line 201) | ✅ Yes |
| Merge policy | Delegates to `firefox-sync.sh merge` | `--ff-only` (line 191) | ✅ Yes |
| Submodule directory | `FIREFOX_DIR` env var (line 48) | `FIREFOX_DIR` env var (line 28) | ✅ Yes |
| Branch default | `main` implied | `FIREFOX_BRANCH` default `main` (line 29) | ✅ Yes |
| Sync after iteration | `firefox_sync_upstream()` (line 489) | `cmd_sync()` (line 76) | ✅ Yes |

---

## Summary of Findings by Severity

| Severity | Count | Summary |
|----------|-------|---------|
| CRITICAL | 0 | No critical issues found |
| WARNING | 7 | Pipeline error propagation (1), file detection heuristics (2), PR gate substring match (1), doc/code mismatch (1), silent branch fallback (1), merge failure marking (1) |
| INFO | 4 | Checklist gap (1), fallback strategy (1), branch cleanup (1), log clarity (1) |

**Conclusion**: Zero CRITICAL findings. The workflow is logically reliable for its intended use case. The WARNING-level findings are recoverable edge cases that would primarily affect automation reliability in unusual environments (traditional include guards, path-prefixed includes, substring PR matches). The core seven-phase loop, checkpoint/resume mechanism, and validation gates are sound.
