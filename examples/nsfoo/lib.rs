//! Becrabbening worked example — Layer 1: Rust implementation for `nsFoo`.
//!
//! This file demonstrates the Rust implementation layer of the three-layer
//! sandwich architecture described in [`02-PHASE-1-RUST.md`][phase1].
//!
//! Layout:
//! - `NsFoo` — the idiomatic Rust struct (no FFI concerns)
//! - `FoxNsFoo` — opaque wrapper used as the C-facing handle
//! - `fox_nsfoo_*` — `extern "C"` functions exported to the C FFI layer
//!
//! [phase1]: ../../02-PHASE-1-RUST.md

use std::os::raw::c_int;
use std::panic::catch_unwind;

// ---------------------------------------------------------------------------
// Rust-native implementation
// ---------------------------------------------------------------------------

/// Idiomatic Rust replacement for `nsFoo`.
pub struct NsFoo {
    value: i32,
}

impl NsFoo {
    /// Create a new `NsFoo` with the given initial value.
    pub fn new(initial: i32) -> Self {
        NsFoo { value: initial }
    }

    /// Return `self.value` wrapping-added to `x`.
    pub fn bar(&self, x: i32) -> i32 {
        self.value.wrapping_add(x)
    }

    /// Set the stored value.
    pub fn set_value(&mut self, v: i32) {
        self.value = v;
    }
}

// ---------------------------------------------------------------------------
// Opaque FFI wrapper
// ---------------------------------------------------------------------------

/// Opaque handle used by C/C++ callers.
///
/// cbindgen emits: `typedef struct FoxNsFoo FoxNsFoo;`
///
/// The inner `NsFoo` is never exposed directly across the ABI boundary.
pub struct FoxNsFoo(NsFoo);

// ---------------------------------------------------------------------------
// extern "C" exports — Layer 1 → Layer 2 interface
// ---------------------------------------------------------------------------

/// Allocate a new `FoxNsFoo` on the heap and return an owning pointer.
///
/// The caller is responsible for calling [`fox_nsfoo_free`] exactly once.
/// Returns a null pointer only if the constructor panics; OOM aborts the process.
#[no_mangle]
pub extern "C" fn fox_nsfoo_new(initial: c_int) -> *mut FoxNsFoo {
    match catch_unwind(|| Box::into_raw(Box::new(FoxNsFoo(NsFoo::new(initial as i32))))) {
        Ok(ptr) => ptr,
        Err(_) => std::ptr::null_mut(),
    }
}

/// Free a `FoxNsFoo` previously returned by [`fox_nsfoo_new`].
///
/// Passing a null pointer is safe and has no effect.
/// Passing any other invalid pointer is undefined behavior.
#[no_mangle]
pub extern "C" fn fox_nsfoo_free(ptr: *mut FoxNsFoo) {
    if ptr.is_null() {
        return;
    }
    let _ = catch_unwind(|| {
        // SAFETY: ptr was created by fox_nsfoo_new and has not been freed.
        let _ = unsafe { Box::from_raw(ptr) };
    });
}

/// Invoke `NsFoo::bar` and return the result.
///
/// # Safety
/// `ptr` must be a non-null pointer previously returned by [`fox_nsfoo_new`]
/// that has not yet been freed. Passing null aborts the process.
#[no_mangle]
pub extern "C" fn fox_nsfoo_bar(ptr: *const FoxNsFoo, x: c_int) -> c_int {
    if ptr.is_null() {
        std::process::abort();
    }
    match catch_unwind(|| {
        // SAFETY: ptr is non-null and valid for the lifetime of this call.
        let obj = unsafe { &(*ptr).0 };
        obj.bar(x as i32) as c_int
    }) {
        Ok(v) => v,
        Err(_) => std::process::abort(),
    }
}

/// Invoke `NsFoo::set_value`.
///
/// # Safety
/// `ptr` must be a non-null pointer previously returned by [`fox_nsfoo_new`]
/// that has not yet been freed. Passing null aborts the process.
#[no_mangle]
pub extern "C" fn fox_nsfoo_set_value(ptr: *mut FoxNsFoo, v: c_int) {
    if ptr.is_null() {
        std::process::abort();
    }
    let _ = catch_unwind(|| {
        // SAFETY: ptr is non-null and valid for the lifetime of this call.
        let obj = unsafe { &mut (*ptr).0 };
        obj.set_value(v as i32);
    });
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bar_wrapping_add() {
        let foo = NsFoo::new(10);
        assert_eq!(foo.bar(5), 15);
    }

    #[test]
    fn test_bar_wrapping_overflow() {
        let foo = NsFoo::new(i32::MAX);
        assert_eq!(foo.bar(1), i32::MIN); // wrapping behavior
    }

    #[test]
    fn test_set_value() {
        let mut foo = NsFoo::new(0);
        foo.set_value(42);
        assert_eq!(foo.bar(0), 42);
    }

    #[test]
    fn test_ffi_new_free() {
        let ptr = fox_nsfoo_new(7);
        assert!(!ptr.is_null());
        fox_nsfoo_free(ptr);
    }

    #[test]
    fn test_ffi_bar() {
        let ptr = fox_nsfoo_new(3);
        assert_eq!(fox_nsfoo_bar(ptr, 4), 7);
        fox_nsfoo_free(ptr);
    }

    #[test]
    fn test_ffi_set_value() {
        let ptr = fox_nsfoo_new(0);
        fox_nsfoo_set_value(ptr, 99);
        assert_eq!(fox_nsfoo_bar(ptr, 1), 100);
        fox_nsfoo_free(ptr);
    }

    #[test]
    fn test_ffi_null_free() {
        // Passing NULL to free is always safe.
        fox_nsfoo_free(std::ptr::null_mut());
    }
}
