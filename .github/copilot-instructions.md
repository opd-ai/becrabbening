# Project Overview

The Becrabbening is a systematic methodology for incrementally replacing C++ code in Mozilla Firefox with Rust, one file-pair at a time, while maintaining full backward compatibility and eliminating merge conflicts. It implements a **three-layer sandwich architecture** — Rust (Layer 1) → C FFI (Layer 2) → C++ Shim (Layer 3) — so that existing C++ callers never need modification.

This repository is a documentation-and-tooling template that defines the seven-phase oxidation loop (Phases 0–6), provides automation scripts for GitHub Copilot CLI–driven conversions, and includes a complete worked example (`examples/nsfoo/`). It targets Firefox contributors, Rust-in-C++ integration engineers, and AI-assisted code generation agents performing systematic C++-to-Rust conversions within large codebases.

Key technologies include Rust (2021 edition, `staticlib` crate type), `cbindgen` for C header generation, Bash automation scripts (`loop.sh`, `generate-targets.sh`, `firefox-sync.sh`), and Mozilla's `mach` build system for validation. The project enforces an additive-before-subtractive strategy where Phases 0–3 only create new files (zero conflict risk) and only Phase 4 edits existing files with minimal atomic changes.

## Technical Stack

- **Primary Language**: Rust (edition 2021) for replacement implementations; C++ for shim wrappers; Bash for automation
- **FFI Tooling**: `cbindgen` — generates pure-C headers from Rust `extern "C"` exports; configured via `cbindgen.toml` per crate
- **Build System**: Mozilla `mach` (for Firefox integration); `cargo` for Rust crate builds (`cargo test`, `cargo clippy -- -D warnings`)
- **Testing**: Rust built-in `#[cfg(test)]` unit tests, contract tests written in Phase 0, `mach test` for integration validation, ABI symbol checks via `nm`
- **Automation**: `loop.sh` (orchestrator), `generate-targets.sh` (dependency graph scanner), `firefox-sync.sh` (git submodule manager)
- **Version Control**: Git with `--ff-only` merges, `oxidize/{name}` branch naming, `oxidized/{name}` tags after merge

## Code Assistance Guidelines

1. **Follow the Seven-Phase Workflow Sequentially**: Every conversion must proceed through Phases 0–6 in order. Never skip phases. Phases 0–3 are purely additive (new files only); Phase 4 is the only phase that edits existing files; Phase 5 validates; Phase 6 merges. Refer to the phase documents (`01-PHASE-0-PREPARE.md` through `07-PHASE-6-MERGE.md`) for detailed instructions.

2. **Use the `fox_{name}_*` FFI Naming Convention**: All exported Rust symbols must use the `fox_{name}_` prefix (e.g., `fox_nsfoo_new`, `fox_nsfoo_bar`, `fox_nsfoo_free`). C types use the `Fox` prefix (e.g., `FoxNsFoo`). This prevents symbol collisions and identifies Rust-backed symbols. See `02-PHASE-1-RUST.md` and `examples/nsfoo/lib.rs`.

3. **Wrap Every `extern "C"` Function in `catch_unwind`**: Rust panics must never cross the FFI boundary (undefined behavior). Every `extern "C"` function body must be wrapped in `std::panic::catch_unwind`. On panic, return a sentinel error value or abort. Provide `_new` and `_free` lifecycle functions for every opaque handle type. See `examples/nsfoo/lib.rs` for the canonical pattern.

4. **Write Idiomatic Rust, Not Transliterated C++**: Use `Result<T, E>` for error handling internally, iterators instead of raw loops, `String` and `Vec<T>` internally with C-type conversion only at the FFI boundary. Use `#[repr(C)]` only for types that must cross the ABI boundary. Keep opaque wrapper structs (e.g., `FoxNsFoo(NsFoo)`) without `#[repr(C)]` — cbindgen emits them as opaque `typedef struct`.

5. **Maintain Zero-Conflict Discipline**: Never open two PRs that modify the same file. Check the conflict gate before starting any conversion: prerequisite conversions merged, no open PRs on the target files, trunk is green. Use complete file replacement in Phase 4 (single `#include` line) rather than partial edits. Defer file deletions and renames to separate cleanup PRs. See `08-CONFLICT-AVOIDANCE.md`.

