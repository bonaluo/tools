@echo off
echo 压缩文件：%1

ffmpeg -i %1 -ss 00:00:03 -c:v h264_qsv -crf 23 -preset fast output.mp4
pause