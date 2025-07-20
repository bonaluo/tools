@echo off
chcp 65001
setlocal enabledelayedexpansion

REM ===================== 日期与目录准备 =====================  
REM 获取当前时间  
for /f "tokens=2 delims==" %%a in ('wmic os get localdatetime /value') do set "dt=%%a"
set "year=!dt:~0,4!"
set "month=!dt:~4,2!"
set "day=!dt:~6,2!"
set "hour=!dt:~8,2!"
set "minute=!dt:~10,2!"
set "second=!dt:~12,2!"
set "starttime=!year!年!month!月!day!日!hour!点!minute!分!second!秒"

REM 目标目录
set "targetDir=P:\video\owner\!year!-!month!-!day!"
if not exist "!targetDir!" mkdir "!targetDir!"

REM ===================== FTP 服务器信息 =====================  
set "ftp_server=10.31.0.95"
set "ftp_port=2121"
set "ftp_user=root"
set "ftp_pass=root"
set "ftp_directory=Pictures/gallery/owner/ddd"

REM ===================== 使用 WinSCP 下载文件 =====================  
set "winscp_path=C:\Users\XFYMT\AppData\Local\Programs\WinSCP\WinSCP.exe"
set "winscp_script=%TEMP%\winscp_ftp_script.txt"

REM 生成 WinSCP 脚本  
(
    echo option batch abort  
    echo option confirm off  
    echo open ftp://%ftp_user%:%ftp_pass%@%ftp_server%:%ftp_port%  
    echo lcd "!targetDir!"  
    echo cd /%ftp_directory%  
    echo mget *  
    echo exit  
) > "%winscp_script%"

echo 正在使用 WinSCP 批量下载文件...  
"%winscp_path%" /script="%winscp_script%" /log="%TEMP%\winscp_ftp_log.txt"

REM 统计下载文件数量  
set "count=0"
for %%f in ("%targetDir%"\*) do (
    set /a count+=1
)

REM ===================== 记录结束时间 =====================  
for /f "tokens=2 delims==" %%a in ('wmic os get localdatetime /value') do set "et=%%a"
set "endtime=!et:~0,4!年!et:~4,2!月!et:~6,2!日!et:~8,2!点!et:~10,2!分!et:~12,2!秒"

REM ===================== 计算耗时 =====================  
REM 仅计算秒数差值，适用于同一天内  
set /a startsec=!hour!*3600+!minute!*60+!second!
set /a endsec=!et:~8,2!*3600+!et:~10,2!*60+!et:~12,2!
set /a result=endsec-startsec
if !result! lss 0 set /a result+=86400
set /a costtimeh=result / 3600
set /a remainingSeconds=result %% 3600
set /a costtimem=remainingSeconds / 60
set /a costtimes=remainingSeconds %% 60

REM ===================== 输出信息 =====================  
echo.
echo 下载开始~结束时间：!starttime! ~ !endtime!
echo 下载时长：!costtimeh!h!costtimem!min!costtimes!sec
echo.

echo 下载完成，共下载了 !count! 个文件到目录：!targetDir!
@REM pause
endlocal
