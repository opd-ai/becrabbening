#!/usr/bin/env bash
# loop.sh — Autonomous iterative Firefox carcinization orchestrator
#
# Drives Firefox toward complete Rust conversion by delegating
# the becrabbening phases to GitHub Copilot CLI, one file-pair
# at a time.
#
# Usage:
#   bash loop.sh [PROMPT_DIR]
#
# Arguments:
#   PROMPT_DIR  Path to the directory containing prompt .md files
#               (default: prompts/ relative to this script)
#
# Environment:
#   PROMPT_DIR      Override the prompt directory (takes precedence over $1)
#   MAX_TARGETS     Maximum number of targets to process (default: 50)
#   FIREFOX_DIR     Path to Firefox submodule (default: firefox)
#
# Prerequisites:
#   - TARGETS.md in the working directory listing file-pairs to convert
#   - Firefox source tree at FIREFOX_DIR (added via firefox-sync.sh init)
#   - GitHub Copilot CLI installed and authenticated
#   - cbindgen, cargo, gcc, g++ available on PATH
#
# The script is idempotent on re-run and safe to interrupt (Ctrl+C).

set -euo pipefail

# ─── Trap: graceful shutdown on Ctrl+C / SIGTERM ─────────────────────────────

# shellcheck disable=SC2317  # cleanup is invoked indirectly via trap
cleanup() {
    echo ""
    echo "=== LOOP INTERRUPTED ==="
    echo "Targets completed: $TARGETS_COMPLETED"
    echo "Current target: ${CURRENT_TARGET:-none}"
    echo "Current phase: ${CURRENT_PHASE:-none}"
    echo "Test failures encountered: $TEST_FAILURES"
    echo "Re-run this script to resume from current state."
    exit 130
}
trap cleanup INT TERM

# ─── Constants and defaults ──────────────────────────────────────────────────

MAX_TARGETS="${MAX_TARGETS:-50}"
FIREFOX_DIR="${FIREFOX_DIR:-firefox}"
LOG_FILE="loop.log"
TEST_OUTPUT="test-output.txt"

# Counters
TARGETS_COMPLETED=0
TEST_FAILURES=0
CURRENT_TARGET=""
CURRENT_PHASE=""

# ─── Logging helpers ─────────────────────────────────────────────────────────

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" >> "$LOG_FILE"
}

log_and_print() {
    local msg="$*"
    log "$msg"
    echo "$msg"
}

phase_summary() {
    local target="$1"
    local phase="$2"
    local status="$3"
    local line="[target: $target] phase $phase — $status"
    log "$line"
    echo "$line"
}

# ─── 1. Entry Gate ───────────────────────────────────────────────────────────

if [ ! -f "TARGETS.md" ]; then
    echo "ERROR: TARGETS.md not found in $(pwd)." >&2
    echo "Create a TARGETS.md listing file-pairs to convert." >&2
    echo "" >&2
    echo "Format (one target per line, unchecked = pending):" >&2
    echo "  - [ ] nsFoo" >&2
    echo "  - [ ] nsBar" >&2
    echo "  - [x] nsAlreadyDone  (checked = skip)" >&2
    exit 1
fi

# Resolve the prompt directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_DIR="${PROMPT_DIR:-${1:-$SCRIPT_DIR/prompts}}"

# Resolve to absolute path
PROMPT_DIR="$(cd "$PROMPT_DIR" && pwd)"

# ─── 1b. Firefox Submodule Gate ──────────────────────────────────────────────

if [ -d "$FIREFOX_DIR/.git" ] || [ -f "$FIREFOX_DIR/.git" ]; then
    FIREFOX_DIR="$(cd "$FIREFOX_DIR" && pwd)"
    log_and_print "Firefox submodule: $FIREFOX_DIR"
else
    echo "WARNING: Firefox submodule not found at $FIREFOX_DIR." >&2
    echo "Run 'bash firefox-sync.sh init' to set up the Firefox submodule." >&2
    echo "Continuing without submodule branch management." >&2
    FIREFOX_DIR=""
fi

# Validate prompt directory contains required files
for required in PREPARE.md RUST.md C_FFI.md CPP_SHIM.md SWITCHOVER.md VALIDATE.md MERGE.md FAIL.md; do
    if [ ! -f "$PROMPT_DIR/$required" ]; then
        echo "ERROR: $PROMPT_DIR does not contain $required." >&2
        echo "Set PROMPT_DIR or pass the prompt directory as an argument." >&2
        exit 1
    fi
