#!/usr/bin/env bash
# generate-targets.sh — Scan a Firefox source tree and generate the next TARGETS.md
#
# Analyzes #include dependencies to identify leaf-node C++ file-pairs
# eligible for oxidation, following the becrabbening's leaf-first
# topological ordering strategy.
#
# Usage:
#   bash generate-targets.sh [SOURCE_DIR]
#
# Arguments:
#   SOURCE_DIR   Root of the Firefox source tree to scan
#               (default: current directory)
#
# Environment:
#   SOURCE_DIR      Override the source directory (takes precedence over $1)
#   MAX_TARGETS     Maximum number of targets to include (default: 20)
#   OUTPUT_FILE     Output file path (default: TARGETS.md)
#   SKIP_PR_CHECK   Set to 1 to skip the open-PR conflict gate check
#
# The script:
#   1. Finds all C++ file-pairs (.cpp+.h or .h-only)
#   2. Excludes already-converted files (contain only #include redirect)
#   3. Builds the #include dependency graph
#   4. Identifies leaf nodes (no unconverted dependents)
#   5. Ranks by smallest API surface first
#   6. Optionally checks for open PRs on candidate files
#   7. Writes TARGETS.md in the format loop.sh expects

set -euo pipefail

# ─── Constants and defaults ──────────────────────────────────────────────────

SOURCE_DIR="${SOURCE_DIR:-${1:-.}}"
MAX_TARGETS="${MAX_TARGETS:-20}"
OUTPUT_FILE="${OUTPUT_FILE:-TARGETS.md}"
SKIP_PR_CHECK="${SKIP_PR_CHECK:-0}"

# Temporary working files
WORK_DIR=""

# ─── Cleanup ─────────────────────────────────────────────────────────────────

