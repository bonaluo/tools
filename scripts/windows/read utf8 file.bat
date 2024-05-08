@echo off 
@REM 读取utf8文件的脚本本身的编码需要时utf8，其次 chcp 65001
chcp 65001
for /f %%f in (..\..\temp\中文文件.txt) do (
@REM for /f %%f in (temp.txt) do (
    echo %%f
)
pause