done

log_and_print "=== BECRABBENING LOOP STARTING ==="
log_and_print "Working directory: $(pwd)"
log_and_print "Firefox source:    ${FIREFOX_DIR:-not configured}"
log_and_print "Prompt directory:  $PROMPT_DIR"
log_and_print "Max targets:       $MAX_TARGETS"

# ─── Helper: resolve working directory for phases ────────────────────────────
# When a Firefox submodule is present, phases and validation operate inside it.
# Otherwise they operate in the current directory.

phase_work_dir() {
    if [ -n "$FIREFOX_DIR" ]; then
        echo "$FIREFOX_DIR"
    else
        pwd
    fi
}

# ─── Helper: delegate a prompt to copilot ────────────────────────────────────

delegate() {
    local prompt_name="$1"
    local target_name="${2:-}"
    local prompt_file="$PROMPT_DIR/$prompt_name"

    if [ ! -f "$prompt_file" ]; then
        log_and_print "WARNING: Prompt file $prompt_file not found, skipping."
        return 1
    fi

    local prompt_content
    local work_dir
    work_dir="$(phase_work_dir)"
    if [ -n "$target_name" ]; then
        prompt_content="Current target file-pair name: ${target_name}
Working directory: ${work_dir}

$(cat "$prompt_file")"
    else
        prompt_content="Working directory: ${work_dir}

$(cat "$prompt_file")"
    fi

    log "Delegating: $prompt_name (target: ${target_name:-none})"
    # Temporarily disable -e so we can capture the copilot exit status from a pipeline.
    set +e
    yes | copilot -p "$prompt_content" --allow-all-tools --deny-tool sudo
    local rc=${PIPESTATUS[1]}
    # Re-enable -e to restore the script's error handling behavior.
    set -e
    log "Delegation complete: $prompt_name (exit code: $rc)"
    return "$rc"
}

# ─── Helper: run validation tests for a target ──────────────────────────────

run_validation() {
    local name="$1"
    local work_dir
    work_dir="$(phase_work_dir)"
    log "Running validation for target: $name (in $work_dir)"
    local rc=0
    local checks_run=0

    # Run cargo test on the Rust crate if it exists
    if [ -d "$work_dir/rust/$name" ]; then
        set +e
        (cd "$work_dir/rust/$name" && cargo test 2>&1) | tee "$TEST_OUTPUT"
        rc=${PIPESTATUS[0]}
        set -e
        if [ "$rc" -ne 0 ]; then
            log "cargo test FAILED for $name"
            return 1
        fi
        log "cargo test PASSED for $name"
        checks_run=$((checks_run + 1))
    fi

    # Verify C FFI header compiles as pure C
    if [ -f "$work_dir/${name}_ffi.h" ]; then
        set +e
        gcc -xc -fsyntax-only "$work_dir/${name}_ffi.h" 2>&1 | tee -a "$TEST_OUTPUT"
        rc=${PIPESTATUS[0]}
        set -e
        if [ "$rc" -ne 0 ]; then
            log "C FFI header validation FAILED for $name"
            return 1
        fi
        log "C FFI header validation PASSED for $name"
        checks_run=$((checks_run + 1))
    fi

    # Verify the shim compiles as C++
    if [ -f "$work_dir/${name}_shim.h" ]; then
        set +e
        g++ -xc++ -std=c++17 -fsyntax-only "$work_dir/${name}_shim.h" 2>&1 | tee -a "$TEST_OUTPUT"
        rc=${PIPESTATUS[0]}
        set -e
        if [ "$rc" -ne 0 ]; then
            log "C++ shim compilation FAILED for $name"
            return 1
        fi
        log "C++ shim compilation PASSED for $name"
        checks_run=$((checks_run + 1))
    fi

    # Run contract tests if they exist
    if [ -f "$work_dir/test_${name}_contract.cpp" ]; then
        set +e
        (cd "$work_dir" && g++ -std=c++17 "test_${name}_contract.cpp" "${name}.cpp" -o "test_${name}_contract" 2>&1) | tee -a "$TEST_OUTPUT"
        rc=${PIPESTATUS[0]}
        set -e
        if [ "$rc" -ne 0 ]; then
            log "Contract test compilation FAILED for $name"
            return 1
        fi
        set +e
        (cd "$work_dir" && "./test_${name}_contract" 2>&1) | tee -a "$TEST_OUTPUT"
        rc=${PIPESTATUS[0]}
        set -e
        if [ "$rc" -ne 0 ]; then
            log "Contract tests FAILED for $name"
            return 1
        fi
        log "Contract tests PASSED for $name"
        checks_run=$((checks_run + 1))
    fi

    # Fail if no artifacts were found to validate — prevents hollow targets
    # from silently passing when no phases produced any output.
    if [ "$checks_run" -eq 0 ]; then
        log "WARNING: No artifacts found to validate for $name"
        return 1
    fi

    log "All validations PASSED for $name ($checks_run check(s) executed)"
    return 0
}

