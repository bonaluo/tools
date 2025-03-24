@echo off
@chcp 65001
echo *****@authorxiafangyuan********
echo *******@date2019-7-19**********
REM ********************************

goto menu
:select
set /p choice=请输入选择：
if %choice% == 1 goto menu
if %choice% == 2 goto dir
REM list all the pictrues belong to pixiv
:dir
REM dir *_p?.*
REM dir *_p??.*
dir *_p???.*
goto menu
REM show the menu
:menu
echo *******************************
echo *1.菜单
echo *2.list pixiv
echo *3.移动到pixiv文件夹
echo *5.退出
echo *******************************
goto select
:move
move *_p???.* "G:\图片\Pixiv\"
goto menu



pause