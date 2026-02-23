cmake_minimum_required(VERSION 3.15)
project(lab1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_BUILD_TYPE Release)

# Google Benchmark
include(FetchContent)
set(BENCHMARK_DOWNLOAD_DEPENDENCIES ON)
FetchContent_Declare(
    benchmark
    GIT_REPOSITORY https://github.com/google/benchmark.git
    GIT_TAG v1.9.4
)
FetchContent_MakeAvailable(benchmark)

# Sources
file(GLOB_RECURSE SOURCES "src/*.cpp")
add_executable(lab1 ${SOURCES})

target_include_directories(lab1 PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${CMAKE_SOURCE_DIR}/src/benchmark
)

# Link
find_package(Threads REQUIRED)
target_link_libraries(lab1 PRIVATE
    benchmark::benchmark
    Threads::Threads
)

# Compile flags
target_compile_options(lab1 PRIVATE -O3 -g -fno-omit-frame-pointer)

set_target_properties(lab1 PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
