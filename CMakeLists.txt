CMAKE_MINIMUM_REQUIRED(VERSION 3.16)

project(LOW_LATENCY_DATA_TRANSFER_CHALLENGE VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(LLDT_MESSAGE_PROFILE "raw" CACHE STRING "LLDT message profile (raw/compact)")

include(cmake/ProjectWarnings.cmake)
include(cmake/DPDK.cmake)

add_library(lldt_harness_headers INTERFACE)

if("${LLDT_MESSAGE_PROFILE}" STREQUAL "compact")
    target_compile_definitions(lldt_harness_headers INTERFACE LLDT_MESSAGE_PROFILE_COMPACT=1)
elseif("${LLDT_MESSAGE_PROFILE}" STREQUAL "raw")
else()
    message(FATAL_ERROR "Invalid LLDT_MESSAGE_PROFILE value: '${LLDT_MESSAGE_PROFILE}'")
endif()

target_include_directories(lldt_harness_headers INTERFACE $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/harness/include/>)

add_library(lldt_common STATIC src/config.cpp src/dpdk/ena_port_info.cpp)

target_include_directories(lldt_common PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include/>)

lldt_enable_project_warnings(lldt_common)

target_link_libraries(lldt_common PUBLIC DPDK::DPDK)

add_executable(lldt_sender
        src/sender_main.cpp
        src/sender_shm_reader.cpp
        src/raw_data_packet_builder.cpp
        src/dpdk/ena_tx_port.cpp
        src/dpdk/data_packet_materializer.cpp
)
add_executable(lldt_receiver
        src/receiver_main.cpp
        src/dpdk/ena_rx_port.cpp
        src/dpdk/ingress_packet_parser.cpp
)

lldt_enable_project_warnings(lldt_sender)
lldt_enable_project_warnings(lldt_receiver)

target_link_libraries(lldt_sender PRIVATE lldt_common lldt_harness_headers DPDK::DPDK)
target_link_libraries(lldt_receiver PRIVATE lldt_common lldt_harness_headers DPDK::DPDK)

include(CTest)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()