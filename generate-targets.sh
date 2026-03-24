#!/usr/bin/env bash
# generate-targets.sh — Scan a Firefox source tree and generate the next TARGETS.md
#
# Analyzes #include dependencies to identify leaf-node C/C++ file-pairs
# eligible for oxidation, following the becrabbening's leaf-first
# topological ordering strategy.
#
# Usage:
#   bash generate-targets.sh [SOURCE_DIR]
#
# Arguments:
#   SOURCE_DIR   Root of the Firefox source tree to scan
#               (default: firefox/ submodule, or current directory)
#
# Environment:
#   SOURCE_DIR      Override the source directory (takes precedence over $1)
#   MAX_TARGETS     Maximum number of targets to include (default: 20)
#   OUTPUT_FILE     Output file path (default: TARGETS.md)
#   SKIP_PR_CHECK   Set to 1 to skip the open-PR conflict gate check
#
# The script:
#   1. Finds all C/C++ file-pairs (.c+.h, .cpp+.h, or .h-only)
#   2. Excludes already-converted files (contain only #include redirect)
#   3. Builds the #include dependency graph
#   4. Identifies leaf nodes (no unconverted dependents)
#   5. Ranks by smallest API surface first
#   6. Optionally checks for open PRs on candidate files
#   7. Writes TARGETS.md in the format loop.sh expects

set -euo pipefail

# ─── Constants and defaults ──────────────────────────────────────────────────

# Default SOURCE_DIR: use $1 if given, otherwise prefer the firefox/ submodule
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_DEFAULT_DIR="."
if [ -d "$SCRIPT_DIR/firefox" ]; then
    _DEFAULT_DIR="$SCRIPT_DIR/firefox"
fi
SOURCE_DIR="${SOURCE_DIR:-${1:-$_DEFAULT_DIR}}"
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

if [ ! -d "$SOURCE_DIR" ]; then
    echo "ERROR: Source directory $SOURCE_DIR does not exist." >&2
    exit 1
fi

if ! SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"; then
    echo "ERROR: Failed to resolve absolute path for source directory: $SOURCE_DIR" >&2
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
ALL_CS="$WORK_DIR/all-cs.txt"
CONVERTED="$WORK_DIR/converted.txt"
CANDIDATES="$WORK_DIR/candidates.txt"
DEPGRAPH="$WORK_DIR/depgraph.txt"
LEAF_NODES="$WORK_DIR/leaf-nodes.txt"
RANKED="$WORK_DIR/ranked.txt"
EXISTING_DONE="$WORK_DIR/existing-done.txt"

# ─── Step 1: Find all C/C++ headers and source files ──────────────────────────

echo "--- Step 1: Scanning for C/C++ files ---"

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

find "$SOURCE_DIR" -type f -name '*.c' \
    ! -path '*/.git/*' \
    ! -path '*/node_modules/*' \
    ! -path '*/third_party/*' \
    ! -path '*/test/*' \
    ! -path '*/tests/*' \
    | sort > "$ALL_CS"

header_count=$(wc -l < "$ALL_HEADERS")
cpp_count=$(wc -l < "$ALL_CPPS")
c_count=$(wc -l < "$ALL_CS")
echo "  Found $header_count headers, $cpp_count C++ source files, and $c_count C source files."

# ─── Step 2: Identify already-converted files ───────────────────────────────

echo "--- Step 2: Identifying already-converted files ---"

# A file is "converted" if its contents are just a #include redirect to a shim
# (i.e., the Phase 4 switchover has been applied)
: > "$CONVERTED"

while IFS= read -r header; do
    # Check if the header is a thin redirect (contains only #include of a shim)
    if grep -qE '^[[:space:]]*#include[[:space:]]+"[^"]*_shim\.h"' "$header" 2>/dev/null; then
        # Count lines that are actual #include directives to a shim
        shim_includes=$(grep -cE '^[[:space:]]*#include[[:space:]]+"[^"]*_shim\.h"' "$header" 2>/dev/null || true)
        # Count total #include directives (shim and non-shim alike)
        total_includes=$(grep -cE '^[[:space:]]*#include[[:space:]]*["<]' "$header" 2>/dev/null || true)
        # Count non-empty, non-comment, non-preprocessor lines.
        # Excludes: #pragma, #ifndef, #define, #endif, #include, and empty lines
        # so that include guards and the shim redirect itself don't count.
        # The separate total_includes == shim_includes check below ensures
        # that non-shim #include lines still disqualify the file.
        substantive_lines=$(sed 's|//.*||; s|/\*.*\*/||' "$header" \
            | grep -cvE '^[[:space:]]*(#pragma|#ifndef|#define|#endif|#include|$)' 2>/dev/null || true)
        # A file is "converted" only if every #include is a shim include
        # and there is no other substantive code.
        if [ "$substantive_lines" -eq 0 ] && [ "$total_includes" -eq "$shim_includes" ]; then
            echo "$header" >> "$CONVERTED"
        fi
    fi
done < "$ALL_HEADERS"

converted_count=$(wc -l < "$CONVERTED")
echo "  Found $converted_count already-converted files."

