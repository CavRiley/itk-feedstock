# This file presets TRY_RUN() results for cross-compilation targeting osx-64
# (x86_64 macOS) built on osx-arm64 runners. It was derived from
# TryRunResults-osx-arm64.cmake: every probe below is OS-level (macOS) and thus
# identical, except the SSE2 probes. CMake still *compiles* each probe live in
# cross mode and only skips the run, so the seeded value is the run exit code.
# The SSE2 intrinsics compile on x86_64 (unlike arm), so a seeded exit code of 0
# resolves to "supported" here while it resolves to "not supported" on arm.
#
# To regenerate: cross-compile-configure ITK for osx-64; cmake produces this
# file automatically. See https://cmake.org/cmake/help/latest/variable/CMAKE_CROSSCOMPILING.html


# DOUBLE_CONVERSION_CORRECT_DOUBLE_OPERATIONS
#    1 means double operations are correct (no workaround needed). x86_64 macOS
#    uses SSE2 (not x87), so there is no excess-precision rounding problem.
set( DOUBLE_CONVERSION_CORRECT_DOUBLE_OPERATIONS
     1
     CACHE STRING "Result from TRY_RUN" FORCE)

# VCL_HAS_LFS
#    Large file support. macOS off_t is always 64-bit, same as osx-arm64.
set( VCL_HAS_LFS
     1
     CACHE STRING "Result from TRY_RUN" FORCE)

# VXL_HAS_SSE2_HARDWARE_SUPPORT
#    Run exit code 0; the probe compiles on x86_64, so this resolves to
#    SSE2 supported (x86_64 has SSE2 as a baseline instruction set).
set( VXL_HAS_SSE2_HARDWARE_SUPPORT
     0
     CACHE STRING "Result from TRY_RUN" FORCE)

# VXL_SSE2_HARDWARE_SUPPORT_POSSIBLE
#    Run exit code 0; compiles with -msse2 on x86_64 -> SSE2 possible.
set( VXL_SSE2_HARDWARE_SUPPORT_POSSIBLE
     0
     CACHE STRING "Result from TRY_RUN" FORCE)

set( _libcxx_run_result
     0
     CACHE STRING "Results from TRY_RUN" FORCE)
set(_libcxx_run_result__TRYRUN_OUTPUT
     "nothing"
     CACHE STRING "Results from TRY_RUN" FORCE)

# QNANHIBIT_VALUE
#    1 means the high bit of the quiet-NaN mantissa is set (IEEE 754; true on
#    x86_64, same as osx-arm64).
set( QNANHIBIT_VALUE
     1
     CACHE STRING "Result from TRY_RUN" FORCE)
set( QNANHIBIT_VALUE__TRYRUN_OUTPUT
     ""
     CACHE STRING "Result from TRY_RUN" FORCE)

# HAVE_CLOCK_GETTIME_RUN
#    0 means clock_gettime() is available and works (macOS 10.12+).
set( HAVE_CLOCK_GETTIME_RUN
     0
     CACHE STRING "Result from TRY_RUN" FORCE)
