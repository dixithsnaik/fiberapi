param(
    [string]$InstallDirectory = "$HOME\AppData\Local\FiberAPI\bin",
    [string]$RawBaseUrl = "",
    [switch]$SkipBuildTools,
    [switch]$UpgradeCompiler
)

$ErrorActionPreference = "Stop"
$installerVersion = "0.3.1"
$cliUrl = if ($RawBaseUrl) {
    "$RawBaseUrl/fiber.ps1"
} else {
    "https://github.com/dixithsnaik/fiberapi/releases/download/v$installerVersion/fiber.ps1"
}

function Test-CppToolchain {
    if (Get-Command ninja.exe -ErrorAction SilentlyContinue) {
        return $true
    }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $msbuild = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find MSBuild\**\Bin\MSBuild.exe 2>$null | Select-Object -First 1
        if ($msbuild -and (Test-Path $msbuild)) {
            return $true
        }
    }
    return [bool](Get-Command cl.exe -ErrorAction SilentlyContinue)
}

function Get-GccVersion {
    $gxx = Get-Command g++.exe -ErrorAction SilentlyContinue
    if (-not $gxx) { return $null }
    $versionText = & $gxx.Source --version | Select-Object -First 1
    if ($versionText -match "(\d+)\.") { return [int]$Matches[1] }
    return $null
}

function Install-CppToolchain {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw "winget is unavailable. Install Visual Studio Build Tools manually."
    }
    Write-Host "Installing Visual Studio C++ Build Tools..."
    winget install Microsoft.VisualStudio.2022.BuildTools `
        --accept-source-agreements --accept-package-agreements `
        --override "--wait --passive --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended"
    if ($LASTEXITCODE -ne 0) {
        throw "C++ Build Tools installation failed with exit code $LASTEXITCODE"
    }
}

if (-not $SkipBuildTools -and -not (Test-CppToolchain)) {
    $gccVersion = Get-GccVersion
    if ($gccVersion) {
        Write-Host "Detected GCC $gccVersion. FiberAPI requires GCC 12+ or MSVC C++ Build Tools."
    } else {
        Write-Host "No supported C++ compiler was detected."
    }
    $answer = if ($UpgradeCompiler) { "Y" } else {
        Read-Host "Upgrade/install C++ Build Tools automatically now? (Y/N)"
    }
    if ($answer -notmatch "^(?i)y(es)?$") {
        throw "Compiler upgrade cancelled. FiberAPI requires GCC 12+ or MSVC C++ Build Tools."
    }
    Install-CppToolchain
    Write-Host "C++ Build Tools installed. Open a new terminal before running fiber dev."
}
$localSource = if ($PSScriptRoot) { Join-Path $PSScriptRoot "fiber.ps1" } else { $null }
$source = Join-Path $InstallDirectory "fiber.ps1"
$windowsAppsDirectory = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"

$oldInstallDirectories = @(
    $InstallDirectory,
    (Join-Path $HOME "AppData\Local\FiberAPI\bin")
) | Select-Object -Unique
foreach ($directory in $oldInstallDirectories) {
    Remove-Item (Join-Path $directory "fiber.ps1") -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $directory "fiber.cmd") -Force -ErrorAction SilentlyContinue
}
if (Test-Path $windowsAppsDirectory) {
    Remove-Item (Join-Path $windowsAppsDirectory "fiber.ps1") -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $windowsAppsDirectory "fiber.cmd") -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Force $InstallDirectory | Out-Null
if ($localSource -and (Test-Path $localSource)) {
    Copy-Item $localSource $source -Force
} else {
    Invoke-WebRequest $cliUrl -OutFile $source
}

$shim = Join-Path $InstallDirectory "fiber.cmd"
Set-Content -Path $shim -Value '@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0fiber.ps1" %*' -Encoding ASCII

if (Test-Path $windowsAppsDirectory) {
    $windowsAppsScript = Join-Path $windowsAppsDirectory "fiber.ps1"
    Set-Content -Path $windowsAppsScript -Value "& '$source' @args" -Encoding UTF8
    Copy-Item $shim (Join-Path $windowsAppsDirectory "fiber.cmd") -Force
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathEntries = @($userPath -split ";" | Where-Object {
    $_ -and $_ -notmatch "(?i)FiberAPI[\\/]bin"
})
[Environment]::SetEnvironmentVariable("Path", (($pathEntries + $InstallDirectory) -join ";"), "User")
$env:Path = "$InstallDirectory;$env:Path"

$profileDirectory = Split-Path -Parent $PROFILE
if (-not (Test-Path $profileDirectory)) {
    New-Item $profileDirectory -ItemType Directory -Force | Out-Null
}
$profileLine = "`$env:Path = `"$InstallDirectory;`$env:Path`""
if (Test-Path $PROFILE) {
    $profileContent = Get-Content $PROFILE | Where-Object {
        $_ -notmatch "(?i)FiberAPI[\\/]bin" -and $_ -notmatch "fiber\.cmd"
    }
    Set-Content -Path $PROFILE -Value $profileContent
}
Add-Content -Path $PROFILE -Value "`n$profileLine"

Write-Host "Installed Fiber CLI v$installerVersion to $InstallDirectory"
if (Test-Path (Join-Path $windowsAppsDirectory "fiber.cmd")) {
    Write-Host "Installed fiber command to $windowsAppsDirectory"
}
Write-Host "PowerShell profile configured: $PROFILE"
Write-Host "Open a new PowerShell window, then run: fiber help"
