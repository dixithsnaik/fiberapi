cmake_minimum_required(VERSION 3.20)
project(notes_api LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
include(CTest)

set(FIBER_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/fiber")
if(NOT EXISTS "${FIBER_ROOT}/include/fiber/server.hpp")
	message(FATAL_ERROR "FiberAPI dependency is missing. Expected fiber/include/fiber/server.hpp")
endif()

add_library(FiberAPI::FiberAPI INTERFACE IMPORTED)
target_include_directories(FiberAPI::FiberAPI INTERFACE
	"${FIBER_ROOT}/include"
	"${FIBER_ROOT}/third_party")

if(WIN32)
	add_library(FiberAPI::picohttpparser STATIC IMPORTED)
	set_target_properties(FiberAPI::picohttpparser PROPERTIES
		IMPORTED_LOCATION "${FIBER_ROOT}/lib/picohttpparser.lib")
	target_link_libraries(FiberAPI::FiberAPI INTERFACE
		FiberAPI::picohttpparser ws2_32 mswsock)
else()
	find_package(Threads REQUIRED)
	find_library(URING_LIBRARY uring REQUIRED)
	add_library(FiberAPI::picohttpparser STATIC IMPORTED)
	set_target_properties(FiberAPI::picohttpparser PROPERTIES
		IMPORTED_LOCATION "${FIBER_ROOT}/lib/libpicohttpparser.a")
	target_link_libraries(FiberAPI::FiberAPI INTERFACE
		FiberAPI::picohttpparser ${URING_LIBRARY} Threads::Threads)
endif()

add_executable(fiber_server main.cpp)
target_link_libraries(fiber_server PRIVATE FiberAPI::FiberAPI FiberAPI::picohttpparser)
