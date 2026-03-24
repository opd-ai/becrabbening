# Phase 3 — C/C++ Shim

**Goal:** Build a C/C++ wrapper that presents the **exact same API** as the original header, delegating all calls to the C FFI layer.

For C++ source files (`.cpp` + `.h`), the shim is a C++ header with class wrappers. For C source files (`.c` + `.h`), the shim is a pure C header with function-level wrappers.

Previous: [03-PHASE-2-C-FFI.md](./03-PHASE-2-C-FFI.md) — C FFI header.
Next: [05-PHASE-4-SWITCHOVER.md](./05-PHASE-4-SWITCHOVER.md) — Switchover.

---

## Step-by-Step Instructions (C++ Source Files)

### Step 1 — Create `{name}_shim.h`

Create the C++ shim header file. Start with the include guard and the C FFI include:

```cpp
#pragma once

extern "C" {
#include "{name}_ffi.h"
}
```

See [examples/nsfoo/nsfoo_shim.h](./examples/nsfoo/nsfoo_shim.h) for a complete example.

### Step 2 — Include the C FFI header

Always wrap the C FFI include in `extern "C" {}` to prevent C++ name mangling:

```cpp
extern "C" {
#include "{name}_ffi.h"
}
```

### Step 3 — Re-create every class and free function

For every class, struct, enum, free function, constant, and type alias from the **original** `.h` file, create an equivalent in the shim with **identical signatures**. The goal is that any file currently including `{name}.h` can instead include `{name}_shim.h` and compile without changes.

Each method body should be 1–3 lines delegating to the corresponding `fox_{name}_*()` C function:

```cpp
int Bar(int x) const {
    return fox_{name}_bar(handle_, x);
}
```

### Step 4 — For classes wrapping opaque Rust objects

Store a `FoxName*` handle as a private member:

```cpp
class OriginalClass {
public:
    // ... methods ...
private:
    FoxName* handle_;
};
```

### Step 5 — Constructor and destructor

Map the constructor to `fox_{name}_new()` and the destructor to `fox_{name}_free()`:

```cpp
explicit OriginalClass(int initial)
    : handle_(fox_{name}_new(initial)) {}

~OriginalClass() {
    fox_{name}_free(handle_);
}
```

### Step 6 — Delete copy constructor and copy assignment

Rust owns the resource behind the opaque pointer. Copying is not safe without a Rust-side clone operation:

```cpp
OriginalClass(const OriginalClass&) = delete;
OriginalClass& operator=(const OriginalClass&) = delete;
```

### Step 7 — Implement move constructor and move assignment

Allow ownership transfer by moving the opaque pointer:

```cpp
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

### Step 8 — Create `{name}_shim.cpp` if needed

If any method implementations are non-trivial or cannot be inlined, create a `{name}_shim.cpp` companion file. In most cases, all delegation is simple enough to inline in the header.

### Step 9 — Verify the shim compiles

```bash
g++ -xc++ -std=c++17 -fsyntax-only {name}_shim.h
```

This must succeed with no errors and no warnings.

---

## API Fidelity Checklist

Before proceeding to Phase 4, verify:

- [ ] Same class names as the original header
- [ ] Same method names
- [ ] Same parameter types (including `const` and reference qualifiers)
- [ ] Same return types
- [ ] Same const-correctness on methods
- [ ] Same include guards as the original (if replacing `#pragma once` with traditional guards or vice versa, match the original)
- [ ] No new public methods that were not in the original API
- [ ] No removed public methods

---

## Type Conversion Patterns

When the original C++ API uses types that don't cross the C FFI boundary directly, convert them at the shim layer:

| C++ Type | C FFI Type | Conversion |
|---|---|---|
| `std::string` | `const char*` | `.c_str()` in, copy on out |
| `std::string&` (out) | `char*` buf + `size_t` len | fill buffer |
| `std::vector<T>` | `T*` + `size_t` len | `.data()` + `.size()` |
| `bool` | `int` | `!! value` or cast |
| `std::unique_ptr<T>` | opaque `FoxT*` handle | `handle_` member |
| `nullptr` / null check | null pointer | `if (handle_)` |

---

## What NOT to Do

- **Do not change the public API surface.** The shim must be a drop-in replacement for the original header.
- **Do not add new public methods** that were not in the original.
- **Do not modify existing C/C++ files** — this phase is still additive.

---

## C Source File Variant

When the original source is a `.c` file (not `.cpp`), build a **C shim** instead of a C++ shim. The C shim is a pure C header that wraps FFI calls to match the original C API.

### Step 1 — Create `{name}_shim.h` (C variant)

```c
#pragma once

#include "{name}_ffi.h"
```

No `extern "C"` wrapper is needed — the FFI header is already pure C.

### Step 2 — Re-create every function and type

For every function, struct, enum, constant, and type alias from the original `{name}.h`, create an equivalent in the shim with **identical signatures**. Each function body should delegate to the corresponding `fox_{name}_*()` function:

```c
static inline int {name}_bar(struct {Name}* obj, int x) {
    return fox_{name}_bar(obj, x);
}
```

### Step 3 — Verify the shim compiles as C

```bash
gcc -xc -fsyntax-only {name}_shim.h
```

This must succeed with no errors and no warnings.

---

## Output Artifacts

At the end of Phase 3, you should have:

- [ ] `{name}_shim.h` created and compiling
- [ ] Optionally, `{name}_shim.cpp` if non-inline implementations are needed
- [ ] The shim exposes the exact same public API as the original `{name}.h`
- [ ] All methods delegate to `fox_{name}_*()` C functions

---

## Cross-References

- [03-PHASE-2-C-FFI.md](./03-PHASE-2-C-FFI.md) — previous phase (C FFI header)
- [05-PHASE-4-SWITCHOVER.md](./05-PHASE-4-SWITCHOVER.md) — next phase (switchover)
- [00-OVERVIEW.md](./00-OVERVIEW.md) — architecture overview and three-layer sandwich
- [examples/nsfoo/nsfoo_shim.h](./examples/nsfoo/nsfoo_shim.h) — complete worked example
