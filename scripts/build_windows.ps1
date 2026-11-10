# =============================================================================
# SecureVault — Windows build script (run on a Windows machine)
# =============================================================================
# Produces a native, standalone Windows release build (.exe + required DLLs).
#
# Prerequisites (install once):
#   1. Flutter SDK (stable)         -> https://docs.flutter.dev/get-started/install/windows
#   2. Visual Studio 2022 with the  "Desktop development with C++"  workload
#      (includes MSVC, Windows 10/11 SDK, CMake). Flutter needs this to compile.
#   3. Run:  flutter config --enable-windows-desktop
#
# Usage (PowerShell, from the project root):
#   ./scripts/build_windows.ps1
#
# Output:
#   build\windows\x64\runner\Release\        <-- the whole folder is the app
#   build\windows\x64\runner\Release\securevault.exe
#   (sqlite3.dll and the Flutter DLLs are copied in automatically)
# To distribute: zip the entire Release folder; the user runs securevault.exe.
# =============================================================================

$ErrorActionPreference = "Stop"

Write-Host "==> Checking Flutter..." -ForegroundColor Cyan
flutter --version

Write-Host "==> Enabling Windows desktop support..." -ForegroundColor Cyan
flutter config --enable-windows-desktop | Out-Null

Write-Host "==> Fetching dependencies..." -ForegroundColor Cyan
flutter pub get

Write-Host "==> Building Windows release (this compiles native C++ via MSVC)..." -ForegroundColor Cyan
flutter build windows --release

$releaseDir = Join-Path $PSScriptRoot "..\build\windows\x64\runner\Release"
if (Test-Path $releaseDir) {
    Write-Host ""
    Write-Host "BUILD SUCCEEDED" -ForegroundColor Green
    Write-Host "App folder : $releaseDir"
    Write-Host "Executable : $(Join-Path $releaseDir 'securevault.exe')"
    Write-Host ""
    Write-Host "Distribute the ENTIRE Release folder (zip it) — the .exe needs the DLLs beside it."
} else {
    Write-Host "Build finished but output folder not found at $releaseDir" -ForegroundColor Yellow
    exit 1
}
