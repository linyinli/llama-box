set(CMAKE_CROSSCOMPILING TRUE)

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR ARM64)
set(CMAKE_GENERATOR_PLATFORM ARM64 CACHE INTERNAL "")

set(target arm64-pc-windows-msvc)
set(CMAKE_C_COMPILER_TARGET ${target})
set(CMAKE_CXX_COMPILER_TARGET ${target})
