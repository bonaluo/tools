@echo off
setlocal enabledelayedexpansion
:: ע��� ��ͣ�� adb ��Ȩ��ʱ���ܡ������� adb ��һ������Զ��Ͽ����ӣ�������ȡʧ��

:: �������ں�ʱ���ʽ
for /f "tokens=2 delims==" %%a in ('wmic os get localdatetime /value') do set "dt=%%a"
set "year=!dt:~0,4!"
set "month=!dt:~4,2!"
set "day=!dt:~6,2!"
set "hour=!dt:~8,2!"
set "minute=!dt:~10,2!"
set "second=!dt:~12,2!"

:: ����Ŀ��Ŀ¼
set "targetDir=F:\video\bilibili\bilibili_download_!year!!month!!day!!hour!!minute!!second!"
mkdir "!targetDir!"

:: ʹ��ADB��ȡ�ļ�
adb shell "cd /sdcard/Android/data/tv.danmaku.bili/download/ && ls" > temp.txt
for /f %%f in (temp.txt) do (
    adb pull "/sdcard/Android/data/tv.danmaku.bili/download/%%f" "!targetDir!\%%f"
)

:: ������ʱ�ļ�
del temp.txt

echo �ļ��ѳɹ���ȡ��Ŀ¼��!targetDir!

pause