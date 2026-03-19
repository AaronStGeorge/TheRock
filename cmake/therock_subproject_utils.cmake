# Copyright Advanced Micro Devices, Inc.
# SPDX-License-Identifier: MIT

# Recursively gets all build system targets defined in a directory and all of
# its subdirectories.
function(therock_get_all_targets var dir)
  get_property(targets DIRECTORY "${dir}" PROPERTY BUILDSYSTEM_TARGETS)
  list(APPEND ${var} ${targets})
  get_property(subdirs DIRECTORY "${dir}" PROPERTY SUBDIRECTORIES)
  foreach(subdir ${subdirs})
    therock_get_all_targets("${var}" "${subdir}")
  endforeach()
  set(${var} "${${var}}" PARENT_SCOPE)
endfunction()


# Sets a list of relative INSTALL_RPATH values on a target. This is a no-op
# outside of Posix systems.
# Args:
# TARGETS: Targets to modify INSTALL_RPATH of.
# PATHS: Origin-relative paths to set.
function(therock_set_install_rpath)
  cmake_parse_arguments(
    PARSE_ARGV 0 ARG
    ""
    ""
    "TARGETS;PATHS"
  )
  if(WIN32)
    return()
  endif()

  set(_rpath)
  foreach(path ${ARG_PATHS})
    if("${path}" STREQUAL ".")
      set(path_suffix "")
    else()
      set(path_suffix "/${path}")
    endif()
    if(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
      list(APPEND _rpath "@loader_path${path_suffix}")
    else()
      list(APPEND _rpath "$ORIGIN${path_suffix}")
    endif()
  endforeach()
  message(STATUS "Set RPATH ${_rpath} on ${ARG_TARGETS}")
  set_target_properties(${ARG_TARGETS} PROPERTIES INSTALL_RPATH "${_rpath}")
endfunction()


# Replaces a library linked with `-l` with a CMake target.
# Args:
# OLD_LIBRARY: Deprecated library linked with `-l`
# NEW_TARGET: New target library
function(therock_patch_linked_lib)
  cmake_parse_arguments(
    PARSE_ARGV 0 ARG
    ""
    ""
    "OLD_LIBRARY;NEW_TARGET"
  )
  therock_get_all_targets(all_targets "${CMAKE_CURRENT_SOURCE_DIR}")
  message(STATUS "Patching targets: ${all_targets}")
  foreach(target ${all_targets})
    get_target_property(link_libs "${target}" LINK_LIBRARIES)
    if("-l${ARG_OLD_LIBRARY}" IN_LIST link_libs)
      list(REMOVE_ITEM link_libs "-l${ARG_OLD_LIBRARY}")
      list(APPEND link_libs "${ARG_NEW_TARGET}")
      set_target_properties("${target}" PROPERTIES LINK_LIBRARIES "${link_libs}")
      message(WARNING "target ${target} depends on deprecated -l${ARG_OLD_LIBRARY}. Redirecting: ${link_libs}")
    endif()
  endforeach()
endfunction()


# Registers a hipDNN engine plugin for integration test discovery. Each provider
# calls this from its post-hook; the marker file is installed into the
# provider's stage directory then installed as part of that provider's test
# artifact. The hipdnn_integration_tests  project references the combined
# manifest when double checking that the expected plugins actually loaded.
#
# PLUGIN_NAME should be the C API plugin name (returned from
# hipdnnGetEngineInfo_ext, or hipdnnPluginGetName on each plugin).
#
# The provider's artifact descriptor (e.g. artifact-fusilliprovider.toml) must
# include the marker file in its test component for integration test discovery:
#   [components.test."<stage-path>"]
#   include = [
#     ...existing patterns...
#     "bin/hipdnn_integration_tests_test_infra/enabled_plugins/*",
#   ]
function(therock_register_hipdnn_engine_plugin PLUGIN_NAME)
  set(_marker_dir "${CMAKE_CURRENT_BINARY_DIR}/_hipdnn_plugin_markers")
  file(MAKE_DIRECTORY "${_marker_dir}")
  file(WRITE "${_marker_dir}/${PLUGIN_NAME}" "")
  install(FILES "${_marker_dir}/${PLUGIN_NAME}"
          DESTINATION "${CMAKE_INSTALL_BINDIR}/hipdnn_integration_tests_test_infra/enabled_plugins")
endfunction()
