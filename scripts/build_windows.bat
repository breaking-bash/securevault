@echo off
REM ==========================================================================
REM SecureVault - Windows build (double-click or run from a VS/Developer prompt)
REM Requires: Flutter SDK + Visual Studio 2022 ("Desktop development with C++").
REM Output:   build\windows\x64\runner\Release\securevault.exe (+ DLLs)
REM ==========================================================================
setlocal
cd /d "%~dp0\.."

echo ==^> Flutter version
call flutter --version || goto :err

echo ==^> Enabling Windows desktop
call flutter config --enable-windows-desktop

echo ==^> Getting dependencies
call flutter pub get || goto :err

echo ==^> Building Windows release
call flutter build windows --release || goto :err

echo.
echo BUILD SUCCEEDED
echo App folder: build\windows\x64\runner\Release
echo Run:        build\windows\x64\runner\Release\securevault.exe
goto :eof

:err
echo.
echo BUILD FAILED - see messages above.
exit /b 1
