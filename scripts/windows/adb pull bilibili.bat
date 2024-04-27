@echo off
setlocal enabledelayedexpansion
:: 注意打开 【停用 adb 授权超时功能】，否则 adb 过一会儿会自动断开连接，导致拉取失败

:: 设置日期和时间格式
for /f "tokens=2 delims==" %%a in ('wmic os get localdatetime /value') do set "dt=%%a"
set "starttime=!dt:~0,4!-!dt:~4,2!-!dt:~6,2! !dt:~8,2!:!dt:~10,2!:!dt:~12,2!"
::set "year=!dt:~0,4!"
::set "month=!dt:~4,2!"
::set "day=!dt:~6,2!"
::set "hour=!dt:~8,2!"
::set "minute=!dt:~10,2!"
::set "second=!dt:~12,2!"

:: 创建目标目录
set "targetDir=F:\video\bilibili\bilibili_download_!starttime!"
mkdir "!targetDir!"

:: 使用ADB拉取文件
:: temp.txt 是utf-8编码，batch读入之后乱码
adb shell "cd /sdcard/Android/data/tv.danmaku.bili/download/ && ls" > temp.txt
for /f %%f in (temp.txt) do (
    adb pull "/sdcard/Android/data/tv.danmaku.bili/download/%%f" "!targetDir!\%%f"
)

:: 清理临时文件
del temp.txt

echo 文件已成功拉取到目录：!targetDir!

:: 打印拉取耗时
for /f "tokens=2 delims==" %%a in ('wmic os get localdatetime /value') do set "endtime=%%a"
set "endtime=!endtime:~0,4!-!endtime:~4,2!-!endtime:~6,2! !endtime:~8,2!:!endtime:~10,2!:!endtime:~12,2!"
echo !starttime!~!endtime!

pause