6. **One File-Pair Per PR, No Exceptions**: Each PR converts exactly one `.cpp` + `.h` pair (or `.h`-only). Never bundle multiple conversions. Each PR must be independently revertable. Copy `09-CHECKLIST-TEMPLATE.md` into the PR description and verify every item.

7. **Complete Feature Implementations**: Always prefer completing the full implementation of any feature rather than leaving partial or placeholder code. When a complete implementation is not feasible, insert clear inline `TODO` comments describing what remains, why it was deferred, and any known constraints (e.g., `// TODO: Implement retry logic once the error categorization schema is finalized`). Never leave code in a silently incomplete state.

## Project Context

- **Domain**: Firefox browser engine C++-to-Rust migration. The core concept is "carcinization" — systematically replacing C++ internals with Rust while preserving the identical C++ public API for all existing callers. Understanding the three-layer sandwich (Rust → C FFI → C++ Shim) is essential for every code contribution.
- **Architecture**: The three-layer sandwich ensures callers never change. Layer 1 (Rust in `rust/{name}/src/lib.rs`) holds idiomatic logic; Layer 2 (`{name}_ffi.h`, generated by cbindgen) provides the pure-C ABI boundary; Layer 3 (`{name}_shim.h`) wraps C FFI calls in a C++ class with the identical original API. Phase 4 switchover guts the original `.h`/`.cpp` to single `#include` redirects.
- **Key Directories**: `examples/nsfoo/` contains a complete worked example of all three layers plus switchover artifacts. `prompts/` contains LLM prompt templates for each phase (used by `loop.sh`). Phase documentation lives in numbered markdown files at the repo root (`00-OVERVIEW.md` through `09-CHECKLIST-TEMPLATE.md`). Actual Rust crates are created at `rust/{name}/` during conversions.
- **Configuration**: Each Rust crate requires a `cbindgen.toml` with `language = "C"`, `Fox` export prefix, and an include guard matching `fox_{name}_ffi_h`. Crates use `crate-type = ["staticlib"]` for linking into the Firefox build. Mozilla's `moz.build` integrates the static archive — keep `moz.build` diffs under 5 lines per PR or split into a separate PR.
- **Automation Scripts**: `loop.sh` orchestrates the full oxidation loop by delegating each phase to GitHub Copilot CLI via prompt files. `generate-targets.sh` scans the Firefox source tree for C++ file-pairs, builds an `#include` dependency graph, and identifies leaf nodes for conversion. `firefox-sync.sh` manages the Firefox git submodule (`init`, `sync`, `branch`, `merge`, `status`). All scripts use POSIX ERE–compatible regex (`[[:space:]]` instead of `\s`) for Linux/macOS portability.

## Quality Standards

- **Testing**: Write contract tests in Phase 0 before any conversion begins. Maintain passing `cargo test` and `cargo clippy -- -D warnings` (zero warnings) for every Rust crate. Validate with `mach build` and `mach test` in Phase 5. Verify ABI compatibility with `nm` symbol diff — no missing symbols allowed.
- **Code Review**: Every oxidation PR must include the completed checklist from `09-CHECKLIST-TEMPLATE.md`. Reviewers verify: identical public API preservation, `catch_unwind` on all `extern "C"` functions, `fox_{name}_*` naming, single-pair scope, and conflict gate compliance.
- **Documentation**: Each conversion follows the phase documents verbatim. New Rust crates include rustdoc comments on all public items and `/// # Safety` sections on all `unsafe` FFI functions. Update the tracking spreadsheet (see `ROADMAP.md`) when status changes.
- **Shell Scripts**: All Bash scripts must use POSIX ERE–compatible patterns (`[[:space:]]` not `\s`). `firefox-sync.sh` uses `--ff-only` merges with no fallback, scoped commits via `git commit --only`, and idempotent tag creation via `rev-parse --verify`.

## Networking Best Practices (for Go projects)

When declaring network variables, always use interface types:
- Never use `net.UDPAddr`, `net.IPAddr`, or `net.TCPAddr`. Use `net.Addr` only instead.
- Never use `net.UDPConn`, use `net.PacketConn` instead
- Never use `net.TCPConn`, use `net.Conn` instead
- Never use `net.UDPListener` or `net.TCPListener`, use `net.Listener` instead
- Never use a type switch or type assertion to convert from an interface type to a concrete type. Use the interface methods instead.

This approach enhances testability and flexibility when working with different network implementations or mocks.