# Also check for existing TARGETS.md completed items
: > "$EXISTING_DONE"
if [ -f "$OUTPUT_FILE" ]; then
    grep -E '^[[:space:]]*-[[:space:]]*\[x\][[:space:]]+' "$OUTPUT_FILE" \
        | sed 's/^[[:space:]]*-[[:space:]]*\[x\][[:space:]]*//' \
        | sed 's/[[:space:]]*$//' > "$EXISTING_DONE" 2>/dev/null || true
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

    # Check if there's a corresponding .cpp or .c source file.
    # Prefer .cpp if both exist (C++ takes precedence).
    src_ext="none"
    if [ -f "$dir_h/$basename_h.cpp" ]; then
        src_ext="cpp"
    elif [ -f "$dir_h/$basename_h.c" ]; then
        src_ext="c"
    fi

    # Derive the target name from the basename
    # (strip ns/moz/etc. prefix conventions aren't changed — use as-is)
    target_name="$basename_h"

    # Skip if already completed (match first word to handle both old
    # format "nsFoo" and new format "nsFoo (path/nsFoo.h + path/nsFoo.cpp)")
    if awk -v t="$target_name" '$1 == t {found=1; exit} END {exit !found}' "$EXISTING_DONE" 2>/dev/null; then
        continue
    fi

    # Count public API symbols as a proxy for API surface size
    # Match class/struct/enum declarations and function-like declarations
    api_size=$(grep -cE '^[[:space:]]*(class[[:space:]]|struct[[:space:]]|enum[[:space:]]|typedef[[:space:]]|using[[:space:]]|inline[[:space:]]|constexpr[[:space:]]|#define[[:space:]])' "$header" 2>/dev/null || true)

    # Record: api_size target_name header_path src_ext
    echo "$api_size $target_name $header $src_ext" >> "$CANDIDATES"

done < "$ALL_HEADERS"

candidate_count=$(wc -l < "$CANDIDATES")
echo "  Found $candidate_count unconverted candidate file-pairs."

if [ "$candidate_count" -eq 0 ]; then
    echo ""
    echo "No unconverted C/C++ file-pairs found. Firefox is fully carcinized! 🦀"
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

# Build header basename -> target index to avoid O(N^2) greps
HEADER_INDEX="$WORK_DIR/header-index.txt"
INCLUDE_INDEX="$WORK_DIR/include-index.txt"
: > "$HEADER_INDEX"
: > "$INCLUDE_INDEX"

# First pass: record, for each candidate header basename, which target it belongs to.
while IFS= read -r line; do
    target_name="$(echo "$line" | awk '{print $2}')"
    header_path="$(echo "$line" | awk '{print $3}')"
    basename_h="$(basename "$header_path")"
    echo "$basename_h $target_name" >> "$HEADER_INDEX"
done < "$CANDIDATES"

# Second pass: for each candidate's header/cpp, extract included header basenames once.
while IFS= read -r line; do
    includer_target="$(echo "$line" | awk '{print $2}')"
    header_path="$(echo "$line" | awk '{print $3}')"
    src_ext="$(echo "$line" | awk '{print $4}')"

    # Helper: scan a single source file for #include basenames
    scan_includes() {
        local src_file="$1"
        if [ ! -f "$src_file" ]; then
            return
        fi
        # Match both bare and path-prefixed includes, then strip to basename
        grep -hE '^[[:space:]]*#include[[:space:]]*["<]([^">]+\.h)[">]' "$src_file" 2>/dev/null | \
            sed -E 's/^[[:space:]]*#include[[:space:]]*["<]([^">]+\.h)[">].*/\1/' | \
            sed 's|.*/||' | \
            while IFS= read -r inc_base; do
                [ -n "$inc_base" ] && echo "$includer_target $inc_base" >> "$INCLUDE_INDEX"
            done || true
    }

    # Scan the header file
    scan_includes "$header_path"

    # Scan the source file (.cpp or .c) if it exists
    if [ "$src_ext" != "none" ]; then
        header_dir="$(dirname "$header_path")"
        src_path="$header_dir/$(basename "$header_path" .h).$src_ext"
        scan_includes "$src_path"
    fi
done < "$CANDIDATES"

# Build dependency edges: included_target -> includer_target, joined via header basename.
awk 'NR==FNR { header_to_target[$1]=$2; next }
     {
         includer = $1;
         incbase  = $2;
         included = header_to_target[incbase];
         if (included != "" && included != includer) {
             print included, includer;
         }
     }' "$HEADER_INDEX" "$INCLUDE_INDEX" >> "$DEPGRAPH"

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
    PR_FILES="$WORK_DIR/pr-files.txt"
    : > "$FILTERED"

    # Fetch the list of files touched by open PRs once, not per-candidate.
    if gh pr list --state open --json files \
            --jq ".[].files[].path" > "$PR_FILES" 2>/dev/null; then

        while IFS= read -r line; do
            target_name="$(echo "$line" | awk '{print $2}')"

            # Check if any open PR touches this file (exact basename match)
            pr_hits=$(grep -cE "(^|/)${target_name}\.(h|c|cpp)$" "$PR_FILES" || true)

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
        echo "  WARNING: gh pr list failed; skipping conflict gate check."
    fi
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
        header_path="$(echo "$line" | awk '{print $3}')"
        src_ext="$(echo "$line" | awk '{print $4}')"

        # Skip malformed entries with no target name
        if [ -z "$target_name" ]; then
            continue
        fi

        # Compute file paths relative to the source directory root
        header_rel="${header_path#$SOURCE_DIR/}"
        if [ "$src_ext" != "none" ]; then
            src_rel="${header_rel%.h}.${src_ext}"
            echo "- [ ] $target_name ($header_rel + $src_rel)"
        else
            echo "- [ ] $target_name ($header_rel)"
        fi
        target_count=$((target_count + 1))
    done < "$RANKED"

} > "$OUTPUT_FILE"

echo ""
echo "=== TARGETS GENERATED ==="
echo "Wrote $target_count pending targets to $OUTPUT_FILE"
echo ""
echo "Next step: review $OUTPUT_FILE and run loop.sh to begin conversion."
