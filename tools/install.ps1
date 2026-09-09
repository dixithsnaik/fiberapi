param(
    [string]$InstallDirectory = "$HOME\AppData\Local\FiberAPI\bin",
    [string]$RawBaseUrl = "https://raw.githubusercontent.com/dixithsnaik/fiberapi/main/tools"
)

$ErrorActionPreference = "Stop"
$localSource = if ($PSScriptRoot) { Join-Path $PSScriptRoot "fiber.ps1" } else { $null }
$source = Join-Path $InstallDirectory "fiber.ps1"
New-Item -ItemType Directory -Force $InstallDirectory | Out-Null
if ($localSource -and (Test-Path $localSource)) {
    Copy-Item $localSource $source -Force
} else {
    Invoke-WebRequest "$RawBaseUrl/fiber.ps1" -OutFile $source
}

$shim = Join-Path $InstallDirectory "fiber.cmd"
Set-Content -Path $shim -Value '@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0fiber.ps1" %*' -Encoding ASCII

$windowsAppsDirectory = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
if (Test-Path $windowsAppsDirectory) {
    Copy-Item $source (Join-Path $windowsAppsDirectory "fiber.ps1") -Force
    Copy-Item $shim (Join-Path $windowsAppsDirectory "fiber.cmd") -Force
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathEntries = @($userPath -split ";" | Where-Object { $_ })
if ($pathEntries -notcontains $InstallDirectory) {
    [Environment]::SetEnvironmentVariable("Path", (($pathEntries + $InstallDirectory) -join ";"), "User")
}
$env:Path = "$InstallDirectory;$env:Path"

$profileDirectory = Split-Path -Parent $PROFILE
if (-not (Test-Path $profileDirectory)) {
    New-Item $profileDirectory -ItemType Directory -Force | Out-Null
}
$profileLine = "`$env:Path = `"$InstallDirectory;`$env:Path`""
if (-not (Test-Path $PROFILE) -or -not (Select-String -Path $PROFILE -SimpleMatch $InstallDirectory -Quiet)) {
    Add-Content -Path $PROFILE -Value "`n$profileLine"
}

Write-Host "Installed fiber CLI to $InstallDirectory"
if (Test-Path (Join-Path $windowsAppsDirectory "fiber.cmd")) {
    Write-Host "Installed fiber command to $windowsAppsDirectory"
}
Write-Host "PowerShell profile configured: $PROFILE"
Write-Host "Open a new PowerShell window, then run: fiber help"
