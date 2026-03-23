# TASK: Build a C++ shim wrapper that presents the exact same API as the original header, delegating all calls to the C FFI layer.

## Execution Mode
**Autonomous action** — create the C++ shim header, verify it compiles and matches the original API, then stop.

This prompt operates on a **Firefox source tree**. The target file-pair name is provided above.

## Context
Read the becrabbening documentation:
- [04-PHASE-3-CPP-SHIM.md](./04-PHASE-3-CPP-SHIM.md) — detailed Phase 3 instructions
- [examples/nsfoo/nsfoo_shim.h](./examples/nsfoo/nsfoo_shim.h) — complete worked example
- [00-OVERVIEW.md](./00-OVERVIEW.md) — three-layer sandwich architecture

## Workflow

### Step 1: Create `{name}_shim.h`

Start with the include guard and C FFI include:

```cpp
#pragma once

extern "C" {
#include "{name}_ffi.h"
}
```

### Step 2: Re-create Every Class and Free Function

For every class, struct, enum, free function, constant, and type alias from the **original** `{name}.h`, create an equivalent in the shim with **identical signatures**.

The goal: any file currently including `{name}.h` can instead include `{name}_shim.h` and compile without changes.

Each method body should be 1–3 lines delegating to the corresponding `fox_{name}_*()` C function:

```cpp
int Bar(int x) const {
    return fox_{name}_bar(handle_, x);
}
```

### Step 3: Store Opaque Handle

For classes wrapping opaque Rust objects, store a `FoxName*` handle as a private member:

```cpp
class OriginalClass {
public:
    // ... methods ...
private:
    FoxName* handle_;
};
```

### Step 4: Constructor and Destructor

Map constructor to `fox_{name}_new()` and destructor to `fox_{name}_free()`:

```cpp
explicit OriginalClass(int initial)
    : handle_(fox_{name}_new(initial)) {}

~OriginalClass() {
    fox_{name}_free(handle_);
}
```

### Step 5: Delete Copy, Implement Move

```cpp
// Copy: deleted (Rust owns the resource)
OriginalClass(const OriginalClass&) = delete;
OriginalClass& operator=(const OriginalClass&) = delete;

// Move: transfer ownership
OriginalClass(OriginalClass&& other) noexcept : handle_(other.handle_) {
    other.handle_ = nullptr;
}

OriginalClass& operator=(OriginalClass&& other) noexcept {
    if (this != &other) {
        fox_{name}_free(handle_);
        handle_ = other.handle_;
        other.handle_ = nullptr;
    }
    return *this;
}
```

### Step 6: Create `{name}_shim.cpp` if Needed

If any method implementations are non-trivial, create a companion `.cpp` file. In most cases, all delegation is simple enough to inline in the header.

### Step 7: Verify Compilation

```bash
g++ -xc++ -std=c++17 -fsyntax-only {name}_shim.h
```

Must succeed with no errors and no warnings.

## API Fidelity Checklist

Before completing, verify:
- [ ] Same class names as the original header
- [ ] Same method names
- [ ] Same parameter types (including `const` and reference qualifiers)
- [ ] Same return types
- [ ] Same const-correctness on methods
- [ ] No new public methods that were not in the original API
- [ ] No removed public methods

## Type Conversion Patterns

| C++ Type | C FFI Type | Conversion |
|----------|-----------|------------|
| `std::string` | `const char*` | `.c_str()` in, copy on out |
| `std::vector<T>` | `T*` + `size_t` len | `.data()` + `.size()` |
| `bool` | `int` | `!! value` or cast |
| `std::unique_ptr<T>` | opaque `FoxT*` | `handle_` member |

## Output Artifacts
- [ ] `{name}_shim.h` created and compiling
- [ ] Optionally, `{name}_shim.cpp` if non-inline implementations needed
- [ ] Shim exposes the exact same public API as the original `{name}.h`
- [ ] All methods delegate to `fox_{name}_*()` C functions

## What NOT to Do
- Do **not** change the public API surface.
- Do **not** add new public methods not in the original.
- Do **not** modify existing C++ files. This phase is still additive.
