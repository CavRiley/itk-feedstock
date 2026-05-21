set BUILD_DIR=%SRC_DIR%\bld
for /f "tokens=1,2 delims=." %%a in ("%PKG_VERSION%") do set ITK_VERSION_MM=%%a.%%b
set ITK_CMAKE_DEST=%LIBRARY_PREFIX%\lib\cmake\ITK-%ITK_VERSION_MM%
set UTIL_DEST=%LIBRARY_PREFIX%\lib\cmake\Utilities
set WRAP_CMAKE_DEST=%LIBRARY_PREFIX%\lib\cmake\Wrapping
set TYPEDEFS_DEST=%ITK_CMAKE_DEST%\Wrapping\Typedefs
set INCLUDE_DEST=%LIBRARY_PREFIX%\include\ITK-%ITK_VERSION_MM%

REM ---------------------------------------------------------------------------
REM C++ development content (headers + module-build CMake infrastructure)
REM ---------------------------------------------------------------------------
cmake -DCOMPONENT=Development -P %BUILD_DIR%\cmake_install.cmake
cmake -DCOMPONENT=DebugDevel -P %BUILD_DIR%\cmake_install.cmake
cmake -DCOMPONENT=cpplibraries  -P %BUILD_DIR%\cmake_install.cmake
cmake -DCOMPONENT=Headers -P %BUILD_DIR%\cmake_install.cmake

if not exist "%ITK_CMAKE_DEST%" mkdir "%ITK_CMAKE_DEST%"
REM Ship the whole CMake/ helper set: ITK installs only a subset, but the
REM module-build + wrapping include() chain pulls in many of these by name and
REM the exact set drifts across ITK releases. copy /Y is mandatory under
REM unattended conda-build. The two wildcard patterns are passed as one set.
for %%f in ("%SRC_DIR%\CMake\*.cmake" "%SRC_DIR%\CMake\*.cmake.in") do (
    copy /Y "%%f" "%ITK_CMAKE_DEST%\"
    if errorlevel 1 exit 1
)
REM ITK's module-build helpers (ITKModuleClangFormat / ITKModuleDoxygen /
REM ITKModuleKWStyleTest / ITKModuleHeaderTest) unconditionally include files
REM via %ITK_CMAKE_DIR%\..\Utilities\<subdir>\. Ship those subdirs wholesale.
if not exist "%UTIL_DEST%" mkdir "%UTIL_DEST%"
REM Skip subdirs a given ITK release doesn't have (e.g. 6.0 dropped ClangFormat).
for %%s in (ClangFormat Doxygen KWStyle Maintenance) do (
    if exist "%SRC_DIR%\Utilities\%%s\" (
        xcopy /E /I /Y "%SRC_DIR%\Utilities\%%s" "%UTIL_DEST%\%%s"
        if errorlevel 1 exit 1
    )
)

REM ---------------------------------------------------------------------------
REM Python wrapping infrastructure (Wrapping/ source tree + .wrap files +
REM build-tree Typedefs/) for building Python-wrapped remote modules.
REM ---------------------------------------------------------------------------
if not exist "%WRAP_CMAKE_DEST%" mkdir "%WRAP_CMAKE_DEST%"

copy /Y "%SRC_DIR%\CMake\WrappingConfigCommon.cmake" "%ITK_CMAKE_DEST%\WrappingConfigCommon.cmake"
if errorlevel 1 exit 1
copy /Y "%SRC_DIR%\CMake\ITKSetPython3Vars.cmake" "%ITK_CMAKE_DEST%\ITKSetPython3Vars.cmake"
if errorlevel 1 exit 1

xcopy /E /I /Y "%SRC_DIR%\Wrapping" "%WRAP_CMAKE_DEST%"
if errorlevel 1 exit 1

REM Per-module wrapping/ subdirs (recursive find). `dir /b /s /AD wrapping`
REM is more reliable than `for /d /r ... in (wrapping)` for matching literal
REM directory names.
pushd "%SRC_DIR%\Modules"
setlocal enabledelayedexpansion
for /f "delims=" %%d in ('dir /b /s /AD wrapping 2^>nul') do (
    set "_src=%%d"
    set "_rel=!_src:%SRC_DIR%\=!"
    if not exist "%INCLUDE_DEST%\!_rel!" mkdir "%INCLUDE_DEST%\!_rel!"
    xcopy /E /I /Y "!_src!" "%INCLUDE_DEST%\!_rel!"
)
endlocal
popd

REM Every module's itk-module.cmake. Downstream wheel-build tooling
REM (ITKPythonPackage_BuildWheels.cmake) reads the source-tree layout
REM Modules/<Group>/<Module>/itk-module.cmake to derive ITK_MODULE_<M>_GROUP.
REM Group info is encoded purely by directory structure.
pushd "%SRC_DIR%\Modules"
setlocal enabledelayedexpansion
for /f "delims=" %%f in ('dir /b /s itk-module.cmake 2^>nul') do (
    set "_src=%%f"
    set "_rel=!_src:%SRC_DIR%\=!"
    for %%p in ("!_rel!") do set "_rel_dir=%%~dpp"
    if not exist "%INCLUDE_DEST%\!_rel_dir!" mkdir "%INCLUDE_DEST%\!_rel_dir!"
    copy /Y "!_src!" "%INCLUDE_DEST%\!_rel!"
)
endlocal
popd

REM Build-tree wrapping artifacts (.i, .idx, .mdx, pyBase.i, python/*_ext.i)
REM not installed by upstream ITK. Required by SWIG at consumer build time.
if not exist "%TYPEDEFS_DEST%" mkdir "%TYPEDEFS_DEST%"
xcopy /E /I /Y "%BUILD_DIR%\Wrapping\Typedefs" "%TYPEDEFS_DEST%"

REM Append Eigen3 + module-include hook to WrappingConfigCommon.cmake.
REM See itk-devel_install.sh for the rationale.
set "WRAP_CFG=%ITK_CMAKE_DEST%\WrappingConfigCommon.cmake"
if exist "%WRAP_CFG%" (
    >>"%WRAP_CFG%" echo.
    >>"%WRAP_CFG%" echo # Forward Eigen3 + module includes for the wrapping/castxml pass.
    >>"%WRAP_CFG%" echo if^(TARGET Eigen3::Eigen^)
    >>"%WRAP_CFG%" echo   get_target_property^(_libitk_wrap_eigen_incs Eigen3::Eigen INTERFACE_INCLUDE_DIRECTORIES^)
    >>"%WRAP_CFG%" echo   if^(_libitk_wrap_eigen_incs^)
    >>"%WRAP_CFG%" echo     include_directories^(${_libitk_wrap_eigen_incs}^)
    >>"%WRAP_CFG%" echo   endif^(^)
    >>"%WRAP_CFG%" echo   unset^(_libitk_wrap_eigen_incs^)
    >>"%WRAP_CFG%" echo endif^(^)
    >>"%WRAP_CFG%" echo if^(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/include"^)
    >>"%WRAP_CFG%" echo   include_directories^("${CMAKE_CURRENT_SOURCE_DIR}/include"^)
    >>"%WRAP_CFG%" echo endif^(^)
    >>"%WRAP_CFG%" echo include_directories^("${CMAKE_CURRENT_BINARY_DIR}/include"^)
)
