@echo off
chcp 65001
setlocal enabledelayedexpansion

@REM 手动复制一个电源计划，并改名为睡眠，调整睡眠计划
@REM powercfg -duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
@REM powercfg /changename 8c516f6d-1f64-44b9-b56b-d02779604e78 睡眠

set "balanceGuid=381b4222-f694-41f0-9685-ff5bb260df2e"
set "highguid=8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
set "sleepguid=8c516f6d-1f64-44b9-b56b-d02779604e78"

set findsleep=0
for /f "skip=3 delims=" %%i in ('powercfg /l') do (
    @REM echo ------------------------------------------
    @REM echo %%i
    set schemestr=%%i
    set schemename=!schemestr:~50,2!
    @REM echo !schemename!
    if "!schemename!"=="睡眠" (
        set findsleep=1
        set sleepguid=!schemestr:~11,36!
        echo sleepguid=!sleepguid!
    )
)

if !findsleep!==0 (
    echo 未找到睡眠模式
    pause
    @REM /b 退出脚本而非cmd
    exit /b
)


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