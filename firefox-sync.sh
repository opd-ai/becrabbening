#!/usr/bin/env bash
# firefox-sync.sh — Manage the Firefox git submodule for becrabbening
#
# Keeps a working copy of Firefox in this repo as a submodule,
# creates per-target oxidize branches, merges completed work,
# and stays up-to-date with upstream mozilla-central.
#
# Usage:
#   bash firefox-sync.sh <command> [args...]
#
# Commands:
#   init                Add Firefox as a git submodule (first-time setup)
#   sync                Update the submodule from upstream Mozilla
#   branch <name>       Create an oxidize/{name} branch in the submodule
#   merge  <name>       Merge a completed oxidize/{name} branch into main
#   status              Show the current Firefox submodule state
#
# Environment:
#   FIREFOX_FORK        Git URL for the owner's Firefox fork — where PRs and
#                       pushes go (REQUIRED for init; e.g. https://github.com/YOU/firefox)
#   FIREFOX_UPSTREAM    Git URL for upstream Mozilla (default: https://github.com/mozilla-firefox/firefox)
#                       Used as a read-only sync source — never push to this.
#   FIREFOX_DIR         Submodule directory name (default: firefox)
#   FIREFOX_BRANCH      Upstream branch to track (default: main)

set -euo pipefail

# ─── Constants and defaults ──────────────────────────────────────────────────

FIREFOX_UPSTREAM="${FIREFOX_UPSTREAM:-${FIREFOX_REPO:-https://github.com/mozilla-firefox/firefox}}"
FIREFOX_FORK="${FIREFOX_FORK:-}"
FIREFOX_DIR="${FIREFOX_DIR:-firefox}"
FIREFOX_BRANCH="${FIREFOX_BRANCH:-main}"

# Known upstream hosts that must never receive PRs or pushes.
# Matches Mozilla-owned repos (mozilla/, mozilla-firefox/, mozilla-central/, etc.)
UPSTREAM_PATTERNS="github.com/mozilla"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

# ─── Helpers ─────────────────────────────────────────────────────────────────

die() {
    echo "ERROR: $*" >&2
    exit 1
}

info() {
    echo "==> $*"
}

