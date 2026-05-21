#!/bin/bash
set -euo pipefail

BUILD_DIR=${SRC_DIR}/build
ITK_VERSION_MM=$(echo "${PKG_VERSION}" | awk -F. '{print $1"."$2}')
ITK_CMAKE_DEST="${PREFIX}/lib/cmake/ITK-${ITK_VERSION_MM}"
UTIL_DEST="${PREFIX}/lib/cmake/Utilities"
WRAP_CMAKE_DEST="${PREFIX}/lib/cmake/Wrapping"
TYPEDEFS_DEST="${ITK_CMAKE_DEST}/Wrapping/Typedefs"
INCLUDE_DEST="${PREFIX}/include/ITK-${ITK_VERSION_MM}"

# ---------------------------------------------------------------------------
# C++ development content (headers + module-build CMake infrastructure)
# ---------------------------------------------------------------------------
cmake -DCOMPONENT=Development -P "${BUILD_DIR}/cmake_install.cmake"
cmake -DCOMPONENT=Headers -P "${BUILD_DIR}/cmake_install.cmake"

# CMake module-build helpers not installed by upstream ITK's Development /
# Headers components. Required for external (remote-module) projects to
# find_package(ITK) and include(ITKModuleExternal). Include the whole CMake/
# helper set rather than maintain a fragile allowlist that drifts.
mkdir -p "${ITK_CMAKE_DEST}"
for f in "${SRC_DIR}"/CMake/*.cmake "${SRC_DIR}"/CMake/*.cmake.in; do
    [ -e "${f}" ] || continue
    base="$(basename "${f}")"
    # Skip files ITK's Development/Headers install already placed (keep those
    # authoritative).
    [ -e "${ITK_CMAKE_DEST}/${base}" ] || cp "${f}" "${ITK_CMAKE_DEST}/${base}"
done

# ITK's module-build helpers (ITKModuleClangFormat / ITKModuleDoxygen /
# ITKModuleKWStyleTest / ITKModuleHeaderTest) unconditionally include files via
# ${ITK_CMAKE_DIR}/../Utilities/<subdir>/. Include those subdirs so the
# include chain resolves even though a downstream module never runs the tools.
mkdir -p "${UTIL_DEST}"
# Skip subdirs a given ITK release doesn't have (e.g. 6.0 dropped ClangFormat),
# so the same script works across ITK versions. `|| continue` (not `&& cp`)
# keeps `set -e` happy when a subdir is absent.
for sub in ClangFormat Doxygen KWStyle Maintenance; do
    [ -d "${SRC_DIR}/Utilities/${sub}" ] || continue
    cp -R "${SRC_DIR}/Utilities/${sub}" "${UTIL_DEST}/${sub}"
done

# ---------------------------------------------------------------------------
# Python wrapping infrastructure (Wrapping/ source tree + .wrap files +
# build-tree Typedefs/) for building Python-wrapped remote modules.
# ---------------------------------------------------------------------------
mkdir -p "${WRAP_CMAKE_DEST}"

# Wrapping CMake helpers that ITKModuleExternal.cmake includes by name.
cp "${SRC_DIR}/CMake/WrappingConfigCommon.cmake" "${ITK_CMAKE_DEST}/WrappingConfigCommon.cmake"
cp "${SRC_DIR}/CMake/ITKSetPython3Vars.cmake"     "${ITK_CMAKE_DEST}/ITKSetPython3Vars.cmake"

# Full Wrapping/ source tree. ITKModuleExternal.cmake sets
# WRAP_ITK_CMAKE_DIR = ${ITK_CMAKE_DIR}/../Wrapping, which resolves to this
# location given ITK_CMAKE_DIR = ${ITK_CMAKE_DEST}.
cp -R "${SRC_DIR}/Wrapping/." "${WRAP_CMAKE_DEST}/"

# macOS only: castxml's bundled Clang treats libc++'s aligned `operator delete`
# (operator delete(void*, size_t, align_val_t)) as a "non-usual" deallocation
# function when parsing libc++ <new> against the system macOS SDK — the SDK's
# aligned-allocation availability gating differs from the conda SDK ITK itself
# wraps against. This breaks wrapping of any remote module. Disable aligned/
# sized deallocation for the castxml PARSE only, so libc++ falls back to the
# plain usual operator delete. castxml only emits the API XML for SWIG, so this
# has no codegen/ABI effect. Scoped to APPLE: Linux has no such OS-version
# gating (no fix needed) and Windows uses the --castxml-cc-msvc path (untouched).
ALSM="${WRAP_CMAKE_DEST}/macro_files/itk_auto_load_submodules.cmake"
if [ -f "${ALSM}" ]; then
    awk '
    { print }
    index($0, "set(_castxml_cc_flags ${CMAKE_CXX_FLAGS})") {
      print "  if(APPLE)"
      print "    string(APPEND _castxml_cc_flags \" -fno-aligned-allocation -fno-sized-deallocation\")"
      print "  endif()"
    }
    ' "${ALSM}" > "${ALSM}.tmp" && mv "${ALSM}.tmp" "${ALSM}"
fi

# Per-module wrapping/ subdirs (Modules/<Group>/<Module>/wrapping/) so that
# external builds re-using ITK module sources can resolve .wrap dependencies.
cd "${SRC_DIR}"
while IFS= read -r wrap_src; do
    rel="${wrap_src#./}"           # e.g. Modules/Core/Common/wrapping
    dest="${INCLUDE_DEST}/${rel}"
    mkdir -p "${dest}"
    cp -R "${wrap_src}/." "${dest}/"
done < <(find Modules -type d -name wrapping)

# Every module's itk-module.cmake. Downstream wheel-build tooling derives
# ITK_MODULE_<M>_GROUP from the directory layout, so the file location matters.
# Include all of them (including ThirdParty) since the dependency walk reads GROUP
# for non-wrapped deps too.
while IFS= read -r module_cmake; do
    rel="${module_cmake#./}"       # e.g. Modules/Core/Common/itk-module.cmake
    dest_dir="${INCLUDE_DEST}/$(dirname "${rel}")"
    mkdir -p "${dest_dir}"
    cp "${module_cmake}" "${dest_dir}/itk-module.cmake"
done < <(find Modules -name itk-module.cmake)

# Build-tree wrapping artifacts (.i, .idx, .mdx, pyBase.i, python/*_ext.i) that
# upstream ITK doesn't install. Required at ${ITK_CMAKE_DIR}/Wrapping/Typedefs/
# for consumer SWIG runs to resolve %import "pyBase.i" and .mdx dependencies.
mkdir -p "${TYPEDEFS_DEST}"
cp -R "${BUILD_DIR}/Wrapping/Typedefs/." "${TYPEDEFS_DEST}/"

# Append Eigen3 + module-include hook to the installed WrappingConfigCommon.cmake.
WRAP_CFG="${ITK_CMAKE_DEST}/WrappingConfigCommon.cmake"
if [[ -f "${WRAP_CFG}" ]]; then
    cat >> "${WRAP_CFG}" <<'EOF'

# Added by itk-feedstock: castxml's include set comes from
# get_directory_property(... INCLUDE_DIRECTORIES), which doesn't pick up
# target-only includes (Eigen3::Eigen) or the consumer module's own include/
# dirs. Push them onto the directory property here.
if(TARGET Eigen3::Eigen)
  get_target_property(_libitk_wrap_eigen_incs
    Eigen3::Eigen INTERFACE_INCLUDE_DIRECTORIES)
  if(_libitk_wrap_eigen_incs)
    include_directories(${_libitk_wrap_eigen_incs})
  endif()
  unset(_libitk_wrap_eigen_incs)
endif()
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/include")
  include_directories("${CMAKE_CURRENT_SOURCE_DIR}/include")
endif()
# Binary include/ for generate_export_header outputs; the dir is created
# during the build before castxml runs.
include_directories("${CMAKE_CURRENT_BINARY_DIR}/include")
EOF
fi
