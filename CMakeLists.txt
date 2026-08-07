CMAKE_MINIMUM_REQUIRED(VERSION 3.16)

project(LOW_LATENCY_DATA_TRANSFER_CHALLENGE VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(cmake/ProjectWarnings.cmake)

add_executable(lldt_sender_kernel src/kernel/sender_main.cpp)
add_executable(lldt_receiver_kernel src/kernel/receiver_main.cpp)

lldt_enable_project_warnings(lldt_sender_kernel)
lldt_enable_project_warnings(lldt_receiver_kernel)

add_library(lldt_harness_headers INTERFACE)

target_include_directories(lldt_harness_headers INTERFACE $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/harness/include/>)

target_link_libraries(lldt_sender_kernel PRIVATE lldt_harness_headers)
target_link_libraries(lldt_receiver_kernel PRIVATE lldt_harness_headers)

include(CTest)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()