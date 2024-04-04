@echo off
chcp 65001
setlocal enabledelayedexpansion

@REM 手动复制一个睡眠计划
@REM powercfg -duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
@REM powercfg /changename 8c516f6d-1f64-44b9-b56b-d02779604e78 睡眠
@REM 调整睡眠电源计划

set "balanceGuid=381b4222-f694-41f0-9685-ff5bb260df2e"
set "highguid=8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
set "sleepguid=8c516f6d-1f64-44b9-b56b-d02779604e78"

@REM 获取当前活动的睡眠计划

for /f "delims=" %%a in ('powercfg /getactivescheme') do (
    set "guidstr=%%a"
    set activeguid=!guidstr:~11,36!
)

echo activeguid=!activeguid!

@REM 如果当前计划是睡眠则切换为高性能
@REM 如果当前计划是高性能则切换为睡眠

if "!activeguid!"=="!sleepguid!" (
    echo switch sleep to high
    set "targetguid=!highguid!"
) else (
    echo switch high to sleep
    set "targetguid=!sleepguid!"
)

echo targetguid=!targetguid!
powercfg /s "!targetguid!"

pause