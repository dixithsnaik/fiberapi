cmake_minimum_required(VERSION 3.20)
project(FiberAPI LANGUAGES C CXX)

include(GNUInstallDirs)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(picohttpparser STATIC third_party/picohttpparser.c)
target_include_directories(picohttpparser PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/third_party>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/fiber>)
set_target_properties(picohttpparser PROPERTIES C_STANDARD 99 C_STANDARD_REQUIRED ON)

find_package(Threads REQUIRED)

add_library(FiberAPI INTERFACE)
target_compile_features(FiberAPI INTERFACE cxx_std_20)
target_include_directories(FiberAPI INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/third_party>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>)
if(WIN32)
    target_link_libraries(FiberAPI INTERFACE ws2_32 mswsock Threads::Threads)
else()
    find_library(URING_LIBRARY uring REQUIRED)
    target_link_libraries(FiberAPI INTERFACE ${URING_LIBRARY} Threads::Threads)
endif()

add_executable(fiber_server examples/main.cpp)
target_include_directories(fiber_server PRIVATE include third_party)
target_link_libraries(fiber_server PRIVATE FiberAPI picohttpparser)
if(MSVC)
    target_compile_options(fiber_server PRIVATE /O2 /W4)
else()
    target_compile_options(fiber_server PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-O3;-march=native;-Wall;-Wextra>)
endif()

install(TARGETS FiberAPI picohttpparser
    EXPORT FiberAPITargets
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})
install(DIRECTORY include/ DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
install(FILES third_party/picohttpparser.h DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/fiber)
install(EXPORT FiberAPITargets
    FILE FiberAPITargets.cmake
    NAMESPACE FiberAPI::
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/FiberAPI)
install(FILES cmake/FiberAPIConfig.cmake
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/FiberAPI)

include(CTest)
if(BUILD_TESTING)
    add_executable(fiber_header_test tests/request_test.cpp)
    target_include_directories(fiber_header_test PRIVATE include)
    target_compile_options(fiber_header_test PRIVATE -Wall -Wextra -Werror -pedantic)
    add_test(NAME fiber_header_test COMMAND fiber_header_test)
endif()
