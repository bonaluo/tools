@echo off
REM GitHub通用更新脚本 - 批处理包装器
REM 版本: 1.0.0
REM 用法: github-update.bat [参数]

setlocal enabledelayedexpansion

REM 脚本信息
set SCRIPT_NAME=github-update
set SCRIPT_VERSION=1.0.0

REM 设置窗口标题
title %SCRIPT_NAME% v%SCRIPT_VERSION%

echo %SCRIPT_NAME% v%SCRIPT_VERSION%
echo ==========================================

REM 检查PowerShell版本
where powershell >nul 2>nul
if %errorlevel% neq 0 (
    echo 错误: 未找到PowerShell
    echo 请确保PowerShell 5.1或更高版本已安装
    pause
    exit /b 1
)

REM 获取脚本目录
set SCRIPT_DIR=%~dp0
if "%SCRIPT_DIR%"=="" set SCRIPT_DIR=%CD%\

REM 检查主脚本是否存在
set MAIN_SCRIPT=%SCRIPT_DIR%Main.ps1
if not exist "%MAIN_SCRIPT%" (
    echo 错误: 未找到主脚本: %MAIN_SCRIPT%
    echo 请确保Main.ps1存在于脚本目录中
    pause
    exit /b 1
)

REM 构建PowerShell命令
set POWERSHELL_CMD=powershell -ExecutionPolicy Bypass -NoProfile -NoLogo -File "%MAIN_SCRIPT%" %*

REM 检查是否需要管理员权限
REM 检查参数中是否有-force或需要管理员权限的操作
set NEED_ADMIN=0
echo %* | findstr /i "force install" >nul
if %errorlevel% equ 0 (
    set NEED_ADMIN=1
)

REM 检查当前是否为管理员权限
net session >nul 2>&1
if %errorlevel% equ 0 (
    set IS_ADMIN=1
) else (
    set IS_ADMIN=0
)

REM 如果需要管理员权限但当前不是管理员，则重新启动
if %NEED_ADMIN% equ 1 (
    if %IS_ADMIN% equ 0 (
        echo 某些操作需要管理员权限
        echo 正在请求管理员权限...

        REM 获取当前批处理文件的完整路径
        set "BAT_PATH=%~f0"

        REM 使用PowerShell重新启动为管理员
        powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%BAT_PATH%\" %*\"' -Verb RunAs"

        exit /b 0
    )
)

REM 执行PowerShell脚本
echo 正在执行更新脚本...
echo.

%POWERSHELL_CMD%
set EXIT_CODE=%errorlevel%

echo.
echo ==========================================
if %EXIT_CODE% equ 0 (
    echo 脚本执行完成
) else (
    echo 脚本执行失败，退出代码: %EXIT_CODE%
)

REM 如果是在管理员模式下运行，保持窗口打开
if %IS_ADMIN% equ 1 (
    echo.
    echo 按任意键继续...
    pause >nul
)

exit /b %EXIT_CODE%