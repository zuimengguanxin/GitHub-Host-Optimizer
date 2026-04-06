@echo off
:: GitHub Host Optimizer - Launcher
chcp 65001 >nul 2>&1
cd /d "%~dp0"

echo ========================================
echo    GitHub Host Optimizer v1.0
echo ========================================
echo.
echo  [1] Run as Administrator (recommended)
echo  [2] Run as User
echo.
set /p choice="Select option (1 or 2): "

if "%choice%"=="1" (
    powershell -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0GitHub-Host-Optimizer.ps1\"' -Verb RunAs"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0GitHub-Host-Optimizer.ps1"
)