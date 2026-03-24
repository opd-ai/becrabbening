# TASK: Analyze the Firefox source tree and generate the next batch of conversion targets for TARGETS.md.

## Execution Mode
**Report generation only** — produce a TARGETS.md file. Do not modify any source code.

## Output
Write exactly one file: **`TARGETS.md`** in the working directory.
If `TARGETS.md` already exists, preserve completed entries (`- [x]`) and regenerate the pending list.

## Context
Read the becrabbening documentation to understand target selection:
- [ROADMAP.md](./ROADMAP.md) — target selection strategy and milestone definitions
- [00-OVERVIEW.md](./00-OVERVIEW.md) — the full conversion loop
- [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md) — conflict gate and serialization rules

## Workflow

### Phase 0: Understand the Dependency Graph
1. Scan the source tree for all C/C++ file-pairs (`.c` + `.h`, `.cpp` + `.h`, or `.h`-only).
2. Exclude third-party code, test files, and already-converted files.
3. A file is "already converted" if its `.h` contains only a `#include` redirect to a `*_shim.h` file (Phase 4 switchover has been applied).

### Phase 1: Build the #include Dependency Graph
For each unconverted header:
1. Parse `#include` directives to identify which other unconverted headers it depends on.
2. Build a directed graph: an edge from A → B means "A includes B".

### Phase 2: Identify Leaf Nodes
A **leaf node** is a file-pair where no other unconverted file includes its header.

Leaf nodes are safe to convert first because:
- They have no downstream callers that would break during conversion.
- They satisfy Rule 1 (one-pair-at-a-time) from the conflict avoidance rules.

From [ROADMAP.md](./ROADMAP.md):
> Never convert a file before all files that include it (its "callers") are already converted.

### Phase 3: Rank Candidates
Sort leaf-node candidates by these criteria (in order):
1. **Smaller API surface first** — fewer public symbols means less to shim and test.
2. **Existing test coverage** — files with tests are easier to write contract tests for.
3. **Standalone utility files first** — string helpers, math utils, data structures.

### Phase 4: Conflict Gate Check
For each candidate, verify:
1. No open PR touches the candidate files.
2. The file-pair is not currently assigned to another conversion.

```bash
gh pr list --state open --json files --jq '.[].files[].path' | grep {name}
```

Skip candidates that fail the conflict gate.

### Phase 5: Write TARGETS.md
Write the file in the format that `loop.sh` expects:

```markdown
# Conversion Targets

## Completed
- [x] nsFoo
- [x] nsBar

## Pending
- [ ] nsNextTarget
- [ ] nsAnotherTarget
```

## Selection Rules (from ROADMAP.md)
1. Never convert a file before all its dependents (callers) are converted.
2. Prefer files with a smaller public API surface.
3. Prefer files with existing test coverage.
4. Non-overlapping subtrees can be listed together (they parallelize safely).
5. Files sharing a common header must be serialized (list them in dependency order).

## Milestone Mapping
- **M1 (Leaf Nodes)**: Isolated utilities with no downstream dependents — target these first.
- **M2 (Mid-Tree)**: Files with moderate fan-in, after all dependents from M1 are converted.
- **M3 (Core)**: Widely-included headers — target these last.

## Output Format
```markdown
# Conversion Targets

Generated on [date] by generate-targets.sh.

Source directory: `[path]`

Selection criteria: leaf-first topological order, smallest API surface first.
See [ROADMAP.md](./ROADMAP.md) for the target selection strategy.

## Completed
- [x] previouslyDone

## Pending
- [ ] nextTarget
- [ ] anotherTarget
```

## What NOT to Do
- Do **not** modify any source files. This task is read-only.
- Do **not** include third-party code as targets.
- Do **not** include test files as targets.
- Do **not** list files that are already converted (redirected to shim).
- Do **not** list files that have open PRs touching them.
