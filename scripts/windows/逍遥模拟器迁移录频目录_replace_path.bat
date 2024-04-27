@REM 此目录为存放逍遥模拟器录屏的数据
@REM 如果变更（移动）录屏的目录，那么录屏索引数据也需要变更


@echo off
chcp 65001
@REM set v=110
@REM set v=120&echo %v%
@REM 输出的是 110，因为v是预处理的，其实是 set v=120&echo 110，因此要使用延迟变量
setlocal enabledelayedexpansion

set datetime=%date% %time%
echo !datetime!
@REM 第一行不增加换行
set  firstLine=1

for /f "tokens=1,* delims==" %%a in (info.ini) do (
    if "%%a"=="filePath" (
        set "oldPath=%%b"
        echo oldPath=!oldPath!
        @REM 因为文件名称是固定格式的yyyyMMddHHmmss.mp4
        set "newPath=%~dp0!oldPath:~-18!"
        @REM 原文件的路径分隔符是/而不是\
        set newPath=!newPath:\=/!
        echo newPath=!newPath!
        echo %%a=!newPath!>> info.ini.new
    ) else (
        @REM %%a不能直接操作，需要先赋值给变量
        set "a=%%a"
        if "!a:~0,1!"=="[" (
            if !firstLine!==0 (
                echo firstLine=0
                @REM echo. echo/ 换行但是和>>之间不要有多于字符比如空格
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

@REM 周三 2024/04/03 18:28:03.68
@REM 备份原文件为 yyyyMMddMMhhss 结尾的格式，再用新文件覆盖
move info.ini info.ini.bak.!datetime:~3,4!!datetime:~8,2!!datetime:~11,2!!datetime:~14,2!!datetime:~17,2!!datetime:~20,2!
move info.ini.new info.ini
@REM 复制配置文件覆盖应用安装目录中的配置文件
copy info.ini info.ini.copy
move info.ini.copy "D:\Program Files\Microvirt\MEmu\videos\info.ini"

pause