@echo off
setlocal

:: С���ļ�������Զ�̹���֧�� mget *��ʹ��wget�������
:: windows�µ�ftpֻ֧��gbk���룬��˷������Ĵ��������ĳ�GBK��ֹ��������
:: ���� FTP �������ĵ�ַ���˿ڡ��û���������
set "ftp_server=192.168.31.72"
set "ftp_port=2121"
set "ftp_user=root"
set "ftp_pass=root"

:: ����Ҫ����ͱ����Ŀ¼
::set "ftp_directory=Pictures/gallery/owner/YouTube/"
set "ftp_directory=Android/data/tv.danmaku.bili/download"
set "ftp_commands_path=..\..\temp\ftp_commands.txt"
set "file_path=..\..\temp\ftp_file_path.txt"

:: ʹ�� FTP �������ӵ�������
echo open %ftp_server% %ftp_port%> %ftp_commands_path%
echo %ftp_user%>> %ftp_commands_path%
echo %ftp_pass%>> %ftp_commands_path%
echo cd %ftp_directory%>> %ftp_commands_path%
echo ls>> %ftp_commands_path%
echo bye>> %ftp_commands_path%

:: ִ�� FTP ����
ftp -s:%ftp_commands_path%

:: ɾ����ʱ�ļ�
del %ftp_commands_path%
del %file_path%

endlocal
pause
