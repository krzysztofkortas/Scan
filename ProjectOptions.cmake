include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(Scan_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(Scan_setup_options)
  option(Scan_ENABLE_HARDENING "Enable hardening" ON)
  option(Scan_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    Scan_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    Scan_ENABLE_HARDENING
    OFF)

  Scan_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR Scan_PACKAGING_MAINTAINER_MODE)
    option(Scan_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(Scan_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(Scan_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(Scan_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(Scan_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(Scan_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(Scan_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(Scan_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(Scan_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(Scan_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(Scan_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(Scan_ENABLE_PCH "Enable precompiled headers" OFF)
    option(Scan_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(Scan_ENABLE_IPO "Enable IPO/LTO" ON)
    option(Scan_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(Scan_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(Scan_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(Scan_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(Scan_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(Scan_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(Scan_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(Scan_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(Scan_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(Scan_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(Scan_ENABLE_PCH "Enable precompiled headers" OFF)
    option(Scan_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      Scan_ENABLE_IPO
      Scan_WARNINGS_AS_ERRORS
      Scan_ENABLE_USER_LINKER
      Scan_ENABLE_SANITIZER_ADDRESS
      Scan_ENABLE_SANITIZER_LEAK
      Scan_ENABLE_SANITIZER_UNDEFINED
      Scan_ENABLE_SANITIZER_THREAD
      Scan_ENABLE_SANITIZER_MEMORY
      Scan_ENABLE_UNITY_BUILD
      Scan_ENABLE_CLANG_TIDY
      Scan_ENABLE_CPPCHECK
      Scan_ENABLE_COVERAGE
      Scan_ENABLE_PCH
      Scan_ENABLE_CACHE)
  endif()

  Scan_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (Scan_ENABLE_SANITIZER_ADDRESS OR Scan_ENABLE_SANITIZER_THREAD OR Scan_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(Scan_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(Scan_global_options)
  if(Scan_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    Scan_enable_ipo()
  endif()

  Scan_supports_sanitizers()

  if(Scan_ENABLE_HARDENING AND Scan_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR Scan_ENABLE_SANITIZER_UNDEFINED
       OR Scan_ENABLE_SANITIZER_ADDRESS
       OR Scan_ENABLE_SANITIZER_THREAD
       OR Scan_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${Scan_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${Scan_ENABLE_SANITIZER_UNDEFINED}")
    Scan_enable_hardening(Scan_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(Scan_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(Scan_warnings INTERFACE)
  add_library(Scan_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  Scan_set_project_warnings(
    Scan_warnings
    ${Scan_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(Scan_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(Scan_options)
  endif()

  include(cmake/Sanitizers.cmake)
  Scan_enable_sanitizers(
    Scan_options
    ${Scan_ENABLE_SANITIZER_ADDRESS}
    ${Scan_ENABLE_SANITIZER_LEAK}
    ${Scan_ENABLE_SANITIZER_UNDEFINED}
    ${Scan_ENABLE_SANITIZER_THREAD}
    ${Scan_ENABLE_SANITIZER_MEMORY})

  set_target_properties(Scan_options PROPERTIES UNITY_BUILD ${Scan_ENABLE_UNITY_BUILD})

  if(Scan_ENABLE_PCH)
    target_precompile_headers(
      Scan_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(Scan_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    Scan_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(Scan_ENABLE_CLANG_TIDY)
    Scan_enable_clang_tidy(Scan_options ${Scan_WARNINGS_AS_ERRORS})
  endif()

  if(Scan_ENABLE_CPPCHECK)
    Scan_enable_cppcheck(${Scan_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(Scan_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    Scan_enable_coverage(Scan_options)
  endif()

  if(Scan_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(Scan_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(Scan_ENABLE_HARDENING AND NOT Scan_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR Scan_ENABLE_SANITIZER_UNDEFINED
       OR Scan_ENABLE_SANITIZER_ADDRESS
       OR Scan_ENABLE_SANITIZER_THREAD
       OR Scan_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    Scan_enable_hardening(Scan_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
