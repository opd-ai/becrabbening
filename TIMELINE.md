# Timeline — How Long to Rewrite Firefox in Rust?

An analysis of conversion timetables for the Becrabbening at various throughput
rates, from 20 to 200 file-pair conversions per day, and the implications for
the process, quality, and the finished product.

---

## Table of Contents

- [Scope of the Problem](#scope-of-the-problem)
- [Conversion Timetable](#conversion-timetable)
- [What Each Rate Actually Means](#what-each-rate-actually-means)
- [The Dependency Bottleneck](#the-dependency-bottleneck)
- [Quality vs. Speed Trade-offs](#quality-vs-speed-trade-offs)
- [Cost Implications](#cost-implications)
- [The Moving Target Problem](#the-moving-target-problem)
- [Practical Recommendations](#practical-recommendations)
- [Appendix: Assumptions and Data Sources](#appendix-assumptions-and-data-sources)

---

## Scope of the Problem

### How big is Firefox?

Firefox (mozilla-central) contains approximately:

| File Type | Estimated Count | Notes |
|-----------|-----------------|-------|
| `.cpp` files | ~5,000–8,000 | C++ source implementations |
| `.c` files | ~600–2,000 | C source implementations |
| `.h` files | ~7,000–10,000 | Headers (C and C++) |
| **Total source files** | **~12,000–20,000** | All C/C++ source and headers |

Lines of code (per [OpenHub](https://openhub.net/p/firefox/analyses/latest/languages_summary)):

| Language | Code Lines | % of Codebase |
|----------|-----------|---------------|
| C++ | ~7,960,000 | ~26.7% |
| C | ~4,100,000 | ~13.8% |
| Rust (already) | ~3,860,000 | ~11.7% |
| Other (JS, HTML, Python, etc.) | ~14,300,000+ | ~47.8% |

> **Note**: Percentages are from [OpenHub](https://openhub.net/p/firefox/analyses/latest/languages_summary)
> and reflect their analysis of the full codebase (~30M+ total lines). The
> "Other" category includes JavaScript, HTML, Python, XML, Kotlin, Assembly,
> and more.

### What needs converting?

Not everything. The Becrabbening converts C/C++ file-pairs — a `.cpp`/`.c`
source paired with its `.h` header, or standalone `.h` headers. The scope
excludes:

- **Third-party/vendored code** (`third_party/`, `nsprpub/`, etc.) — not
  Mozilla's to rewrite; maintained upstream
- **Test files** (`**/test/**`, `**/tests/**`, `**/*_test.*`) — tests exercise
  converted code, they don't need conversion
- **Build system files** (`moz.build`, `Makefile`, etc.) — not C/C++
- **JavaScript/HTML/Python** — different language, different problem
- **Already-Rust code** (~3.86M lines) — already done (WebRender, Servo
  components, etc.)

After exclusions, the realistic conversion target is approximately:

| Category | Estimated File-Pairs | Rationale |
|----------|---------------------|-----------|
| **First-party `.cpp` + `.h` pairs** | ~3,000–5,500 | `.cpp` files with matching `.h` |
| **First-party `.c` + `.h` pairs** | ~400–1,200 | `.c` files with matching `.h` |
| **Header-only conversions** | ~500–1,500 | `.h` files with no source file |
| **Total conversion targets** | **~4,000–8,000** | Reasonable working range |

For the timetable below, we model three scenarios:

- **Conservative**: 8,000 file-pairs (upper bound)
- **Moderate**: 6,000 file-pairs (midpoint estimate)
- **Optimistic**: 4,000 file-pairs (lower bound, aggressive exclusions)

---

## Conversion Timetable

### Duration at Various Daily Rates

Each cell shows **calendar days** to complete all conversions at the given rate,
assuming 7-day work weeks (automated pipeline runs continuously).

| Daily Rate | 4,000 pairs | 6,000 pairs | 8,000 pairs |
|-----------:|:-----------:|:-----------:|:-----------:|
| **20/day** | 200 days | 300 days | 400 days |
| **30/day** | 134 days | 200 days | 267 days |
| **40/day** | 100 days | 150 days | 200 days |
| **50/day** | 80 days | 120 days | 160 days |
| **75/day** | 54 days | 80 days | 107 days |
| **100/day** | 40 days | 60 days | 80 days |
| **125/day** | 32 days | 48 days | 64 days |
| **150/day** | 27 days | 40 days | 54 days |
| **175/day** | 23 days | 35 days | 46 days |
| **200/day** | 20 days | 30 days | 40 days |

### The Same Data in Months and Years

| Daily Rate | 4,000 pairs | 6,000 pairs | 8,000 pairs |
|-----------:|:-----------:|:-----------:|:-----------:|
| **20/day** | 6.7 months | 10 months | 13.3 months |
| **30/day** | 4.5 months | 6.7 months | 8.9 months |
| **40/day** | 3.3 months | 5 months | 6.7 months |
| **50/day** | 2.7 months | 4 months | 5.3 months |
| **75/day** | 1.8 months | 2.7 months | 3.6 months |
| **100/day** | 1.3 months | 2 months | 2.7 months |
| **125/day** | 1.1 months | 1.6 months | 2.1 months |
| **150/day** | 0.9 months | 1.3 months | 1.8 months |
| **175/day** | 0.8 months | 1.1 months | 1.5 months |
| **200/day** | 0.7 months | 1 month | 1.3 months |

### Baseline at 50/Day (Model-Agnostic Scenario)

At 50 conversions per day with the moderate estimate of 6,000 file-pairs, assuming the documented GitHub Copilot CLI–driven workflow (configured with your preferred LLM backend):

```
6,000 file-pairs ÷ 50/day = 120 calendar days ≈ 4 months
```

That's the headline number. But the real story is more complex.

---

## What Each Rate Actually Means

### Per-Conversion Time Budget

Each conversion goes through 7 phases plus the anti-slop audit. The time
budget per conversion at different daily rates, assuming a 24-hour automated
pipeline:

| Daily Rate | Minutes per Conversion | Phase Budget Breakdown |
|-----------:|-----------------------:|----------------------:|
| **20/day** | 72 min | Comfortable for all phases |
| **50/day** | 28.8 min | Tight; requires fast AI + fast builds |
| **100/day** | 14.4 min | Requires parallelization |
| **200/day** | 7.2 min | Only feasible with massive parallelism |

### Phase-by-Phase Time Estimates

Based on the phase documentation, a single conversion requires:

| Phase | Minimum | Typical | Maximum | Bottleneck |
|-------|--------:|--------:|--------:|-----------|
| 0 — Prepare | 15 min | 30 min | 2 hrs | API surface analysis complexity |
| 1 — Rust | 20 min | 1–2 hrs | 8 hrs | Code complexity; AI generation time |
| — Anti-Slop | 10 min | 30 min | 2 hrs | Number of slop patterns found |
| 2 — C FFI | 5 min | 15 min | 30 min | cbindgen run + verification |
| 3 — C/C++ Shim | 10 min | 30 min | 3 hrs | API surface size |
| 4 — Switchover | 2 min | 5 min | 15 min | Purely mechanical |
| 5 — Validate | 10 min | 30 min | 2 hrs | `mach build` + `mach test` duration |
| 6 — Merge | 2 min | 5 min | 10 min | PR creation + merge |
| **Total** | **~1.2 hrs** | **~3–5 hrs** | **~18 hrs** | |

### Implications by Rate Tier

#### 🐌 Low Rate: 20–30/day (Careful and Thorough)

- **Time per conversion**: 48–72 minutes
- **Parallelism needed**: 1–2 concurrent pipelines
- **Quality**: Highest. Every conversion gets full attention, complete
  anti-slop audit, thorough validation. Memory safety audit documents are
  comprehensive. Contract tests are robust.
- **Duration**: 6.7–10 months (moderate estimate)
- **Risk**: Firefox upstream development moves faster than conversion, creating
  an ever-growing backlog. See [The Moving Target Problem](#the-moving-target-problem).
- **Best for**: Initial rollout, establishing patterns, building confidence.

#### 🦀 Medium Rate: 40–75/day (The Sweet Spot)

- **Time per conversion**: 19–36 minutes
- **Parallelism needed**: 3–6 concurrent pipelines
- **Implementation note**: Each "pipeline" is a separate workdir/container with its own Firefox checkout, `loop.log`, and `test-output.txt`; do **not** just background multiple `loop.sh` runs in a single working directory.
- **Quality**: Good. AI-generated Rust code is audited but some edge cases may
  be caught later. Anti-slop audit is effective but time-boxed.
- **Duration**: 1.8–5 months (moderate estimate)
- **Risk**: Manageable conflict potential. Dependency ordering requires careful
  scheduling. Build validation (`mach build`) becomes the bottleneck — Firefox
  full builds take 30+ minutes.
- **Best for**: Steady-state production conversion once the workflow is proven.
- **Note**: 50/day falls here. A single `loop.sh` pipeline (one loop
  runner/workdir configured with a given model) running continuously can
  achieve this if average file complexity is moderate.

#### 🚀 High Rate: 100–150/day (Aggressive)

- **Time per conversion**: 10–14.4 minutes
- **Parallelism needed**: 8–15 concurrent pipelines on non-overlapping
  dependency subtrees
- **Quality**: Acceptable but requires post-conversion quality sweeps.
  Anti-slop audit is abbreviated. Some conversions may produce non-idiomatic
  Rust that compiles and passes tests but isn't optimal.
- **Duration**: 1.3–2 months (moderate estimate)
- **Risk**: High conflict risk between parallel pipelines. Dependency ordering
  violations become likely. `mach build` validation must be batched or deferred.
  Branch management overhead grows significantly.
- **Best for**: Sprints on well-isolated subsystems with many leaf nodes.

#### 🔥 Maximum Rate: 175–200/day (Theoretical Maximum)

- **Time per conversion**: 7–8 minutes per conversion
- **Parallelism needed**: 15–25+ concurrent pipelines
- **Quality**: Quantity over quality. Many conversions will be functionally
  correct but need follow-up cleanup. Memory safety audits are thin.
  Anti-slop audit may be skipped or reduced to clippy-only.
- **Duration**: 1–1.5 months (moderate estimate)
- **Risk**: Extreme. Merge conflicts near-certain. Dependency ordering breaks
  down. Build system integration (moz.build changes) may accumulate errors.
  The "one PR, one file-pair, no exceptions" rule is under severe pressure.
- **Best for**: Demonstration/proof of concept. Not recommended for
  production use.

---

## The Dependency Bottleneck

The timetable above assumes uniform throughput. Reality is messier because the
[ROADMAP.md](./ROADMAP.md) enforces a **leaf-first topological ordering**.

### The Dependency Funnel

```
            MILESTONE 1: Leaf Nodes
            ┌─────────────────────────────────────────────┐
            │  ████████████████████████████████████████    │
            │  ~60-70% of all file-pairs                  │
            │  Maximum parallelism, fewest constraints     │
            │  FAST: Can sustain 100+ conversions/day     │
            └─────────────────────────┬───────────────────┘
                                      │
                                      ▼
            MILESTONE 2: Mid-Tree
            ┌─────────────────────────────────────────────┐
            │  ██████████████████                          │
            │  ~20-25% of file-pairs                      │
            │  Moderate constraints, some serialization    │
            │  MEDIUM: Drops to 30-50 conversions/day     │
            └─────────────────────────┬───────────────────┘
                                      │
                                      ▼
            MILESTONE 3: Core Headers
            ┌─────────────────────────────────────────────┐
            │  ████████                                    │
            │  ~10-15% of file-pairs                      │
            │  High fan-in, strict serialization           │
            │  SLOW: Drops to 5-15 conversions/day        │
            └─────────────────────────────────────────────┘
```

### Effective Throughput Over Time

Even if your pipeline can handle 200/day during M1 (leaf nodes), it will
naturally slow during M2 and M3 due to serialization constraints. A realistic
projection for the full project:

| Phase | % of Work | Effective Rate | Duration (6,000 pairs) |
|-------|-----------|---------------|------------------------|
| M1 — Leaf Nodes | ~65% (3,900 pairs) | Target rate | Varies by target rate |
| M2 — Mid-Tree | ~23% (1,380 pairs) | ~40% of target | Serialization overhead |
| M3 — Core | ~12% (720 pairs) | ~15% of target | Strict ordering |

**Adjusted total durations** (factoring in the dependency funnel):

| Nominal Rate | M1 Duration | M2 Duration | M3 Duration | **Real Total** |
|-------------:|:-----------:|:-----------:|:-----------:|:--------------:|
| **20/day** | 195 days | 173 days | 240 days | **~608 days (~20 months)** |
| **50/day** | 78 days | 69 days | 96 days | **~243 days (~8 months)** |
| **100/day** | 39 days | 35 days | 48 days | **~122 days (~4 months)** |
| **200/day** | 20 days | 17 days | 24 days | **~61 days (~2 months)** |

> **Key insight**: The dependency funnel roughly doubles the naive timeline.
> The 50/day headline of "4 months" becomes more like **8 months** when you
> account for the serialization tax on mid-tree and core conversions.

---

## Quality vs. Speed Trade-offs

### The Anti-Slop Tax

The [anti-slop audit](./02b-ANTI-SLOP-AUDIT.md) checks for 15 categories of
AI-generated code smell. At higher rates, this audit becomes the quality
gatekeeper — or the first thing to be compromised.

| Rate | Anti-Slop Audit Depth | Expected Quality Impact |
|-----:|:---------------------:|------------------------|
| 20/day | Full: all 15 patterns + manual review | Highest quality Rust |
| 50/day | Standard: clippy pedantic + automated pattern scan | Good quality; rare misses |
| 100/day | Abbreviated: clippy warnings only | Some non-idiomatic patterns survive |
| 200/day | Minimal: `cargo clippy` basic only | Significant cleanup debt |

### Memory Safety Audit Depth

Every conversion requires a [MEMORIES file](./02-PHASE-1-RUST.md) documenting
memory safety issues in the original C/C++. At higher rates, these become less
thorough:

| Rate | Audit Depth | Bugs Found per File | Risk |
|-----:|:-----------:|:-------------------:|------|
| 20/day | Thorough line-by-line analysis | Most | Low — bugs are documented and fixed |
| 50/day | AI-assisted analysis with spot checks | Many | Low-Medium — some subtle bugs missed |
| 100/day | AI-only analysis, no manual verification | Some | Medium — false negatives likely |
| 200/day | Boilerplate "no issues found" | Few | High — defeats purpose of audit |

### The Quality Spectrum of the Finished Product

| Dimension | 20/day | 50/day | 100/day | 200/day |
|-----------|--------|--------|---------|---------|
| **Idiomatic Rust** | Excellent | Good | Fair | Poor — C-style Rust |
| **Memory safety improvement** | Significant | Good | Moderate | Minimal |
| **Documentation quality** | Thorough MEMORIES files | Adequate | Sparse | Perfunctory |
| **Test coverage** | Strong contract tests | Good | Basic | Brittle |
| **Cleanup debt** | Minimal | Low | Moderate | Massive |
| **Maintenance burden** | Lower than C++ | Similar to C++ | Worse initially | Much worse initially |

> **The paradox**: Converting at 200/day may technically "finish" in ~2 months,
> but the resulting Rust code could be worse than the C++ it replaced. You'd
> then need months of cleanup to achieve the quality that a 50/day pace would
> have delivered from the start.

---

## Cost Implications

### AI/LLM Cost per Conversion

Each conversion invokes the AI model multiple times (once per phase, plus
retries on failure). Using GitHub Copilot's premium request model:

| Component | Requests per Conversion | Notes |
|-----------|:-----------------------:|-------|
| Phase 0 (Prepare) | 1–2 | API analysis + contract test generation |
| Phase 1 (Rust) | 2–5 | Implementation + iterations |
| Anti-Slop Audit | 1–2 | Review + fix cycles |
| Phase 2 (C FFI) | 1 | cbindgen config + verification |
| Phase 3 (Shim) | 1–2 | Wrapper generation |
| Phase 4 (Switchover) | 1 | Mechanical replacement |
| Phase 5 (Validate) | 1 | Copilot VALIDATE.md prompt + local tooling (0 only in fully-manual mode) |
| Phase 6 (Merge) | 1 | PR creation |
| Retries on failure | 1–3 | FAIL.md re-prompting |
| **Total per conversion** | **~8–16** | **~12 average** |

### Monthly Cost Estimates

| Daily Rate | Requests/Day | Requests/Month | Cost (Pro @ $10/mo) | Cost (Pro+ @ $39/mo) |
|-----------:|:------------:|:--------------:|:-------------------:|:--------------------:|
| **20/day** | ~240 | ~7,200 | ~$286/mo | ~$267/mo |
| **50/day** | ~600 | ~18,000 | ~$718/mo | ~$699/mo |
| **100/day** | ~1,200 | ~36,000 | ~$1,438/mo | ~$1,419/mo |
| **200/day** | ~2,400 | ~72,000 | ~$2,878/mo | ~$2,859/mo |

> **Note**: These figures are illustrative estimates based on a snapshot of
> GitHub Copilot pricing (e.g., $10/mo Pro, $39/mo Pro+, 300 and 1,500 included
> premium requests, and $0.04/request overage) and may change over time. See
> the [official GitHub Copilot pricing](https://github.com/features/copilot#pricing)
> for current details. Estimates assume a 1× request multiplier (base model).
> Using, for example, Claude Opus (modeled here as a 10× multiplier) or GPT‑4.5
> (modeled here as a 50× multiplier) dramatically increases costs. Under these
> assumptions, a single 50/day pipeline on Claude Opus would cost on the order
> of ~$7,180/month in premium requests alone; always recompute using your
> provider's current documentation.

### Total Project Cost by Scenario (6,000 pairs, moderate estimate)

| Rate | Duration (adjusted) | Monthly Cost (base model) | **Total Cost** |
|-----:|:-------------------:|:-------------------------:|:--------------:|
| **20/day** | ~20 months | ~$286 | ~$5,720 |
| **50/day** | ~8 months | ~$718 | ~$5,744 |
| **100/day** | ~4 months | ~$1,438 | ~$5,752 |
| **200/day** | ~2 months | ~$2,878 | ~$5,756 |

> **Surprising result**: Total AI cost is roughly the same regardless of rate
> — you're doing the same number of conversions either way. The difference is
> in *elapsed time* and *quality*.

---

## The Moving Target Problem

Firefox is under active development. While you're converting C++ to Rust,
Mozilla's ~400 active contributors are writing new C++ (and new Rust, and
JavaScript, and...).

### Firefox Development Velocity

- Mozilla lands roughly **~100–200 commits per day** on mozilla-central
- Approximately **5–15 C/C++ files** are modified per day
- New C/C++ files are added at a rate of roughly **1–3 per week**
- C/C++ files are also deleted as Mozilla does their own refactoring

### Race Condition Analysis

| Conversion Rate | New C/C++ files/week | Net Progress/Week | Outpacing Development? |
|----------------:|:--------------------:|:------------------:|:----------------------:|
| **20/day** | ~2 | 138 net | ✅ Yes, by ~70x |
| **50/day** | ~2 | 348 net | ✅ Yes, by ~175x |
| **100/day** | ~2 | 698 net | ✅ Yes, by ~350x |
| **200/day** | ~2 | 1398 net | ✅ Yes, by ~700x |

The good news: at any rate above ~5/day, you're converting faster than Mozilla
is writing new C++. The bad news: existing files are *modified* frequently,
which means:

1. **Rebasing pain**: Long-running conversion branches will diverge from trunk.
   The [conflict avoidance rules](./08-CONFLICT-AVOIDANCE.md) mitigate this
   (Phases 0–3 are additive, Phase 4 is a complete file replacement), but
   rebases during Phase 5–6 may still fail.

2. **API surface drift**: A file's public API may change between when you
   snapshot it (Phase 0) and when you merge (Phase 6). At 20/day this is rare;
   at 200/day with dependency bottlenecks, some conversions may sit for weeks
   before they can merge.

3. **Stale contract tests**: Tests written in Phase 0 against today's API may
   not match tomorrow's API.

### Mitigation Strategies

- **Minimize cycle time**: Keep the Phase 0→Phase 6 duration as short as
  possible per file-pair. A conversion that completes in 30 minutes has a
  much lower chance of conflicting with upstream changes than one that takes
  a week.
- **Rebase just before merge**: The workflow already does this (Phase 6 rebases
  immediately before PR creation).
- **Abandon and restart**: If a conversion conflicts, it's cheaper to discard
  and re-convert from scratch than to manually resolve conflicts — the entire
  conversion is AI-generated anyway.
- **Convert recently-stable files first**: Prioritize files with low churn
  (few recent commits) over hot files that change weekly.

---

## Practical Recommendations

### The Recommended Plan

Based on this analysis, the recommended approach is a **phased ramp-up**:

```
Months 1–2:     20–30 conversions/day
                 ├─ Prove the workflow end-to-end
                 ├─ Establish quality baselines
                 ├─ Build tooling confidence
                 └─ Convert ~1,000–1,800 leaf nodes

Months 3–4:     50–75 conversions/day
                 ├─ Scale up with proven workflow
                 ├─ Tackle remaining leaf nodes
                 ├─ Begin mid-tree conversions
                 └─ Convert ~3,000–4,500 file-pairs

Months 5–6:     30–50 conversions/day (natural slowdown)
                 ├─ Mid-tree serialization reduces throughput
                 ├─ More complex files require more time
                 └─ Convert ~1,000–2,000 file-pairs

Months 7–8:     10–20 conversions/day (core phase)
                 ├─ Core headers with highest fan-in
                 ├─ Strict serialization, careful validation
                 └─ Convert final ~500–1,000 file-pairs

Month 9:        Cleanup and stabilization
                 ├─ Quality sweeps on fast-converted code
                 ├─ Cleanup PRs (delete dead .cpp/.c files)
                 └─ Final validation and documentation
```

**Total estimated duration: 8–9 months** for the moderate estimate of 6,000
file-pairs.

### What "Done" Looks Like

When all conversions are merged, Firefox will have:

- **~6,000 new Rust crates** in `rust/*/`, totaling several million lines of
  Rust
- **~6,000 C FFI headers** (`*_ffi.h`), generated by cbindgen
- **~6,000 C/C++ shim headers** (`*_shim.h`), providing backward-compatible
  wrappers
- **~10,000–12,000 gutted original source and header files** (`.h` and
  `.cpp`/`.c`), each containing only a single `#include` redirect
- **~6,000 MEMORIES files** (one per converted file-pair) documenting
  discovered memory safety issues in the original C/C++ code

The C/C++ shim layer remains as a thin compatibility layer. Callers are unchanged.
The actual implementation lives in Rust.

### What "Done" Does NOT Look Like

- It does **not** mean "zero C++ in Firefox." The shim layer is still C/C++.
  Third-party code is still C/C++. SpiderMonkey (the JS engine) is a separate
  large codebase that may not be covered. NSPR and NSS are external.
- It does **not** mean "all bugs are fixed." The AI will miss some memory
  safety issues. Some Rust code will be non-idiomatic. Some contract tests
  will be inadequate.
- It does **not** mean "no more maintenance." The Rust code needs maintenance
  just like the C++ code did. The shim layer adds complexity.

---

## Appendix: Assumptions and Data Sources

### Firefox Codebase Size

- Source: [OpenHub Firefox Language Summary](https://openhub.net/p/firefox/analyses/latest/languages_summary)
- C++ lines: ~7,960,000; C lines: ~4,100,000; Rust: ~3,860,000
- File counts are estimated ranges based on community analyses and `find`
  command results on mozilla-central checkouts
- Exclusions (third-party, tests) reduce the target count by ~40–50%

### Conversion Time Estimates

- Phase durations are drawn from the Becrabbening phase documentation
  ([01-PHASE-0-PREPARE.md](./01-PHASE-0-PREPARE.md) through
  [07-PHASE-6-MERGE.md](./07-PHASE-6-MERGE.md))
- `mach build` full build time for Firefox: ~30–60 minutes on modern hardware
- `mach test` full test suite: varies by component, ~30 minutes to several
  hours

### AI/LLM Cost Model

- Based on GitHub Copilot premium request pricing (2025):
  Pro plan: 300 included, $0.04/request overage;
  Pro+ plan: 1,500 included, $0.04/request overage
- Request multipliers for premium models: Claude Opus 4 = 10x,
  Claude Sonnet = 1x–1.25x, GPT-4.5 = 50x
- Estimated ~12 premium requests per conversion (average across all phases
  including retries)

### Dependency Structure

- Leaf-first topological ordering per [ROADMAP.md](./ROADMAP.md)
- Estimated distribution: ~65% leaf nodes (M1), ~23% mid-tree (M2),
  ~12% core (M3)
- Serialization overhead estimated at 2.5x for mid-tree, 6.7x for core headers
- These ratios are rough estimates; actual distribution depends on the Firefox
  include dependency graph

### Conversion Rate Definitions

- All rates assume **24/7 automated operation** via `loop.sh`
- "50/day" means 50 complete Phase 0→Phase 6 cycles per 24-hour period
- Rates above 50/day require **multiple parallel pipelines** operating on
  non-overlapping dependency subtrees
- Failure/retry cycles are included in the rate (i.e., 50/day means 50
  *successful* merges, not 50 attempts)

---

## Cross-References

- [00-OVERVIEW.md](./00-OVERVIEW.md) — the full conversion loop
- [ROADMAP.md](./ROADMAP.md) — milestone planning and target selection
- [02b-ANTI-SLOP-AUDIT.md](./02b-ANTI-SLOP-AUDIT.md) — anti-slop quality gate
- [08-CONFLICT-AVOIDANCE.md](./08-CONFLICT-AVOIDANCE.md) — conflict avoidance rules
- [09-CHECKLIST-TEMPLATE.md](./09-CHECKLIST-TEMPLATE.md) — PR quality checklist
