@echo off
setlocal enabledelayedexpansion
:: ע��� ��ͣ�� adb ��Ȩ��ʱ���ܡ������� adb ��һ������Զ��Ͽ����ӣ�������ȡʧ��

:: �������ں�ʱ���ʽ
for /f "tokens=2 delims==" %%a in ('wmic os get localdatetime /value') do set "dt=%%a"
set "starttime=!dt:~0,4!-!dt:~4,2!-!dt:~6,2! !dt:~8,2!:!dt:~10,2!:!dt:~12,2!"
::set "year=!dt:~0,4!"
::set "month=!dt:~4,2!"
::set "day=!dt:~6,2!"
::set "hour=!dt:~8,2!"
::set "minute=!dt:~10,2!"
::set "second=!dt:~12,2!"

:: ����Ŀ��Ŀ¼
set "targetDir=F:\video\bilibili\bilibili_download_!starttime!"
mkdir "!targetDir!"

:: ʹ��ADB��ȡ�ļ�
:: temp.txt ��utf-8���룬batch����֮������
adb shell "cd /sdcard/Android/data/tv.danmaku.bili/download/ && ls" > temp.txt
for /f %%f in (temp.txt) do (
    adb pull "/sdcard/Android/data/tv.danmaku.bili/download/%%f" "!targetDir!\%%f"
)

:: ������ʱ�ļ�
del temp.txt

echo �ļ��ѳɹ���ȡ��Ŀ¼��!targetDir!

:: ��ӡ��ȡ��ʱ
for /f "tokens=2 delims==" %%a in ('wmic os get localdatetime /value') do set "endtime=%%a"
set "endtime=!endtime:~0,4!-!endtime:~4,2!-!endtime:~6,2! !endtime:~8,2!:!endtime:~10,2!:!endtime:~12,2!"
echo !starttime!~!endtime!

pause