@echo off
:: -ndH nd ������Ŀ¼�ṹ�� nH ����������������������Ŀ¼
:: -P ���Ŀ¼
:: --remote-encoding=GBK ָ�����������룬Ϊ�˼���windows��ftp���windows��ftp����ֻ֧��GBK����wget֧�ֶ���룩������������������ΪGBK��
wsl wget ftp://192.168.31.72:2121/Pictures/gallery/owner/YouTube/ ^
--ftp-user=root --ftp-password=root -r -ndH -P ../../temp/ddd/ --remote-encoding=GBK
pause
