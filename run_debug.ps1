$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$srcDll = Join-Path $root 'target\release\librustdesk.dll'
$srcVd = Join-Path $root 'target\release\deps\dylib_virtual_display.dll'
$dstDir = Join-Path $PSScriptRoot 'build\windows\x64\runner\Debug'

if (-not (Test-Path $srcDll)) {
  Write-Error "Missing $srcDll. Run: python build.py --flutter"
}
if (-not (Test-Path $srcVd)) {
  Write-Error "Missing $srcVd. Run: python build.py --flutter"
}

New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
Copy-Item -Path $srcDll -Destination $dstDir -Force
Copy-Item -Path $srcVd -Destination $dstDir -Force

flutter run -d windows
