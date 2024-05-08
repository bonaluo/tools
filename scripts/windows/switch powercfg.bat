@echo off
chcp 65001
setlocal enabledelayedexpansion

@REM �ֶ�����һ����Դ�ƻ���������Ϊ˯�ߣ�����˯�߼ƻ�
@REM powercfg -duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
@REM powercfg /changename 8c516f6d-1f64-44b9-b56b-d02779604e78 ˯��

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
    if "!schemename!"=="˯��" (
        set findsleep=1
        set sleepguid=!schemestr:~11,36!
        echo sleepguid=!sleepguid!
    )
)

if !findsleep!==0 (
    echo δ�ҵ�˯��ģʽ
    pause
    @REM /b �˳��ű�����cmd
    exit /b
)


@REM ��ȡ��ǰ���˯�߼ƻ�

for /f "delims=" %%a in ('powercfg /getactivescheme') do (
    set "guidstr=%%a"
    set activeguid=!guidstr:~11,36!
)

echo activeguid=!activeguid!

@REM �����ǰ�ƻ���˯�����л�Ϊ������
@REM �����ǰ�ƻ��Ǹ��������л�Ϊ˯��

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