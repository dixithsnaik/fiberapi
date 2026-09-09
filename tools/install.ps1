param(
    [string]$InstallDirectory = "$HOME\AppData\Local\FiberAPI\bin",
    [string]$RawBaseUrl = "https://raw.githubusercontent.com/dixithsnaik/fiberapi/main/tools",
    [switch]$SkipBuildTools
)

$ErrorActionPreference = "Stop"
$installerVersion = "0.2.5"

function Test-CppToolchain {
    if (Get-Command ninja.exe -ErrorAction SilentlyContinue) {
        return $true
    }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $installationPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
        if ($installationPath -and (Test-Path $installationPath)) {
            return $true
        }
    }
    return [bool](Get-Command cl.exe -ErrorAction SilentlyContinue)
}

if (-not $SkipBuildTools -and -not (Test-CppToolchain)) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw "No C++ toolchain found. Install Visual Studio 2022 Desktop C++ manually, then run the installer again."
    }
    Write-Host "Installing Visual Studio 2022 Desktop C++ workload..."
    winget install Microsoft.VisualStudio.2022.BuildTools `
        --accept-source-agreements --accept-package-agreements `
        --override "--wait --passive --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended"
    if ($LASTEXITCODE -ne 0) {
        throw "Visual Studio installation failed with exit code $LASTEXITCODE"
    }
    Write-Host "Visual Studio C++ tools installed. Open a new terminal before running fiber dev."
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
    Invoke-WebRequest "$RawBaseUrl/fiber.ps1" -OutFile $source
}

$shim = Join-Path $InstallDirectory "fiber.cmd"
Set-Content -Path $shim -Value '@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0fiber.ps1" %*' -Encoding ASCII

if (Test-Path $windowsAppsDirectory) {
    Copy-Item $source (Join-Path $windowsAppsDirectory "fiber.ps1") -Force
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
