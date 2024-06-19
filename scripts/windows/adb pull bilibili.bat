@echo off
chcp 65001
setlocal enabledelayedexpansion
:: 注意打开 【停用 adb 授权超时功能】，否则 adb 过一会儿会自动断开连接，导致拉取失败

:: 设置日期和时间格式
for /f "tokens=2 delims==" %%a in ('wmic os get localdatetime /value') do set "dt=%%a"
::set "year=!dt:~0,4!"
::set "month=!dt:~4,2!"
::set "day=!dt:~6,2!"
::set "hour=!dt:~8,2!"
::set "minute=!dt:~10,2!"
::set "second=!dt:~12,2!"
for /f %%i in ('powershell -Command "(Get-Date -UFormat %%s)"') do set dttimestamp=%%i

:: 创建目标目录
set "targetDir=F:\video\bilibili\bilibili_download_!dt:~0,4!!dt:~4,2!!dt:~6,2!!dt:~8,2!!dt:~10,2!!dt:~12,2!"
echo !targetDir!
mkdir "!targetDir!"
set "sourceDir=/sdcard/Android/data/tv.danmaku.bili/download/"

:: 使用ADB拉取文件
:: temp.txt 是utf-8编码，batch读入之后乱码，batch脚本的编码改为 UTF-8 同时脚本开头加上 chcp 65001 即可解决
adb shell "cd %sourceDir% && ls" > temp.txt

:: 计算进度
set total=0
for /f %%f in (temp.txt) do (
    set /a total+=1
)
set count=0
for /f %%f in (temp.txt) do (
    echo !count!/!total!
    adb pull -a -z any "%sourceDir%%%f" "!targetDir!\%%f"
    set /a count+=1
)
echo !count!/!total!

:: 清理临时文件
del temp.txt

echo 文件已成功拉取到目录：!targetDir!

:: 打印拉取耗时
for /f "tokens=2 delims==" %%a in ('wmic os get localdatetime /value') do set "et=%%a"
for /f %%i in ('powershell -Command "(Get-Date -UFormat %%s)"') do set ettimestamp=%%i

:: 可以使用 PowerShell 进行更准确的计算
echo %et:~0,18%-%dt:~0,18%
set "Calculation=%ettimestamp% - %dttimestamp%"
for /f %%i in ('powershell "%Calculation%"') do set "result=%%i"
echo Result: %result%s

:: 时分秒阅读更清晰
set /a "costtimeh=result / 3600"
set /a "remainingSeconds=result %% 3600"
set /a "costtimem=remainingSeconds / 60"
set /a "costtimes=remainingSeconds %% 60"
echo 拉取耗时：%costtimeh%h%costtimem%m%costtimes%s

set /p ifopen=是否打开文件夹（直接回车跳过）？(y/n) 
if /i "%ifopen%"=="y" ( 
    goto open
 ) else (
    goto end
 )

:open
explorer !targetDir!

:end