cleanup() {
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

# ─── Validate inputs ─────────────────────────────────────────────────────────

SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "ERROR: Source directory $SOURCE_DIR does not exist." >&2
    exit 1
fi

echo "=== GENERATE TARGETS ==="
echo "Source directory: $SOURCE_DIR"
echo "Max targets:     $MAX_TARGETS"
echo "Output file:     $OUTPUT_FILE"
echo ""

# ─── Create temp working directory ───────────────────────────────────────────

WORK_DIR="$(mktemp -d)"

ALL_HEADERS="$WORK_DIR/all-headers.txt"
ALL_CPPS="$WORK_DIR/all-cpps.txt"
CONVERTED="$WORK_DIR/converted.txt"
CANDIDATES="$WORK_DIR/candidates.txt"
DEPGRAPH="$WORK_DIR/depgraph.txt"
LEAF_NODES="$WORK_DIR/leaf-nodes.txt"
RANKED="$WORK_DIR/ranked.txt"
EXISTING_DONE="$WORK_DIR/existing-done.txt"

# ─── Step 1: Find all C++ headers and source files ──────────────────────────

echo "--- Step 1: Scanning for C++ files ---"

find "$SOURCE_DIR" -type f -name '*.h' \
    ! -path '*/.git/*' \
    ! -path '*/node_modules/*' \
    ! -path '*/third_party/*' \
    ! -path '*/test/*' \
    ! -path '*/tests/*' \
    ! -path '*_ffi.h' \
    ! -path '*_shim.h' \
    | sort > "$ALL_HEADERS"

find "$SOURCE_DIR" -type f -name '*.cpp' \
    ! -path '*/.git/*' \
    ! -path '*/node_modules/*' \
    ! -path '*/third_party/*' \
    ! -path '*/test/*' \
    ! -path '*/tests/*' \
    | sort > "$ALL_CPPS"

header_count=$(wc -l < "$ALL_HEADERS")
cpp_count=$(wc -l < "$ALL_CPPS")
echo "  Found $header_count headers and $cpp_count source files."

# ─── Step 2: Identify already-converted files ───────────────────────────────

echo "--- Step 2: Identifying already-converted files ---"

# A file is "converted" if its contents are just a #include redirect to a shim
# (i.e., the Phase 4 switchover has been applied)
: > "$CONVERTED"

while IFS= read -r header; do
    # Check if the header is a thin redirect (contains only #include of a shim)
    if grep -qE '^\s*#include\s+"[^"]*_shim\.h"' "$header" 2>/dev/null; then
        # Count lines that are actual #include directives to a shim
        shim_includes=$(grep -cE '^\s*#include\s+"[^"]*_shim\.h"' "$header" 2>/dev/null || true)
        # Count all non-empty, non-comment, non-pragma lines
        substantive_lines=$(sed 's|//.*||; s|/\*.*\*/||' "$header" \
            | grep -cvE '^\s*(#pragma|$)' 2>/dev/null || true)
        if [ "$substantive_lines" -le "$shim_includes" ]; then
            echo "$header" >> "$CONVERTED"
        fi
    fi
done < "$ALL_HEADERS"

converted_count=$(wc -l < "$CONVERTED")
echo "  Found $converted_count already-converted files."

# Also check for existing TARGETS.md completed items
: > "$EXISTING_DONE"
if [ -f "$OUTPUT_FILE" ]; then
    grep -E '^\s*-\s*\[x\]\s+' "$OUTPUT_FILE" \
        | sed 's/^\s*-\s*\[x\]\s*//' \
        | sed 's/\s*$//' > "$EXISTING_DONE" 2>/dev/null || true
    done_count=$(wc -l < "$EXISTING_DONE")
    echo "  Found $done_count previously completed targets in $OUTPUT_FILE."
fi

# ─── Step 3: Build candidate list of file-pairs ─────────────────────────────

echo "--- Step 3: Building candidate file-pair list ---"

: > "$CANDIDATES"

while IFS= read -r header; do
    # Skip already-converted
    if grep -qF "$header" "$CONVERTED" 2>/dev/null; then
        continue
    fi

    # Extract base name (without directory and extension)
    basename_h="$(basename "$header" .h)"
    dir_h="$(dirname "$header")"

    # Check if there's a corresponding .cpp
    has_cpp=0
    if [ -f "$dir_h/$basename_h.cpp" ]; then
        has_cpp=1
    fi

    # Derive the target name from the basename
    # (strip ns/moz/etc. prefix conventions aren't changed — use as-is)
    target_name="$basename_h"

    # Skip if already completed
    if grep -qxF "$target_name" "$EXISTING_DONE" 2>/dev/null; then
        continue
    fi

    # Count public API symbols as a proxy for API surface size
    # Match class/struct/enum declarations and function-like declarations
    api_size=$(grep -cE '^\s*(class\s|struct\s|enum\s|typedef\s|using\s|inline\s|constexpr\s|#define\s)' "$header" 2>/dev/null || echo "0")

    # Record: api_size target_name header_path has_cpp
    echo "$api_size $target_name $header $has_cpp" >> "$CANDIDATES"

done < "$ALL_HEADERS"

candidate_count=$(wc -l < "$CANDIDATES")
echo "  Found $candidate_count unconverted candidate file-pairs."

if [ "$candidate_count" -eq 0 ]; then
    echo ""
    echo "No unconverted C++ file-pairs found. Firefox is fully carcinized! 🦀"
    # Write an empty TARGETS.md
    {
        echo "# Conversion Targets"
        echo ""
        echo "All targets have been converted. Firefox carcinization complete. 🦀"
    } > "$OUTPUT_FILE"
    exit 0
fi

# ─── Step 4: Build #include dependency graph ─────────────────────────────────

echo "--- Step 4: Building #include dependency graph ---"

# For each candidate header, find which other candidate headers include it.
# Format: included_header including_header
# (i.e., included_header is a dependency OF including_header)
: > "$DEPGRAPH"

while IFS= read -r line; do
    # Parse candidate fields
    target_name="$(echo "$line" | awk '{print $2}')"
    header_path="$(echo "$line" | awk '{print $3}')"
    basename_h="$(basename "$header_path")"

    # Build the include pattern for exact basename matching
    include_pattern="#include\s*[\"<](.*\/)?${basename_h}[\">]"

    # Search for other candidate files that #include this header
    while IFS= read -r other_line; do
        other_target="$(echo "$other_line" | awk '{print $2}')"
        other_header="$(echo "$other_line" | awk '{print $3}')"
        other_has_cpp="$(echo "$other_line" | awk '{print $4}')"

        # Skip self
        if [ "$other_target" = "$target_name" ]; then
            continue
        fi

        # Check if the other header includes this header (exact basename match)
        if grep -qE "$include_pattern" "$other_header" 2>/dev/null; then
            # other_target depends on target_name
            echo "$target_name $other_target" >> "$DEPGRAPH"
        fi

        # Also check the .cpp file if it exists
        if [ "$other_has_cpp" = "1" ]; then
            other_dir="$(dirname "$other_header")"
            other_cpp="$other_dir/$(basename "$other_header" .h).cpp"
            if [ -f "$other_cpp" ] && grep -qE "$include_pattern" "$other_cpp" 2>/dev/null; then
                echo "$target_name $other_target" >> "$DEPGRAPH"
            fi
        fi
    done < "$CANDIDATES"

done < "$CANDIDATES"

# Deduplicate
sort -u "$DEPGRAPH" -o "$DEPGRAPH"
dep_count=$(wc -l < "$DEPGRAPH")
echo "  Found $dep_count dependency edges."

# ─── Step 5: Identify leaf nodes ─────────────────────────────────────────────

echo "--- Step 5: Identifying leaf nodes ---"

# A leaf node is a candidate that has NO unconverted dependents
# (i.e., no other unconverted candidate #includes it)
# In the dependency graph, leaf nodes are those that never appear in column 1
# (they are never depended upon by another unconverted file)

: > "$LEAF_NODES"

while IFS= read -r line; do
    target_name="$(echo "$line" | awk '{print $2}')"

    # Check if this target appears as a dependency (column 1) in the graph
    if ! grep -q "^${target_name} " "$DEPGRAPH" 2>/dev/null; then
        echo "$line" >> "$LEAF_NODES"
    fi
done < "$CANDIDATES"

leaf_count=$(wc -l < "$LEAF_NODES")
echo "  Found $leaf_count leaf-node candidates."

# If no pure leaf nodes, fall back to candidates with fewest dependents
if [ "$leaf_count" -eq 0 ]; then
    echo "  No pure leaf nodes found. Using all candidates ranked by dependency count."
    cp "$CANDIDATES" "$LEAF_NODES"
fi

# ─── Step 6: Rank candidates ─────────────────────────────────────────────────

echo "--- Step 6: Ranking candidates ---"

# Sort by API surface size (ascending — smaller API = easier to convert)
sort -n "$LEAF_NODES" > "$RANKED"

# ─── Step 7: Conflict gate check (optional) ──────────────────────────────────

if [ "$SKIP_PR_CHECK" != "1" ] && command -v gh &>/dev/null; then
    echo "--- Step 7: Checking for open PRs (conflict gate) ---"

    FILTERED="$WORK_DIR/filtered.txt"
    : > "$FILTERED"

    while IFS= read -r line; do
        target_name="$(echo "$line" | awk '{print $2}')"

        # Check if any open PR touches this file
        set +e
        pr_hits=$(gh pr list --state open --json files \
            --jq ".[].files[].path" 2>/dev/null \
            | grep -c "$target_name" || true)
        set -e

        if [ "$pr_hits" -gt 0 ]; then
            echo "  SKIP: $target_name — open PR touches this file"
        else
            echo "$line" >> "$FILTERED"
        fi
    done < "$RANKED"

    cp "$FILTERED" "$RANKED"
    filtered_count=$(wc -l < "$RANKED")
    echo "  $filtered_count candidates pass conflict gate."
else
    if [ "$SKIP_PR_CHECK" = "1" ]; then
        echo "--- Step 7: Skipping PR check (SKIP_PR_CHECK=1) ---"
    else
        echo "--- Step 7: Skipping PR check (gh CLI not available) ---"
    fi
fi

# ─── Step 8: Write TARGETS.md ────────────────────────────────────────────────

echo "--- Step 8: Writing $OUTPUT_FILE ---"

target_count=0

{
    echo "# Conversion Targets"
    echo ""
    echo "Generated on $(date '+%Y-%m-%d %H:%M:%S') by \`generate-targets.sh\`."
    echo ""
    echo "Source directory: \`$SOURCE_DIR\`"
    echo ""
    echo "Selection criteria: leaf-first topological order, smallest API surface first."
    echo "See [ROADMAP.md](./ROADMAP.md) for the target selection strategy."
    echo ""

    # Preserve already-completed targets from existing file
    if [ -s "$EXISTING_DONE" ]; then
        echo "## Completed"
        echo ""
        while IFS= read -r done_target; do
            echo "- [x] $done_target"
        done < "$EXISTING_DONE"
        echo ""
    fi

    echo "## Pending"
    echo ""

    while IFS= read -r line; do
        if [ "$target_count" -ge "$MAX_TARGETS" ]; then
            break
        fi

        target_name="$(echo "$line" | awk '{print $2}')"

        echo "- [ ] $target_name"
        target_count=$((target_count + 1))
    done < "$RANKED"

} > "$OUTPUT_FILE"

echo ""
echo "=== TARGETS GENERATED ==="
echo "Wrote $target_count pending targets to $OUTPUT_FILE"
echo ""
echo "Next step: review $OUTPUT_FILE and run loop.sh to begin conversion."
