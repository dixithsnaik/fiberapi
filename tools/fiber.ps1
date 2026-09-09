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
$fiberVersion = "0.3.8"

# Prefer the installed MSYS2 UCRT64 toolchain even when this terminal was
# created by an older VS Code process with a stale PATH snapshot.
$ucrt64Bin = "C:\msys64\ucrt64\bin"
if (Test-Path (Join-Path $ucrt64Bin "g++.exe")) {
    $env:Path = "$ucrt64Bin;$env:Path"
}

function Get-CMakeGeneratorArguments {
    if (Get-Command ninja.exe -ErrorAction SilentlyContinue) {
        return @("-G", "Ninja")
    }
    $gxx = Get-Command g++.exe -ErrorAction SilentlyContinue
    $mingwMake = Get-Command mingw32-make.exe -ErrorAction SilentlyContinue
    if ($gxx -and $mingwMake) {
        $versionText = (& $gxx.Source --version | Select-Object -First 1)
        if ($versionText -match "(\d+)\.") {
            $gccMajor = [int]$Matches[1]
            if ($gccMajor -ge 12) {
                return @("-G", "MinGW Makefiles")
            }
            throw "GCC $gccMajor is too old. FiberAPI requires GCC 12+ for C++20."
        }
    }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    $visualStudio = if (Test-Path $vswhere) {
        & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find MSBuild\**\Bin\MSBuild.exe 2>$null | Select-Object -First 1
    } else {
        $null
    }
    if (($visualStudio -and (Test-Path $visualStudio)) -or (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
        return @("-G", "Visual Studio 17 2022", "-A", "x64")
    }
    throw "No supported C++ build tool found. Install Visual Studio Build Tools, Ninja, or MinGW GCC 12+, then reopen PowerShell."
}

function Show-Help {
    @"
FiberAPI Windows CLI v$fiberVersion

Usage:
  fiber new NAME --Template URL   Clone a Git project template
  fiber build                     Build the current project
    fiber dev                       Debug build with automatic refresh
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
if ($Command -in @("version", "--version", "-v")) {
    Write-Host "fiber $fiberVersion"
    exit 0
}

$projectDirectory = (Get-Location).Path
$buildDirectory = if ($env:FIBER_BUILD_DIR) { $env:FIBER_BUILD_DIR } else { $BuildDirectory }
$serverProcess = $null

function Invoke-Build {
    param([string]$Configuration = "Debug")
    $generatorArguments = Get-CMakeGeneratorArguments
    cmake -S $projectDirectory -B $buildDirectory @generatorArguments "-DCMAKE_BUILD_TYPE=$Configuration"
    if ($LASTEXITCODE -ne 0) { return $false }
    cmake --build $buildDirectory --parallel
    return ($LASTEXITCODE -eq 0)
}

function Get-SourceSnapshot {
    $files = @(
        Get-ChildItem $projectDirectory -File -ErrorAction SilentlyContinue
        Get-ChildItem (Join-Path $projectDirectory "fiber") -File -Recurse -ErrorAction SilentlyContinue
    ) | Where-Object { $_.FullName -notmatch "[\\/]build[\\/]" } | Sort-Object FullName
    return (($files | ForEach-Object { "$($_.FullName):$($_.LastWriteTimeUtc.Ticks):$($_.Length)" }) -join "`n")
}

function Get-ServerPath {
    $paths = @(
        (Join-Path $buildDirectory "fiber_server.exe"),
        (Join-Path $buildDirectory "Debug\fiber_server.exe")
    )
    return $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Stop-DevServer {
    if ($null -ne $script:serverProcess -and -not $script:serverProcess.HasExited) {
        Stop-Process -Id $script:serverProcess.Id -Force -ErrorAction SilentlyContinue
        $script:serverProcess.WaitForExit()
    }
    $script:serverProcess = $null
}

function Start-DevServer {
    $executable = Get-ServerPath
    if (-not $executable) { throw "fiber_server.exe was not produced by the build" }
    $script:serverProcess = Start-Process -FilePath $executable -NoNewWindow -PassThru
    Write-Host "FiberAPI server running (pid $($script:serverProcess.Id))"
}

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
        if (-not (Invoke-Build)) { exit 1 }
    }
    "dev" {
        if (-not (Invoke-Build "Debug")) { exit 1 }
        try {
            Start-DevServer
            $snapshot = Get-SourceSnapshot
            Write-Host "Watching for changes. Press Ctrl-C to stop."
            while ($true) {
                Start-Sleep -Seconds 1
                $currentSnapshot = Get-SourceSnapshot
                if ($currentSnapshot -eq $snapshot) { continue }
                $snapshot = $currentSnapshot
                Write-Host "Change detected; rebuilding..."
                Stop-DevServer
                if (Invoke-Build "Debug") {
                    Start-DevServer
                } else {
                    Write-Warning "Build failed; waiting for the next change."
                }
            }
        } finally {
            Stop-DevServer
        }
    }
    "start" {
        if (-not (Invoke-Build)) { exit 1 }
        $executable = Get-ServerPath
        if (-not $executable) { throw "fiber_server.exe was not produced by the build" }
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
