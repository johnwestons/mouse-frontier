@echo off
setlocal
title Mouse Frontier Launcher

set "GAME_DIR=%~dp0"
rem Remove the trailing backslash so it cannot escape the closing quote.
if "%GAME_DIR:~-1%"=="\" set "GAME_DIR=%GAME_DIR:~0,-1%"
set "LOVE_EXE="

where love.exe >nul 2>nul
if not errorlevel 1 set "LOVE_EXE=love.exe"

if not defined LOVE_EXE if exist "%ProgramFiles%\LOVE\love.exe" set "LOVE_EXE=%ProgramFiles%\LOVE\love.exe"
if not defined LOVE_EXE if exist "%ProgramFiles(x86)%\LOVE\love.exe" set "LOVE_EXE=%ProgramFiles(x86)%\LOVE\love.exe"
if not defined LOVE_EXE if exist "%LOCALAPPDATA%\LOVE\love.exe" set "LOVE_EXE=%LOCALAPPDATA%\LOVE\love.exe"

if not defined LOVE_EXE goto missing_love

echo Starting Mouse Frontier...
start "Mouse Frontier" "%LOVE_EXE%" "%GAME_DIR%"
exit /b 0

:missing_love
echo.
echo ============================================================
echo  Mouse Frontier could not find LOVE on this computer.
echo ============================================================
echo.
echo  1. Open https://love2d.org/
echo  2. Click Download, then choose the Windows 64-bit installer.
echo  3. Complete the installation using the default options.
echo  4. Double-click RUN_GAME.bat again.
echo.
echo If LOVE is already installed somewhere unusual, drag this
echo project folder onto love.exe to start the game.
echo.
pause
exit /b 1
