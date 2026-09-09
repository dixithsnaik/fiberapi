param(
    [string]$InstallDirectory = "$HOME\AppData\Local\FiberAPI\bin",
    [string]$RawBaseUrl = "",
    [switch]$SkipBuildTools,
    [switch]$UpgradeCompiler
)

$ErrorActionPreference = "Stop"
$installerVersion = "0.3.7"
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

function Install-Msys2Gcc {
    $bash = "C:\msys64\usr\bin\bash.exe"
    if (-not (Test-Path $bash)) {
        if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
            throw "winget is unavailable. Install MSYS2 manually from https://www.msys2.org/"
        }
        winget install --id MSYS2.MSYS2 --exact --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0 -and -not (Test-Path $bash)) {
            throw "MSYS2 installation failed with exit code $LASTEXITCODE"
        }
    }
    if (-not (Test-Path $bash)) {
        throw "MSYS2 was installed in an unexpected location. Install the UCRT64 toolchain manually."
    }
    & $bash -lc "pacman -Syu --noconfirm"
    & $bash -lc "pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-toolchain"
    if ($LASTEXITCODE -ne 0) {
        throw "MSYS2 GCC installation failed with exit code $LASTEXITCODE"
    }
    $ucrtBin = "C:\msys64\ucrt64\bin"
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $pathEntries = @($userPath -split ";" | Where-Object {
        $_ -and $_ -ne $ucrtBin -and $_ -notmatch "(?i)(mingw|msys64)[\\/]mingw(32|64)[\\/]bin"
    })
    [Environment]::SetEnvironmentVariable("Path", (($ucrtBin + $pathEntries) -join ";"), "User")
    $env:Path = "$ucrtBin;$env:Path"
}

$gccVersion = Get-GccVersion
$needsCompiler = -not (Test-CppToolchain)
$needsGccUpgrade = $gccVersion -and $gccVersion -lt 12
if (-not $SkipBuildTools -and ($needsCompiler -or $needsGccUpgrade)) {
    $gccVersion = Get-GccVersion
    if ($gccVersion) {
        Write-Host "Detected GCC $gccVersion. FiberAPI requires GCC 12+."
    } else {
        Write-Host "No supported C++ compiler was detected."
    }
    $answer = if ($UpgradeCompiler) { "Y" } else {
        Read-Host "Upgrade/install C++ Build Tools automatically now? (Y/N)"
    }
    if ($answer -notmatch "^(?i)y(es)?$") {
        throw "Compiler upgrade cancelled. FiberAPI requires GCC 12+."
    }
    Install-Msys2Gcc
    Write-Host "Modern GCC installed. Open a new terminal before running fiber dev."
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
$ucrt64Bin = "C:\msys64\ucrt64\bin"
if (Test-Path (Join-Path $ucrt64Bin "g++.exe")) {
    $env:Path = "$ucrt64Bin;$env:Path"
}

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
