param(
  [ValidateSet('full', 'qs')]
  [string]$Variant = 'full'
)

$ErrorActionPreference = 'Stop'

Write-Host '[run_debug] Stopping running HelpDesk processes...'
$procNames = @('HelpDesk', 'HelpDeskQS', 'helpdesk', 'helpdeskqs')
foreach ($name in $procNames) {
  Get-Process -Name $name -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
}
# Wait a moment for process handles/windows to fully release.
Start-Sleep -Milliseconds 600

$root = $PSScriptRoot
$srcDll = Join-Path $root 'target\debug\librustdesk.dll'
$srcVd = Join-Path $root 'target\debug\deps\dylib_virtual_display.dll'
$dstDir = Join-Path $root 'flutter\build\windows\x64\runner\Debug'

Write-Host "[run_debug] Variant: $Variant"
Write-Host "[run_debug] Building Rust debug lib..."
cargo build --features flutter --lib

if (-not (Test-Path $srcDll)) {
  Write-Error "Missing $srcDll after cargo build"
}
if (-not (Test-Path $srcVd)) {
  $srcVd = Join-Path $root 'target\release\deps\dylib_virtual_display.dll'
}

New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
Copy-Item -Path $srcDll -Destination $dstDir -Force
if (Test-Path $srcVd) {
  Copy-Item -Path $srcVd -Destination $dstDir -Force
}

Set-Location (Join-Path $root 'flutter')

if ($Variant -eq 'full') {
  flutter run -d windows
  exit $LASTEXITCODE
}

# QS variant: executable name triggers is_qs() detection.
Write-Host '[run_debug] Building Windows debug runner for QS...'
flutter build windows --debug

$debugExe = Join-Path $PWD 'build\windows\x64\runner\Debug\HelpDesk.exe'
if (-not (Test-Path $debugExe)) {
  Write-Error "Missing $debugExe"
}

$qsExe = Join-Path $PWD 'build\windows\x64\runner\Debug\HelpDeskQS.exe'
Copy-Item -Path $debugExe -Destination $qsExe -Force

Write-Host '[run_debug] Launching QS debug exe...'
Start-Process -FilePath $qsExe -WorkingDirectory (Split-Path $qsExe)
Write-Host '[run_debug] QS launched. Logs are not attached to flutter run in this mode.'
