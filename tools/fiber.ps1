param(
    [Parameter(Position = 0)]
    [string]$Command = "help",
    [Parameter(Position = 1)]
    [string]$ProjectName,
    [string]$Template,
    [string]$BuildDirectory = "build",
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$defaultTemplate = "https://github.com/dixithsnaik/fiberapi.git"

function Get-CMakeGeneratorArguments {
    if (Get-Command ninja.exe -ErrorAction SilentlyContinue) {
        return @("-G", "Ninja")
    }
    if (Get-Command cl.exe -ErrorAction SilentlyContinue) {
        return @("-G", "Visual Studio 17 2022", "-A", "x64")
    }
    throw "No C++ build tool found. Install Visual Studio 2022 Desktop C++ or Ninja, then reopen PowerShell."
}

function Show-Help {
    @"
FiberAPI Windows CLI

Usage:
  fiber new NAME --Template URL   Clone a Git project template
  fiber build                     Build the current project
  fiber start                     Build and run fiber_server.exe
  fiber clean                     Remove the build directory
  fiber help                      Show this help

Environment:
  FIBER_TEMPLATE_REPO             Default Git template URL
  FIBER_BUILD_DIR                 Build directory (default: build)
"@
}

if ($Help -or $Command -in @("help", "--help", "-h")) {
    Show-Help
    exit 0
}

$projectDirectory = (Get-Location).Path
$buildDirectory = if ($env:FIBER_BUILD_DIR) { $env:FIBER_BUILD_DIR } else { $BuildDirectory }

switch ($Command) {
    "new" {
        if (-not $ProjectName) { throw "Usage: fiber new NAME --Template GIT_URL" }
        if (Test-Path $ProjectName) { throw "Refusing to overwrite existing path: $ProjectName" }
        $templateUrl = if ($Template) { $Template } elseif ($env:FIBER_TEMPLATE_REPO) { $env:FIBER_TEMPLATE_REPO } else { $defaultTemplate }
        if ($templateUrl -eq $defaultTemplate -and -not $Template -and -not $env:FIBER_TEMPLATE_REPO) {
            $temporaryDirectory = Join-Path $env:TEMP ("fiber-template-" + [guid]::NewGuid())
            git clone --depth 1 --filter=blob:none --no-checkout $templateUrl $temporaryDirectory
            git -C $temporaryDirectory sparse-checkout init --cone
            git -C $temporaryDirectory sparse-checkout set templates/notes include/fiber third_party
            git -C $temporaryDirectory read-tree -mu HEAD
            New-Item (Join-Path $ProjectName "fiber\include") -ItemType Directory -Force | Out-Null
            New-Item (Join-Path $ProjectName "fiber\third_party") -ItemType Directory -Force | Out-Null
            New-Item (Join-Path $ProjectName "fiber\lib") -ItemType Directory -Force | Out-Null
            Copy-Item (Join-Path $temporaryDirectory "templates\notes\CMakeLists.txt") $ProjectName
            Copy-Item (Join-Path $temporaryDirectory "templates\notes\main.cpp") $ProjectName
            Copy-Item (Join-Path $temporaryDirectory "include\fiber") (Join-Path $ProjectName "fiber\include") -Recurse
            Copy-Item (Join-Path $temporaryDirectory "third_party\picohttpparser.h") (Join-Path $ProjectName "fiber\third_party")
            Copy-Item (Join-Path $temporaryDirectory "third_party\picohttpparser.c") (Join-Path $ProjectName "fiber\third_party")
            Remove-Item $temporaryDirectory -Recurse -Force
        } else {
            git clone --depth 1 $templateUrl $ProjectName
        }
        Write-Host "Created $ProjectName from $templateUrl"
        Write-Host "Run: cd $ProjectName; fiber build"
    }
    "build" {
        $generatorArguments = Get-CMakeGeneratorArguments
        cmake -S $projectDirectory -B $buildDirectory @generatorArguments -DCMAKE_BUILD_TYPE=Debug
        cmake --build $buildDirectory --parallel
    }
    "start" {
        $generatorArguments = Get-CMakeGeneratorArguments
        cmake -S $projectDirectory -B $buildDirectory @generatorArguments -DCMAKE_BUILD_TYPE=Debug
        cmake --build $buildDirectory --parallel
        $executable = Join-Path $buildDirectory "fiber_server.exe"
        if (-not (Test-Path $executable)) {
            $executable = Join-Path $buildDirectory "Debug\fiber_server.exe"
        }
        if (-not (Test-Path $executable)) { throw "fiber_server.exe was not produced by the build" }
        & $executable
    }
    "clean" {
        Remove-Item $buildDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
    default {
        Show-Help
        exit 2
    }
}
