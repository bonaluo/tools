@echo off
REM 此脚本使用copilot生成
setlocal enabledelayedexpansion

REM 遍历 D:\work 目录下的每个子目录
for /d %%i in (D:\work\*) do (
    cd %%i
    if exist .git (
        echo 更新 %%i 中的 Git 仓库...
        REM git pull
        git fetch
    )
    cd ..
)

echo 完成所有更新！
pause
