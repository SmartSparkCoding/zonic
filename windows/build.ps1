# Builds Zonic for Windows and zips it, ready to attach to a release.
# Run from anywhere: ./windows/build.ps1

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "windows/Zonic.Windows/Zonic.Windows.csproj"
$out = Join-Path $root "dist-windows"
$version = (Select-String -Path $project -Pattern '<Version>([^<]+)</Version>').Matches[0].Groups[1].Value

if (Test-Path $out) { Remove-Item $out -Recurse -Force }

dotnet publish $project `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true `
  -p:IncludeNativeLibrariesForSelfExtract=true `
  -p:EnableCompressionInSingleFile=true `
  -p:DebugType=none `
  -o $out

if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

Copy-Item (Join-Path $root "RELEASE_NOTES.md") $out -Force

$zip = Join-Path $root "Zonic-$version-windows.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $out "Zonic.exe"), (Join-Path $out "RELEASE_NOTES.md") -DestinationPath $zip

$size = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "Built $zip ($size MB)"
