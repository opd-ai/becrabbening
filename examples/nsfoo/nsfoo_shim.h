#pragma once

// Layer 3: C++ shim for nsFoo.
//
// This header presents the EXACT same public API as the original nsFoo.h,
// but delegates all calls to the Rust-backed C FFI layer.
//
// See 04-PHASE-3-CPP-SHIM.md for the full explanation.

extern "C" {
#include "nsfoo_ffi.h"
}

#include <cassert>

/**
 * C++ wrapper for nsFoo. Delegates to the Rust implementation via the C FFI.
 *
 * This class has the same public interface as the original nsFoo, so all
 * existing callers compile without modification.
 */
class nsFoo {
public:
    /// Construct nsFoo with the given initial value.
    /// Aborts the process if the underlying Rust allocation panics.
    explicit nsFoo(int initial)
        : handle_(fox_nsfoo_new(initial)) {
        // fox_nsfoo_new only returns null when the Rust constructor panics.
        // Treat that as an unrecoverable programmer/environment error.
        assert(handle_ != nullptr && "fox_nsfoo_new returned null");
    }

    /// Destructor — releases the Rust-owned resource.
    ~nsFoo() {
        fox_nsfoo_free(handle_);
    }

    // Non-copyable: Rust owns the resource; there is no clone operation at
    // the C FFI boundary.
    nsFoo(const nsFoo&) = delete;
    nsFoo& operator=(const nsFoo&) = delete;

    /// Move constructor: transfer ownership of the opaque handle.
    nsFoo(nsFoo&& other) noexcept
        : handle_(other.handle_) {
        other.handle_ = nullptr;
    }

    /// Move assignment: transfer ownership, freeing any previously held resource.
    nsFoo& operator=(nsFoo&& other) noexcept {
        if (this != &other) {
            fox_nsfoo_free(handle_);
            handle_ = other.handle_;
            other.handle_ = nullptr;
        }
        return *this;
    }

    /// Return value + x (wrapping addition). Delegates to fox_nsfoo_bar().
    int Bar(int x) const {
        return fox_nsfoo_bar(handle_, x);
    }

    /// Set the stored value. Delegates to fox_nsfoo_set_value().
    void SetValue(int v) {
        fox_nsfoo_set_value(handle_, v);
    }

private:
    FoxNsFoo* handle_;
};
