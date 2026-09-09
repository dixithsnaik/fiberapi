#----------------------------------------------------------------
# Generated CMake target import file for configuration "Debug".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "FiberAPI::picohttpparser" for configuration "Debug"
set_property(TARGET FiberAPI::picohttpparser APPEND PROPERTY IMPORTED_CONFIGURATIONS DEBUG)
set_target_properties(FiberAPI::picohttpparser PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_DEBUG "C"
  IMPORTED_LOCATION_DEBUG "${_IMPORT_PREFIX}/lib/libpicohttpparser.a"
  )

list(APPEND _cmake_import_check_targets FiberAPI::picohttpparser )
list(APPEND _cmake_import_check_files_for_FiberAPI::picohttpparser "${_IMPORT_PREFIX}/lib/libpicohttpparser.a" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
