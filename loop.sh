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
#
# Prerequisites:
#   - TARGETS.md in the working directory listing file-pairs to convert
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
log_and_print "Prompt directory:  $PROMPT_DIR"
log_and_print "Max targets:       $MAX_TARGETS"

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
    if [ -n "$target_name" ]; then
        prompt_content="Current target file-pair name: ${target_name}

$(cat "$prompt_file")"
    else
        prompt_content="$(cat "$prompt_file")"
    fi

    log "Delegating: $prompt_name (target: ${target_name:-none})"
    yes | copilot -p "$prompt_content" --allow-all-tools --deny-tool sudo
    local rc=$?
    log "Delegation complete: $prompt_name (exit code: $rc)"
    return $rc
}

# ─── Helper: run validation tests for a target ──────────────────────────────

run_validation() {
    local name="$1"
    log "Running validation for target: $name"
    local rc=0

    # Run cargo test on the Rust crate if it exists
    if [ -d "rust/$name" ]; then
        set +e
        (cd "rust/$name" && cargo test 2>&1) | tee "$TEST_OUTPUT"
        rc=${PIPESTATUS[0]}
        set -e
        if [ "$rc" -ne 0 ]; then
            log "cargo test FAILED for $name"
            return 1
        fi
        log "cargo test PASSED for $name"
    fi

    # Verify C FFI header compiles as pure C
    if [ -f "${name}_ffi.h" ]; then
        set +e
        gcc -xc -fsyntax-only "${name}_ffi.h" 2>&1 | tee -a "$TEST_OUTPUT"
        rc=${PIPESTATUS[0]}
        set -e
        if [ "$rc" -ne 0 ]; then
            log "C FFI header validation FAILED for $name"
            return 1
        fi
        log "C FFI header validation PASSED for $name"
    fi

    # Verify the shim compiles as C++
    if [ -f "${name}_shim.h" ]; then
        set +e
        g++ -xc++ -std=c++17 -fsyntax-only "${name}_shim.h" 2>&1 | tee -a "$TEST_OUTPUT"
        rc=${PIPESTATUS[0]}
        set -e
        if [ "$rc" -ne 0 ]; then
            log "C++ shim compilation FAILED for $name"
            return 1
        fi
        log "C++ shim compilation PASSED for $name"
    fi

    # Run contract tests if they exist
    if [ -f "test_${name}_contract.cpp" ]; then
        set +e
        g++ -std=c++17 "test_${name}_contract.cpp" "${name}.cpp" -o "test_${name}_contract" 2>&1 | tee -a "$TEST_OUTPUT"
        rc=${PIPESTATUS[0]}
        set -e
        if [ "$rc" -ne 0 ]; then
            log "Contract test compilation FAILED for $name"
            return 1
        fi
        set +e
        "./test_${name}_contract" 2>&1 | tee -a "$TEST_OUTPUT"
        rc=${PIPESTATUS[0]}
        set -e
        if [ "$rc" -ne 0 ]; then
            log "Contract tests FAILED for $name"
            return 1
        fi
        log "Contract tests PASSED for $name"
    fi

    log "All validations PASSED for $name"
    return 0
}

# ─── Helper: extract pending targets from TARGETS.md ─────────────────────────

get_pending_targets() {
    # Extract unchecked items: lines matching "- [ ] name"
    grep -E '^\s*-\s*\[\s*\]\s+' TARGETS.md | sed 's/^\s*-\s*\[\s*\]\s*//' | sed 's/\s*$//'
}

# ─── Helper: mark a target as complete in TARGETS.md ─────────────────────────

mark_target_complete() {
    local name="$1"
    # Replace "- [ ] name" with "- [x] name"
    sed -i "s/^\(\s*-\s*\)\[\s*\]\(\s\+${name}\s*$\)/\1[x]\2/" TARGETS.md
    log "Marked target $name as complete in TARGETS.md"
}

# ─── Helper: check if all targets are complete ───────────────────────────────

all_targets_complete() {
    local pending
    pending=$(get_pending_targets | wc -l)
    [ "$pending" -eq 0 ]
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
            phase_summary "$CURRENT_TARGET" "1-rust" "FAIL (persisted)"
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
            phase_summary "$CURRENT_TARGET" "2-c-ffi" "FAIL (persisted)"
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
            phase_summary "$CURRENT_TARGET" "3-cpp-shim" "FAIL (persisted)"
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
        phase_summary "$CURRENT_TARGET" "6-merge" "WARNING"
    fi

    # ── Mark target complete ─────────────────────────────────────────────
    mark_target_complete "$CURRENT_TARGET"
    TARGETS_COMPLETED=$((TARGETS_COMPLETED + 1))
    log_and_print ""
    log_and_print "=== TARGET COMPLETE: $CURRENT_TARGET ==="
    log_and_print "Targets converted so far: $TARGETS_COMPLETED"
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