# Safety check: refuse to push or create PRs against upstream Mozilla or
# any repo that is not the owner's fork.  Only the fork receives writes.
assert_not_upstream() {
    local url="$1"
    local context="${2:-remote URL}"
    for pattern in $UPSTREAM_PATTERNS; do
        if echo "$url" | grep -qi "$pattern"; then
            die "$context ($url) appears to be an upstream Mozilla repo.
  PRs and pushes must target your own fork, not upstream.
  Set FIREFOX_FORK to your fork URL (e.g. https://github.com/YOU/firefox)."
        fi
    done
}

# ─── Command: init ───────────────────────────────────────────────────────────

cmd_init() {
    info "Initializing Firefox submodule"

    cd "$REPO_ROOT"

    # Determine the clone URL.  Prefer the owner's fork; fall back to
    # FIREFOX_UPSTREAM with a loud warning so the user knows PRs will
    # not work until a fork is configured.
    local clone_url="${FIREFOX_FORK:-}"
    if [ -z "$clone_url" ]; then
        echo "WARNING: FIREFOX_FORK is not set." >&2
        echo "  The submodule will be cloned from upstream ($FIREFOX_UPSTREAM) as a" >&2
        echo "  read-only working copy.  You will NOT be able to push or open PRs" >&2
        echo "  until you set FIREFOX_FORK to your own fork URL." >&2
        clone_url="$FIREFOX_UPSTREAM"
    else
        assert_not_upstream "$clone_url" "FIREFOX_FORK"
    fi

    if [ -f ".gitmodules" ] && grep -q "$FIREFOX_DIR" .gitmodules 2>/dev/null; then
        info "Submodule entry already exists in .gitmodules."

        if [ ! -d "$FIREFOX_DIR/.git" ] && [ ! -f "$FIREFOX_DIR/.git" ]; then
            info "Submodule directory not initialized. Running git submodule update..."
            git submodule update --init --depth 1 "$FIREFOX_DIR"
        else
            info "Submodule already initialized at $FIREFOX_DIR."
        fi
    else
        if [ -d "$FIREFOX_DIR" ]; then
            die "$FIREFOX_DIR directory already exists but is not a submodule. Remove it first."
        fi

        info "Adding submodule: $clone_url -> $FIREFOX_DIR"
        git submodule add --depth 1 --branch "$FIREFOX_BRANCH" "$clone_url" "$FIREFOX_DIR"
        info "Submodule added. Commit the .gitmodules and $FIREFOX_DIR changes."
    fi

    # Ensure upstream remote is set for read-only sync (separate from origin).
    cd "$FIREFOX_DIR"
    if ! git remote get-url upstream &>/dev/null; then
        info "Adding upstream remote for read-only sync: $FIREFOX_UPSTREAM"
        git remote add upstream "$FIREFOX_UPSTREAM"
    fi
    cd "$REPO_ROOT"

    info "Firefox submodule ready at $FIREFOX_DIR/"
}

# ─── Command: sync ───────────────────────────────────────────────────────────

cmd_sync() {
    info "Syncing Firefox submodule with upstream"

    cd "$REPO_ROOT"

    if [ ! -d "$FIREFOX_DIR/.git" ] && [ ! -f "$FIREFOX_DIR/.git" ]; then
        die "Firefox submodule not initialized. Run: bash firefox-sync.sh init"
    fi

    cd "$FIREFOX_DIR"

    # Ensure upstream remote exists (read-only sync source)
    if ! git remote get-url upstream &>/dev/null; then
        info "Adding upstream remote: $FIREFOX_UPSTREAM"
        git remote add upstream "$FIREFOX_UPSTREAM"
    fi

    info "Fetching upstream $FIREFOX_BRANCH..."
    git fetch upstream "$FIREFOX_BRANCH"

    # Get current branch
    current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")"

    if [ "$current_branch" = "HEAD" ] || [ "$current_branch" = "$FIREFOX_BRANCH" ] || [ "$current_branch" = "main" ]; then
        # On main/master/detached: fast-forward to upstream
        info "Updating $FIREFOX_BRANCH to upstream..."
        if git rev-parse --verify "$FIREFOX_BRANCH" &>/dev/null; then
            git checkout "$FIREFOX_BRANCH"
        else
            git checkout -b "$FIREFOX_BRANCH" "upstream/$FIREFOX_BRANCH"
        fi
        git merge --ff-only "upstream/$FIREFOX_BRANCH" || {
            die "Fast-forward merge failed for $FIREFOX_BRANCH. The local branch has diverged from upstream.
  To fix: cd $FIREFOX_DIR && git rebase upstream/$FIREFOX_BRANCH"
        }
    else
        info "Currently on branch $current_branch — not auto-merging upstream."
        info "Switch to $FIREFOX_BRANCH and run sync again, or rebase manually."
    fi

    # Update the submodule reference in the parent repo
    cd "$REPO_ROOT"
    info "Updating submodule reference in parent repo..."
    git add "$FIREFOX_DIR"

    if ! git diff --cached --quiet "$FIREFOX_DIR"; then
        git commit --only -- "$FIREFOX_DIR" -m "chore: update Firefox submodule to latest upstream"
        info "Submodule reference updated and committed."
    else
        info "Submodule already at latest upstream."
    fi
}

# ─── Command: branch ─────────────────────────────────────────────────────────

cmd_branch() {
    local name="${1:-}"
    if [ -z "$name" ]; then
        die "Usage: firefox-sync.sh branch <name>"
    fi

    info "Creating oxidize/$name branch in Firefox submodule"

    cd "$REPO_ROOT"

    if [ ! -d "$FIREFOX_DIR/.git" ] && [ ! -f "$FIREFOX_DIR/.git" ]; then
        die "Firefox submodule not initialized. Run: bash firefox-sync.sh init"
    fi

    cd "$FIREFOX_DIR"

    # Ensure we're on a clean state
    if ! git diff --quiet || ! git diff --cached --quiet; then
        die "Firefox submodule has uncommitted changes. Commit or stash them first."
    fi

    # Create the oxidize branch from the current main
    if git rev-parse --verify "oxidize/$name" &>/dev/null; then
        info "Branch oxidize/$name already exists. Checking it out."
        git checkout "oxidize/$name"
    else
        # Start from the main tracking branch
        if ! git checkout "$FIREFOX_BRANCH" 2>/dev/null; then
            if ! git checkout main 2>/dev/null; then
                die "Cannot find branch $FIREFOX_BRANCH or main to base oxidize/$name on."
            fi
        fi
        git checkout -b "oxidize/$name"
        info "Created and switched to branch oxidize/$name"
    fi
}

# ─── Command: merge ──────────────────────────────────────────────────────────

cmd_merge() {
    local name="${1:-}"
    if [ -z "$name" ]; then
        die "Usage: firefox-sync.sh merge <name>"
    fi

    info "Merging oxidize/$name into $FIREFOX_BRANCH in Firefox submodule"

    cd "$REPO_ROOT"

    if [ ! -d "$FIREFOX_DIR/.git" ] && [ ! -f "$FIREFOX_DIR/.git" ]; then
        die "Firefox submodule not initialized. Run: bash firefox-sync.sh init"
    fi

    cd "$FIREFOX_DIR"

    # Verify the branch exists
    if ! git rev-parse --verify "oxidize/$name" &>/dev/null; then
        die "Branch oxidize/$name does not exist in the Firefox submodule."
    fi

    # Switch to main
    git checkout "$FIREFOX_BRANCH" 2>/dev/null || git checkout main

    # Fast-forward merge only (linear history required)
    if ! git merge --ff-only "oxidize/$name"; then
        die "Fast-forward merge failed for oxidize/$name. Rebase the branch first:
  cd $FIREFOX_DIR && git rebase $FIREFOX_BRANCH oxidize/$name"
    fi
    info "Fast-forward merge successful."

    # Tag the completed conversion (guard against re-runs)
    if git rev-parse -q --verify "refs/tags/oxidized/$name" &>/dev/null; then
        info "Tag oxidized/$name already exists — skipping."
    else
        git tag "oxidized/$name"
        info "Tagged oxidized/$name"
    fi

    # Update the submodule reference in the parent repo
    cd "$REPO_ROOT"
    git add "$FIREFOX_DIR"

    if ! git diff --cached --quiet "$FIREFOX_DIR"; then
        git commit --only -- "$FIREFOX_DIR" -m "oxidize($name): update Firefox submodule after merge"
        info "Submodule reference updated in parent repo."
    fi

    info "Merge complete for oxidize/$name"
}

# ─── Command: status ─────────────────────────────────────────────────────────

cmd_status() {
    info "Firefox submodule status"

    cd "$REPO_ROOT"

    echo ""

    # Check if submodule is configured
    if [ ! -f ".gitmodules" ] || ! grep -q "$FIREFOX_DIR" .gitmodules 2>/dev/null; then
        echo "  Submodule: NOT CONFIGURED"
        echo "  Run: bash firefox-sync.sh init"
        return
    fi

    echo "  Submodule: configured"

    # Check if submodule is initialized
    if [ ! -d "$FIREFOX_DIR/.git" ] && [ ! -f "$FIREFOX_DIR/.git" ]; then
        echo "  Initialized: no"
        echo "  Run: git submodule update --init $FIREFOX_DIR"
        return
    fi

    echo "  Initialized: yes"

    cd "$FIREFOX_DIR"

    # Current branch
    current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")"
    echo "  Branch: $current_branch"

    # Current commit
    current_sha="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"
    echo "  Commit: $current_sha"

    # Dirty state
    if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
        echo "  Working tree: clean"
    else
        echo "  Working tree: DIRTY (uncommitted changes)"
    fi

    # List oxidize branches
    oxidize_branches=$(git branch --list 'oxidize/*' 2>/dev/null | wc -l)
    echo "  Oxidize branches: $oxidize_branches"
    if [ "$oxidize_branches" -gt 0 ]; then
        git branch --list 'oxidize/*' 2>/dev/null | while IFS= read -r branch; do
            echo "    $branch"
        done
    fi

    # List oxidized tags
    oxidized_tags=$(git tag --list 'oxidized/*' 2>/dev/null | wc -l)
    echo "  Completed conversions (tags): $oxidized_tags"
    if [ "$oxidized_tags" -gt 0 ]; then
        git tag --list 'oxidized/*' 2>/dev/null | while IFS= read -r tag; do
            echo "    $tag"
        done
    fi
}

# ─── Main dispatch ───────────────────────────────────────────────────────────

command="${1:-}"
shift || true

case "$command" in
    init)
        cmd_init "$@"
        ;;
    sync)
        cmd_sync "$@"
        ;;
    branch)
        cmd_branch "$@"
        ;;
    merge)
        cmd_merge "$@"
        ;;
    status)
        cmd_status "$@"
        ;;
    ""|help|-h|--help)
        echo "Usage: firefox-sync.sh <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  init                Add Firefox as a git submodule (first-time setup)"
        echo "  sync                Update the submodule from upstream Mozilla"
        echo "  branch <name>       Create an oxidize/{name} branch in the submodule"
        echo "  merge  <name>       Merge a completed oxidize/{name} branch into main"
        echo "  status              Show the current Firefox submodule state"
        echo ""
        echo "Environment:"
        echo "  FIREFOX_FORK        Git URL for your Firefox fork (required for push/PR)"
        echo "                      (e.g. https://github.com/YOU/firefox)"
        echo "  FIREFOX_UPSTREAM    Git URL for upstream Mozilla (read-only sync source)"
        echo "                      (default: https://github.com/mozilla-firefox/firefox)"
        echo "  FIREFOX_DIR         Submodule directory name (default: firefox)"
        echo "  FIREFOX_BRANCH      Upstream branch to track (default: main)"
        ;;
    *)
        die "Unknown command: $command. Run 'firefox-sync.sh help' for usage."
        ;;
esac
