@echo off
chcp 65001
setlocal enabledelayedexpansion
:: 注意打开 【停用 adb 授权超时功能】，否则 adb 过一会儿会自动断开连接，导致拉取失败

:: 设置日期和时间格式，中文格式日期
set "starttime=%date%%time%"
:: 格式化日期
for /f "tokens=2 delims==" %%a in ('wmic os get localdatetime /value') do set "dt=%%a"
set "year=!dt:~0,4!"
set "month=!dt:~4,2!"
set "day=!dt:~6,2!"
set "hour=!dt:~8,2!"
set "minute=!dt:~10,2!"
set "second=!dt:~12,2!"
set "startTimeFormatted=!year!-!month!-!day! !hour!:!minute!:!second!"
echo 开始时间: !startTimeFormatted!
echo.
:: 时间戳
for /f %%i in ('powershell -Command "(Get-Date -UFormat %%s)"') do set dttimestamp=%%i

:: 创建目标目录
set "targetDir=P:\video\owner\!year!!month!!day!"
echo 创建目标目录为：!targetDir!
mkdir "!targetDir!"
:: 检查并选择设备
adb devices > devices.txt
set "devcount=0"
setlocal enabledelayedexpansion
for /f "skip=1 tokens=1" %%d in (devices.txt) do (
    if not "%%d"=="" (
        set /a devcount+=1
        set "devname[!devcount!]=%%d"
    )
)
del devices.txt
if %devcount%==0 (
    echo 未检测到任何设备，请连接设备后重试。
    pause
    exit /b
)
if %devcount%==1 (
    set "selecteddev=!devname[1]!"
    echo 检测到设备: !selecteddev!
) else (
    echo 检测到多个设备：
    for /l %%i in (1,1,%devcount%) do echo %%i. !devname[%%i]!
    set /p devsel=请选择设备编号：
    set "selecteddev=!devname[%devsel%]!"
    echo 已选择设备: !selecteddev!
)

set "sourceDir=/sdcard/Pictures/gallery/owner/ddd1/"
@REM set "sourceDir=/sdcard/Download/MiShare/"
@REM set "sourceDir=/sdcard/Pictures/gallery/owner/YouTube/"
:: 使用ADB拉取文件
:: temp.txt 是utf-8编码，batch读入之后乱码，batch脚本的编码改为 UTF-8 同时脚本开头加上 chcp 65001 即可解决
adb -s !selecteddev! shell "cd !sourceDir! && ls" > temp.txt

:: 计算进度
set total=0
for /f %%f in (temp.txt) do (
    if not "%%f"==".nomedia" (
        set /a total+=1
    )
)
echo 源目录文件总数: !total! (已排除 .nomedia 文件)
echo.
set count=0
for /f %%f in (temp.txt) do (
    if not "%%f"==".nomedia" (
        set /a count+=1
        echo [!count!/!total!] 正在拉取: %%f
        adb -s !selecteddev! pull -a -z any "!sourceDir!%%f" "!targetDir!\%%f"
        echo.
    ) else (
        echo 跳过文件: %%f
    )
)
echo 完成！共拉取 !count!/!total! 个文件

:: 清理临时文件
del temp.txt

echo 文件已成功拉取到目录：!targetDir!

:: 打印拉取耗时
echo.
set "endtime=%date%%time%"
for /f "tokens=2 delims==" %%a in ('wmic os get localdatetime /value') do set "et=%%a"
set "eyear=!et:~0,4!"
set "emonth=!et:~4,2!"
set "eday=!et:~6,2!"
set "ehour=!et:~8,2!"
set "eminute=!et:~10,2!"
set "esecond=!et:~12,2!"
set "endTimeFormatted=!eyear!-!emonth!-!eday! !ehour!:!eminute!:!esecond!"
echo 结束时间: !endTimeFormatted!
echo 时间范围: !startTimeFormatted! ~ !endTimeFormatted!
echo.

for /f %%i in ('powershell -Command "(Get-Date -UFormat %%s)"') do set ettimestamp=%%i
:: 可以使用 PowerShell 进行更准确的计算
set "Calculation=%ettimestamp% - %dttimestamp%"
for /f %%i in ('powershell "%Calculation%"') do set "result=%%i"

:: 时分秒阅读更清晰
set /a "costtimeh=result / 3600"
set /a "remainingSeconds=result %% 3600"
set /a "costtimem=remainingSeconds / 60"
set /a "costtimes=remainingSeconds %% 60"
echo 拉取耗时：%costtimeh%h%costtimem%m%costtimes%s (%result%s)
adb -s !selecteddev! shell rm -rf !sourceDir!
:: 删除源文件
adb shell rm -rf !sourceDir!
echo 已删除全部文件

set /p ifopen=是否打开文件夹（直接回车跳过）？(y/n) 
if /i "%ifopen%"=="y" ( 
    goto open
 ) else (
    goto end
 )

:open
explorer !targetDir!

:end