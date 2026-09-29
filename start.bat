@echo off
rem Double-click to start MemeGuard on Windows (installs on first run, then opens the dashboard).
title MemeGuard
cd /d "%~dp0"

where node >nul 2>nul
if errorlevel 1 goto nonode

node scripts\start.mjs
echo.
pause
exit /b

:nonode
echo MemeGuard needs Node.js, which is not installed on this computer.
echo.
where winget >nul 2>nul
if errorlevel 1 goto website
choice /c YN /m "Install Node.js now"
if errorlevel 2 goto website
winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
echo.
echo Done. Close this window, then double-click start.bat again.
pause
exit /b

:website
echo Opening the Node.js download page. Install the LTS version,
echo then double-click start.bat again.
start "" "https://nodejs.org/en/download"
pause
