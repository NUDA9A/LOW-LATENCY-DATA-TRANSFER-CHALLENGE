CMAKE_MINIMUM_REQUIRED(VERSION 3.16)

project(LOW_LATENCY_DATA_TRANSFER_CHALLENGE VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(cmake/ProjectWarnings.cmake)

add_library(lldt_sender_core STATIC src/config.cpp src/sender_shm_reader.cpp src/raw_data_packet_builder.cpp)

target_include_directories(lldt_sender_core PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include/>)

lldt_enable_project_warnings(lldt_sender_core)

add_executable(lldt_sender src/sender_main.cpp)

lldt_enable_project_warnings(lldt_sender)

target_link_libraries(lldt_sender PRIVATE lldt_sender_core)

add_library(lldt_harness_headers INTERFACE)

target_include_directories(lldt_harness_headers INTERFACE $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/harness/include/>)

target_link_libraries(lldt_sender_core PUBLIC lldt_harness_headers)
target_link_libraries(lldt_sender PRIVATE lldt_harness_headers)

include(CTest)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()