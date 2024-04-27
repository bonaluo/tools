@echo off
:: -ndH nd 不保留目录结构和 nH 不创建以主机名称命名的目录
:: -P 输出目录
:: --remote-encoding=GBK 指定服务器编码，为了兼容windows下ftp命令（windows下ftp命令只支持GBK，但wget支持多编码），将服务器编码设置为GBK，
wsl wget ftp://192.168.31.72:2121/Pictures/gallery/owner/YouTube/ ^
--ftp-user=root --ftp-password=root -r -ndH -P ../../temp/ddd/ --remote-encoding=GBK
pause