# ─── Helper: extract pending targets from TARGETS.md ─────────────────────────

get_pending_targets() {
    # Extract unchecked items: lines matching "- [ ] name"
    grep -E '^[[:space:]]*-[[:space:]]*\[[[:space:]]*\][[:space:]]+' TARGETS.md \
        | sed 's/^[[:space:]]*-[[:space:]]*\[[[:space:]]*\][[:space:]]*//' \
        | sed 's/[[:space:]]*$//'
}

# ─── Helper: mark a target as complete in TARGETS.md ─────────────────────────

mark_target_complete() {
    local name="$1"
    # Replace "- [ ] name" with "- [x] name"
    # Use a temp file and -E for portability across GNU/BSD sed
    local tmp
    tmp=$(mktemp)
    sed -E "s/^([[:space:]]*-[[:space:]]*)\[[[:space:]]*\]([[:space:]]+${name}[[:space:]]*$)/\1[x]\2/" TARGETS.md > "$tmp"
    mv "$tmp" TARGETS.md
    log "Marked target $name as complete in TARGETS.md"
}

# ─── Helper: check if all targets are complete ───────────────────────────────

all_targets_complete() {
    local pending
    pending=$(get_pending_targets | wc -l)
    [ "$pending" -eq 0 ]
}

# ─── Helper: create oxidize branch in Firefox submodule ──────────────────────

firefox_create_branch() {
    local name="$1"
    if [ -z "$FIREFOX_DIR" ]; then
        return 0
    fi

    log "Creating oxidize/$name branch in Firefox submodule"
    if bash "$SCRIPT_DIR/firefox-sync.sh" branch "$name"; then
        log_and_print "Firefox branch oxidize/$name ready."
    else
        log_and_print "WARNING: Failed to create Firefox branch oxidize/$name."
    fi
}

# ─── Helper: merge oxidize branch in Firefox submodule ───────────────────────

firefox_merge_branch() {
    local name="$1"
    if [ -z "$FIREFOX_DIR" ]; then
        return 0
    fi

    log "Merging oxidize/$name in Firefox submodule"
    if bash "$SCRIPT_DIR/firefox-sync.sh" merge "$name"; then
        log_and_print "Firefox branch oxidize/$name merged and tagged."
    else
        log_and_print "WARNING: Failed to merge Firefox branch oxidize/$name."
    fi
}

# ─── Helper: sync Firefox submodule with upstream ────────────────────────────

firefox_sync_upstream() {
    if [ -z "$FIREFOX_DIR" ]; then
        return 0
    fi

    log "Syncing Firefox submodule with upstream"
    if bash "$SCRIPT_DIR/firefox-sync.sh" sync; then
        log_and_print "Firefox submodule synced with upstream."
    else
        log_and_print "WARNING: Failed to sync Firefox submodule with upstream."
    fi
}

# ─── 2. Main Loop ────────────────────────────────────────────────────────────

log_and_print "--- Entering main loop ---"

