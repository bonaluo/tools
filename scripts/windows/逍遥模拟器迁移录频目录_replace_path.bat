@REM ��Ŀ¼Ϊ�����ңģ����¼��������
@REM ���������ƶ���¼����Ŀ¼����ô¼����������Ҳ��Ҫ���


@echo off
chcp 65001
@REM set v=110
@REM set v=120&echo %v%
@REM ������� 110����Ϊv��Ԥ����ģ���ʵ�� set v=120&echo 110�����Ҫʹ���ӳٱ���
setlocal enabledelayedexpansion

set datetime=%date% %time%
echo !datetime!
@REM ��һ�в����ӻ���
set  firstLine=1

for /f "tokens=1,* delims==" %%a in (info.ini) do (
    if "%%a"=="filePath" (
        set "oldPath=%%b"
        echo oldPath=!oldPath!
        @REM ��Ϊ�ļ������ǹ̶���ʽ��yyyyMMddHHmmss.mp4
        set "newPath=%~dp0!oldPath:~-18!"
        @REM ԭ�ļ���·���ָ�����/������\
        set newPath=!newPath:\=/!
        echo newPath=!newPath!
        echo %%a=!newPath!>> info.ini.new
    ) else (
        @REM %%a����ֱ�Ӳ�������Ҫ�ȸ�ֵ������
        set "a=%%a"
        if "!a:~0,1!"=="[" (
            if !firstLine!==0 (
                echo firstLine=0
                @REM echo. echo/ ���е��Ǻ�>>֮�䲻Ҫ�ж����ַ�����ո�
                echo.>> info.ini.new
            ) else (
                echo set firstLine=0
                set firstLine=0
            )
            echo %%a>> info.ini.new
        ) else (
            echo %%a=%%b>> info.ini.new
        )
    )
)

@REM ���� 2024/04/03 18:28:03.68
@REM ����ԭ�ļ�Ϊ yyyyMMddMMhhss ��β�ĸ�ʽ���������ļ�����
move info.ini info.ini.bak.!datetime:~3,4!!datetime:~8,2!!datetime:~11,2!!datetime:~14,2!!datetime:~17,2!!datetime:~20,2!
move info.ini.new info.ini
@REM ���������ļ�����Ӧ�ð�װĿ¼�е������ļ�
copy info.ini info.ini.copy
move info.ini.copy "D:\Program Files\Microvirt\MEmu\videos\info.ini"

pause