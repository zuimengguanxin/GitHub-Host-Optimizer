@echo off
:: GitHub Host 智能优选工具 - 一键运行
:: 自动以管理员身份运行 PowerShell 脚本

cd /d "%~dp0"
powershell -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0GitHub-Host-Optimizer.ps1\"' -Verb RunAs"
