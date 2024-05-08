@echo off
setlocal

:: 小米文件管理器远程管理不支持 mget *，使用wget进行替代
:: windows下的ftp只支持gbk编码，因此服务器的传输编码请改成GBK防止中文乱码
:: 设置 FTP 服务器的地址、端口、用户名和密码
set "ftp_server=192.168.31.72"
set "ftp_port=2121"
set "ftp_user=root"
set "ftp_pass=root"

:: 设置要进入和保存的目录
::set "ftp_directory=Pictures/gallery/owner/YouTube/"
set "ftp_directory=Android/data/tv.danmaku.bili/download"
set "ftp_commands_path=..\..\temp\ftp_commands.txt"
set "file_path=..\..\temp\ftp_file_path.txt"

:: 使用 FTP 命令连接到服务器
echo open %ftp_server% %ftp_port%> %ftp_commands_path%
echo %ftp_user%>> %ftp_commands_path%
echo %ftp_pass%>> %ftp_commands_path%
echo cd %ftp_directory%>> %ftp_commands_path%
echo ls>> %ftp_commands_path%
echo bye>> %ftp_commands_path%

:: 执行 FTP 命令
ftp -s:%ftp_commands_path%

:: 删除临时文件
del %ftp_commands_path%
del %file_path%

endlocal
pause
