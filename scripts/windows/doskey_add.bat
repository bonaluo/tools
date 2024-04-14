@echo off
doskey cd=cd /d $*

echo 列出所有已安装的快捷方式
doskey /macros:all
pause
