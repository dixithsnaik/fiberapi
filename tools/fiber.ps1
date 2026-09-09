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
        $templateUrl = if ($Template) { $Template } else { $env:FIBER_TEMPLATE_REPO }
        if (-not $templateUrl) { throw "Provide --Template GIT_URL or set FIBER_TEMPLATE_REPO" }
        git clone --depth 1 $templateUrl $ProjectName
        Write-Host "Created $ProjectName from $templateUrl"
        Write-Host "Run: cd $ProjectName; fiber build"
    }
    "build" {
        cmake -S $projectDirectory -B $buildDirectory -G Ninja -DCMAKE_BUILD_TYPE=Debug
        cmake --build $buildDirectory --parallel
    }
    "start" {
        cmake -S $projectDirectory -B $buildDirectory -G Ninja -DCMAKE_BUILD_TYPE=Debug
        cmake --build $buildDirectory --parallel
        & (Join-Path $buildDirectory "fiber_server.exe")
    }
    "clean" {
        Remove-Item $buildDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
    default {
        Show-Help
        exit 2
    }
}
