@echo off
chcp 65001  
:: 注意打开 【停用 adb 授权超时功能】，否则 adb 过一会儿会自动断开连接，导致拉取失败  
@REM 因为我在创建的时候提到使用同名的ps1文件，因此%~dpn0表示当前脚本的路径和名称但不带扩展名
powershell -ExecutionPolicy Bypass -File "%~dpn0.ps1"