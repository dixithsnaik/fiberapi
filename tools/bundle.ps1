param(
    [Parameter(Mandatory = $true)]
    [string]$Destination,
    [string]$BuildDirectory = "build"
)

$ErrorActionPreference = "Stop"
$frameworkRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\")).Path
$bundleRoot = Join-Path $Destination "fiber"
$includeSource = Join-Path $frameworkRoot "include\fiber"
$parserHeader = Join-Path $frameworkRoot "third_party\picohttpparser.h"
$libraryCandidates = @(
    (Join-Path $frameworkRoot "$BuildDirectory\picohttpparser.lib"),
    (Join-Path $frameworkRoot "$BuildDirectory\Release\picohttpparser.lib"),
    (Join-Path $frameworkRoot "$BuildDirectory\Debug\picohttpparser.lib")
)
$parserLibrary = $libraryCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not (Test-Path $includeSource)) {
    throw "FiberAPI headers were not found at $includeSource"
}
if (-not $parserLibrary) {
    throw "picohttpparser.lib was not found. Build FiberAPI first."
}

Remove-Item $bundleRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item (Join-Path $bundleRoot "include") -ItemType Directory -Force | Out-Null
New-Item (Join-Path $bundleRoot "third_party") -ItemType Directory -Force | Out-Null
New-Item (Join-Path $bundleRoot "lib") -ItemType Directory -Force | Out-Null
Copy-Item $includeSource (Join-Path $bundleRoot "include") -Recurse
Copy-Item $parserHeader (Join-Path $bundleRoot "third_party")
Copy-Item $parserLibrary (Join-Path $bundleRoot "lib\picohttpparser.lib")

Write-Host "Created vendored FiberAPI dependency at $bundleRoot"
