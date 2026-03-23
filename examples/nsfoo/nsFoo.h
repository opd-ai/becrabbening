#pragma once

// nsFoo.h — after Phase 4 switchover.
//
// The implementation now lives in rust/nsfoo/src/lib.rs.
// This file is kept as a thin redirect so that all existing #include
// directives continue to work without modification.
//
// See 05-PHASE-4-SWITCHOVER.md for the switchover procedure.

#include "nsfoo_shim.h"
