@echo off
chcp 65001

setlocal EnableDelayedExpansion

:: 定义文件路径
set "filePath=C:\Users\XFYMT\OneDrive\应用\winget_install.txt"

:: 检查文件是否存在
if not exist %filePath% (
    echo 文件 %filePath% 不存在！
    exit /b 1
)

:: 读取文件并安装软件
for /f "tokens=*" %%a in (%filePath%) do (
    :: 如果要操作for循环中的变量，先赋值给另一个变量
    set "i=%%a"
    :: 忽略空行和以#开头的行
    if not "!i!"=="" if not "!i:~0,1!"=="#" (
        echo 正在安装 "!i!" ...
        winget install -h --accept-package-agreements --authentication-mode silentPreferred "!i!"
    )
)

echo 所有软件安装完成！
pause