while [ "$TARGETS_COMPLETED" -lt "$MAX_TARGETS" ]; do

    # Check if there are any remaining targets
    if all_targets_complete; then
        log_and_print ""
        log_and_print "=== ALL TARGETS COMPLETE ==="
        log_and_print "Targets converted: $TARGETS_COMPLETED"
        log_and_print "Test failures encountered: $TEST_FAILURES"
        log_and_print "Firefox carcinization progressing. 🦀"
        rm -f "$TEST_OUTPUT"
        exit 0
    fi

    # Get the next pending target
    CURRENT_TARGET="$(get_pending_targets | head -1)"
    if [ -z "$CURRENT_TARGET" ]; then
        log_and_print "No pending targets found."
        break
    fi

    log_and_print ""
    log_and_print "=========================================="
    log_and_print "  TARGET: $CURRENT_TARGET"
    log_and_print "  ($((TARGETS_COMPLETED + 1)) / $MAX_TARGETS max)"
    log_and_print "=========================================="

    # ── Create oxidize branch in Firefox submodule ───────────────────────
    firefox_create_branch "$CURRENT_TARGET"

    # ── Phase 0: Prepare ─────────────────────────────────────────────────
    CURRENT_PHASE="0-prepare"
    log_and_print "--- Phase 0: Prepare ($CURRENT_TARGET) ---"
    if delegate "PREPARE.md" "$CURRENT_TARGET"; then
        phase_summary "$CURRENT_TARGET" "0-prepare" "DONE"
    else
        log_and_print "WARNING: Phase 0 delegation returned non-zero for $CURRENT_TARGET."
        phase_summary "$CURRENT_TARGET" "0-prepare" "WARNING"
    fi

    # ── Phase 1: Rust ────────────────────────────────────────────────────
    CURRENT_PHASE="1-rust"
    log_and_print "--- Phase 1: Rust ($CURRENT_TARGET) ---"
    if delegate "RUST.md" "$CURRENT_TARGET"; then
        phase_summary "$CURRENT_TARGET" "1-rust" "DONE"
    else
        log_and_print "WARNING: Phase 1 delegation returned non-zero for $CURRENT_TARGET."
        phase_summary "$CURRENT_TARGET" "1-rust" "WARNING"
    fi

    # Validate Rust crate after Phase 1
    if ! run_validation "$CURRENT_TARGET"; then
        TEST_FAILURES=$((TEST_FAILURES + 1))
        log_and_print "Validation failed after Phase 1 — delegating FAIL.md..."
        delegate "FAIL.md" "$CURRENT_TARGET" || true
        if ! run_validation "$CURRENT_TARGET"; then
            log_and_print "Validation still failing after FAIL.md for $CURRENT_TARGET Phase 1."
            phase_summary "$CURRENT_TARGET" "1-rust" "FAIL (persisted — skipping target)"
            continue
        fi
    fi

    # ── Phase 2: C FFI ───────────────────────────────────────────────────
    CURRENT_PHASE="2-c-ffi"
    log_and_print "--- Phase 2: C FFI ($CURRENT_TARGET) ---"
    if delegate "C_FFI.md" "$CURRENT_TARGET"; then
        phase_summary "$CURRENT_TARGET" "2-c-ffi" "DONE"
    else
        log_and_print "WARNING: Phase 2 delegation returned non-zero for $CURRENT_TARGET."
        phase_summary "$CURRENT_TARGET" "2-c-ffi" "WARNING"
    fi

    # Validate C FFI header
    if ! run_validation "$CURRENT_TARGET"; then
        TEST_FAILURES=$((TEST_FAILURES + 1))
        log_and_print "Validation failed after Phase 2 — delegating FAIL.md..."
        delegate "FAIL.md" "$CURRENT_TARGET" || true
        if ! run_validation "$CURRENT_TARGET"; then
            log_and_print "Validation still failing after FAIL.md for $CURRENT_TARGET Phase 2."
            phase_summary "$CURRENT_TARGET" "2-c-ffi" "FAIL (persisted — skipping target)"
            continue
        fi
    fi

    # ── Phase 3: C++ Shim ────────────────────────────────────────────────
    CURRENT_PHASE="3-cpp-shim"
    log_and_print "--- Phase 3: C++ Shim ($CURRENT_TARGET) ---"
    if delegate "CPP_SHIM.md" "$CURRENT_TARGET"; then
        phase_summary "$CURRENT_TARGET" "3-cpp-shim" "DONE"
    else
        log_and_print "WARNING: Phase 3 delegation returned non-zero for $CURRENT_TARGET."
        phase_summary "$CURRENT_TARGET" "3-cpp-shim" "WARNING"
    fi

    # Validate C++ shim
    if ! run_validation "$CURRENT_TARGET"; then
        TEST_FAILURES=$((TEST_FAILURES + 1))
        log_and_print "Validation failed after Phase 3 — delegating FAIL.md..."
        delegate "FAIL.md" "$CURRENT_TARGET" || true
        if ! run_validation "$CURRENT_TARGET"; then
            log_and_print "Validation still failing after FAIL.md for $CURRENT_TARGET Phase 3."
            phase_summary "$CURRENT_TARGET" "3-cpp-shim" "FAIL (persisted — skipping target)"
            continue
        fi
    fi

    # ── Phase 4: Switchover ──────────────────────────────────────────────
    CURRENT_PHASE="4-switchover"
    log_and_print "--- Phase 4: Switchover ($CURRENT_TARGET) ---"
    if delegate "SWITCHOVER.md" "$CURRENT_TARGET"; then
        phase_summary "$CURRENT_TARGET" "4-switchover" "DONE"
    else
        log_and_print "WARNING: Phase 4 delegation returned non-zero for $CURRENT_TARGET."
        phase_summary "$CURRENT_TARGET" "4-switchover" "WARNING"
    fi

    # ── Phase 5: Validate ────────────────────────────────────────────────
    CURRENT_PHASE="5-validate"
    log_and_print "--- Phase 5: Validate ($CURRENT_TARGET) ---"
    if delegate "VALIDATE.md" "$CURRENT_TARGET"; then
        phase_summary "$CURRENT_TARGET" "5-validate" "DONE"
    else
        log_and_print "WARNING: Phase 5 delegation returned non-zero for $CURRENT_TARGET."
        phase_summary "$CURRENT_TARGET" "5-validate" "WARNING"
    fi

    # Run validation after Phase 5
    if ! run_validation "$CURRENT_TARGET"; then
        TEST_FAILURES=$((TEST_FAILURES + 1))
        log_and_print "Validation failed after Phase 5 — delegating FAIL.md..."
        delegate "FAIL.md" "$CURRENT_TARGET" || true

        # Re-validate after FAIL.md
        if ! run_validation "$CURRENT_TARGET"; then
            log_and_print "CRITICAL: Validation still failing after FAIL.md for $CURRENT_TARGET."
            log_and_print "Manual intervention required. Skipping target."
            phase_summary "$CURRENT_TARGET" "5-validate" "FAIL (manual intervention needed)"
            continue
        fi
    fi

    # ── Phase 6: Merge ───────────────────────────────────────────────────
    CURRENT_PHASE="6-merge"
    log_and_print "--- Phase 6: Merge ($CURRENT_TARGET) ---"
    if delegate "MERGE.md" "$CURRENT_TARGET"; then
        phase_summary "$CURRENT_TARGET" "6-merge" "DONE"
    else
        log_and_print "WARNING: Phase 6 delegation returned non-zero for $CURRENT_TARGET."
        phase_summary "$CURRENT_TARGET" "6-merge" "FAIL (merge incomplete — skipping target)"
        continue
    fi

    # ── Merge oxidize branch in Firefox submodule ────────────────────────
    firefox_merge_branch "$CURRENT_TARGET"

    # ── Mark target complete ─────────────────────────────────────────────
    mark_target_complete "$CURRENT_TARGET"
    TARGETS_COMPLETED=$((TARGETS_COMPLETED + 1))
    log_and_print ""
    log_and_print "=== TARGET COMPLETE: $CURRENT_TARGET ==="
    log_and_print "Targets converted so far: $TARGETS_COMPLETED"

    # ── Sync Firefox submodule with upstream between iterations ──────────
    firefox_sync_upstream
done

# ─── 3. Completion ───────────────────────────────────────────────────────────

if all_targets_complete; then
    log_and_print ""
    log_and_print "=== BECRABBENING LOOP COMPLETE ==="
    log_and_print "All targets converted successfully."
else
    log_and_print ""
    log_and_print "=== BECRABBENING LOOP COMPLETE (max targets reached) ==="
    log_and_print "Some targets may remain unconverted."
fi

log_and_print "Targets converted: $TARGETS_COMPLETED"
log_and_print "Test failures encountered: $TEST_FAILURES"

rm -f "$TEST_OUTPUT"

if [ "$TEST_FAILURES" -eq 0 ]; then
    exit 0
else
    exit 1
fi
