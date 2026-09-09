param(
    [string]$InstallDirectory = "$HOME\AppData\Local\FiberAPI\bin"
)

$ErrorActionPreference = "Stop"
$source = Join-Path $PSScriptRoot "fiber.ps1"
New-Item -ItemType Directory -Force $InstallDirectory | Out-Null
Copy-Item $source (Join-Path $InstallDirectory "fiber.ps1") -Force

$shim = Join-Path $InstallDirectory "fiber.cmd"
Set-Content -Path $shim -Value '@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0fiber.ps1" %*' -Encoding ASCII

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathEntries = @($userPath -split ";" | Where-Object { $_ })
if ($pathEntries -notcontains $InstallDirectory) {
    [Environment]::SetEnvironmentVariable("Path", (($pathEntries + $InstallDirectory) -join ";"), "User")
}
$env:Path = "$InstallDirectory;$env:Path"

Write-Host "Installed fiber CLI to $InstallDirectory"
Write-Host "Open a new PowerShell window, then run: fiber help"
