# FiberAPI

FiberAPI is a C++20 HTTP framework built around native asynchronous I/O, coroutines, and `std::string_view` request parsing. Linux uses `io_uring`; Windows uses IOCP.

## Requirements

- Linux or Windows 10/11
- GCC 12+ or Clang 15+
- CMake 3.20+
- Ninja
- `liburing` development files on Linux

On Ubuntu or WSL2, install everything with:

```bash
sudo apt update
sudo apt install -y build-essential cmake ninja-build liburing-dev
```

On Windows, install Visual Studio 2022 with the Desktop C++ workload, CMake, and Ninja. Build from PowerShell or the Visual Studio Developer PowerShell; the Windows backend uses IOCP and does not require WSL.

## Windows CLI

Install the native CLI from the latest GitHub Release. Download `fiber-install.cmd` and double-click it. It downloads and runs the PowerShell installer automatically; no ZIP archive or terminal command is required.

Release page: https://github.com/dixithsnaik/fiberapi/releases/latest

Open a new PowerShell window after installation. The CLI can clone an application template from Git:

```powershell
fiber new notes-api --Template https://github.com/your-name/fiber-notes-template.git
cd notes-api
fiber build
fiber start
```

The template repository should contain the application `CMakeLists.txt`, `main.cpp`, and its small `fiber/` dependency bundle. The CLI does not clone the full FiberAPI framework repository into the application.

Complete newcomer workflow:

```powershell
fiber new notes-api --Template https://github.com/your-name/fiber-notes-template.git
cd notes-api
fiber build
fiber start
```

You can set a default template URL:

```powershell
$env:FIBER_TEMPLATE_REPO = "https://github.com/your-name/fiber-notes-template.git"
fiber new notes-api
```

## Build And Run

From the FiberAPI directory:

```bash
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
cmake --build build
ctest --test-dir build --output-on-failure
./build/fiber_server
```

The same workflow is available through the editable `fiber` command:

```bash
./fiber build
./fiber test
./fiber start
```

To make the command available exactly as `fiber dev` from any directory, install the local CLI once:

```bash
./fiber install
source "$HOME/.bashrc"
fiber dev
```

The installer creates `~/.local/bin/fiber` as a symlink to this project, so edits to the project command remain active. If you do not want to install it globally for your user, use `./fiber ...` from the repository instead.

`fiber dev` builds a Debug binary, starts the server, and watches framework, example, parser, and CMake files. When a file changes, it rebuilds and restarts the server automatically. Stop the watcher with `Ctrl-C`.

```bash
./fiber dev
```

The command is a plain shell script, so project commands can be changed directly in `fiber`. It also supports `FIBER_BUILD_DIR`, `FIBER_BUILD_TYPE`, `FIBER_GENERATOR`, `FIBER_JOBS`, and `FIBER_WATCH_INTERVAL` environment overrides. For example:

```bash
FIBER_BUILD_DIR=debug FIBER_JOBS=4 FIBER_WATCH_INTERVAL=0.5 ./fiber dev
```

The example listens on `0.0.0.0:8080`. Its protected routes require a Bearer token:

```bash
curl -H 'Authorization: Bearer demo-user' http://127.0.0.1:8080/ping
curl -H 'Authorization: Bearer demo-user' http://127.0.0.1:8080/users/42
curl -H 'Authorization: Bearer demo-user' -d 'hello' http://127.0.0.1:8080/echo
```

Stop the server with `Ctrl-C`.

## Start A Notes Backend

On Windows, open the project in VS Code and use PowerShell or a Visual Studio Developer PowerShell terminal. Native Windows uses the IOCP backend; WSL2 is only needed when you specifically want to test the Linux `io_uring` backend.

From the FiberAPI repository:

```bash
./fiber install
source "$HOME/.bashrc"
fiber new notes-api
cd notes-api
fiber dev
```

This creates a small backend with:

- `GET /health` returning `{"ok":true}`
- `POST /notes` accepting a note body

Test it from another WSL terminal:

```bash
curl http://127.0.0.1:8080/health
curl -X POST -d 'buy milk' http://127.0.0.1:8080/notes
```

The generated project contains only `CMakeLists.txt` and `main.cpp`. Edit `main.cpp`, save it, and `fiber dev` rebuilds and restarts automatically.

## Install

Install the headers and CMake targets for use by another project:

```bash
cmake --install build --prefix "$HOME/.local"
```

Then a consumer project can use FiberAPI with:

```cmake
find_package(FiberAPI CONFIG REQUIRED)
add_executable(app main.cpp)
target_link_libraries(app PRIVATE FiberAPI::FiberAPI FiberAPI::picohttpparser)
```

The consumer should include headers normally:

```cpp
#include <fiber/router.hpp>
#include <fiber/server.hpp>
```

## New Project Template

FiberAPI is installed once as a dependency. A new application contains only its own files; do not copy the FiberAPI repository, headers, or `third_party` directory into every project.

For a portable project that carries only the required FiberAPI support files, generate the app with:

```bash
./fiber new notes-api
```

This creates:

```text
notes-api/
├── CMakeLists.txt
├── main.cpp
└── fiber/
    ├── include/fiber/
    ├── third_party/picohttpparser.h
    └── lib/libpicohttpparser.a
```

On Windows, use `picohttpparser.lib` instead of `libpicohttpparser.a`. After building FiberAPI on Windows, create the bundle with PowerShell:

```powershell
.\tools\bundle.ps1 -Destination D:\tempCppNoteApp
Copy-Item .\templates\notes\CMakeLists.txt D:\tempCppNoteApp\CMakeLists.txt -Force
Copy-Item .\templates\notes\main.cpp D:\tempCppNoteApp\main.cpp -Force
```

The generated CMake file automatically links IOCP libraries on Windows and `liburing` plus pthreads on Linux. No framework examples, tests, source files, or build directory are copied.

To create only the dependency bundle for an existing app:

```bash
./fiber bundle path/to/my-app
```

Then copy the generated `templates/notes/CMakeLists.txt` and `templates/notes/main.cpp` only when starting a new notes app.

Install FiberAPI once on Windows with:

```powershell
cd D:\FiberAPI
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
cmake --install build --prefix D:\FiberAPI\install
```

Then create a new application with only `CMakeLists.txt` and `main.cpp`:

```bash
mkdir my-fiber-app && cd my-fiber-app
```

`CMakeLists.txt`:

```cmake
cmake_minimum_required(VERSION 3.20)
project(my_fiber_app LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(FiberAPI CONFIG REQUIRED)
add_executable(my_fiber_app main.cpp)
target_link_libraries(my_fiber_app PRIVATE FiberAPI::FiberAPI FiberAPI::picohttpparser)
```

Build it with:

```bash
cmake -S . -B build -G Ninja -DCMAKE_PREFIX_PATH="$HOME/.local"
cmake --build build
./build/my_fiber_app
```

On Windows, use the installed dependency path instead:

```powershell
cmake -S . -B build -G Ninja `
    -DCMAKE_BUILD_TYPE=Debug `
    -DCMAKE_PREFIX_PATH="D:\FiberAPI\install"
cmake --build build
.\build\my_fiber_app.exe
```

## Example Route

```cpp
#include <fiber/router.hpp>
#include <fiber/server.hpp>

using namespace fiber;

int main() {
    Router app;
    app.get("/", [](Context& ctx) {
        ctx.text("hello from FiberAPI");
    });
    Server server(app, 8080);
    server.run();
}
```# fiberapi
