cmake_minimum_required(VERSION 3.20)
project(keysight_synth LANGUAGES CXX)

if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()

include(FetchContent)
FetchContent_Declare(godot_cpp
    URL https://codeload.github.com/godotengine/godot-cpp/tar.gz/refs/tags/godot-4.4-stable
    URL_HASH SHA256=472c6e7f3f7a9d576f21e2c57d16390b46d238f98e69a47d84730e943f5c5506)
set(GODOTCPP_BUILD_PROFILE "${CMAKE_CURRENT_SOURCE_DIR}/profile.json" CACHE FILEPATH "")
find_file(TSF_HEADER tsf.h PATHS "${CMAKE_CURRENT_BINARY_DIR}" NO_DEFAULT_PATH)
if(NOT TSF_HEADER)
    set(TSF_HEADER "${CMAKE_CURRENT_BINARY_DIR}/tsf.h")
    file(DOWNLOAD
        https://raw.githubusercontent.com/schellingb/TinySoundFont/a3621a19c6504885cd9583e6e26c35bc954fc8ec/tsf.h
        "${TSF_HEADER}.download" TLS_VERIFY ON
        EXPECTED_HASH SHA256=70d55963c98f60ebb81518eaa1f25d46888d5180eb5f5289fd6b74ffc177d197)
    file(RENAME "${TSF_HEADER}.download" "${TSF_HEADER}")
endif()
file(SHA256 "${TSF_HEADER}" TSF_HASH)
if(NOT TSF_HASH STREQUAL "70d55963c98f60ebb81518eaa1f25d46888d5180eb5f5289fd6b74ffc177d197")
    message(FATAL_ERROR "Unexpected TinySoundFont checksum")
endif()
FetchContent_MakeAvailable(godot_cpp)

add_library(keysight_synth SHARED synth.cpp)
target_compile_features(keysight_synth PRIVATE cxx_std_17)
target_include_directories(keysight_synth PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
target_link_libraries(keysight_synth PRIVATE godot-cpp::template_release)
target_link_options(keysight_synth PRIVATE -static-libgcc -static-libstdc++ "LINKER:--exclude-libs,ALL")
set_target_properties(keysight_synth PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../addons/keysight_synth/bin"
    OUTPUT_NAME "keysight_synth.${KEYSIGHT_ARCH}")
