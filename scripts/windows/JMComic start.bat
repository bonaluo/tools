@echo off
cd F:\appdata\JMComic
@rem cd /d %~dp0
start /B cmd /c "del /s /q *.log"
start start.exe