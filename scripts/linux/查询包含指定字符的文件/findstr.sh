#/bin/bash

# 查找当前目录下最近创建的10个文件夹（不含子目录），并递归查找其中包含"英语播客"的entry.json
find . -maxdepth 1 -type d ! -name "." -printf "%C+ %p\n" | sort -r | head -n 10 | awk '{print $2}' | xargs -I {} find {} -name "entry.json" | xargs grep -l "英语播客"