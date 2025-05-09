@echo off
chcp 65001 >nul

:: 添加了 net session 检查是否具有管理员权限。 
net session >nul 2>&1
:: 如果没有管理员权限，%errorlevel% 将不为 0。 
if %errorlevel% neq 0 (
    echo This script requires administrator privileges.
    echo Requesting administrator privileges...
    :: pause
    :: 如果没有权限，使用 PowerShell 的 Start-Process 以管理员权限重新启动脚本。 
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    :: 如果权限不足，原脚本会退出，避免重复执行。 
    exit /b
)

winget settings --enable InstallerHashOverride
winget update -u -r -h --ignore-security-hash --accept-package-agreements --authentication-mode silentPreferred
pause
