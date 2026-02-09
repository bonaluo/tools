@echo off
chcp 65001 >nul
:: 检查是否以管理员身份运行
net session >nul 2>&1
if %errorLevel% == 0 (
    :: 已经是管理员，直接执行 PowerShell 脚本
    powershell.exe -ExecutionPolicy Bypass -File "%~dp0ddns-go-update.ps1"
    exit /b
) else (
    :: 不是管理员，请求管理员权限并重新运行本脚本
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)
