# 功能说明：
# 1. 从 porn.txt 文件中匹配包含 "download" 的行，并剪切到同目录下的 download_tmp.txt。
# 2. 剩余内容写回 porn.txt，实现“剪切”效果。
# 3. 自动打开 download_tmp.txt 以便查看。
# 4. 处理中文乱码，确保读写均为 UTF-8。
# 5. 脚本路径：H:\note\tools\scripts\ai\cut_download_lines.ps1
# 使用场景：批量整理和筛选含有 download 关键字的链接或文本。
# ---------------------------------------------
chcp 65001
$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8
$src = "c:\Users\XFYMT\OneDrive\porn\porn.txt"
$tmp = "c:\Users\XFYMT\OneDrive\porn\download_tmp.txt"
$lines = Get-Content $src -Encoding utf8
$match = $lines | Where-Object { $_ -match "download" }
$remain = $lines | Where-Object { $_ -notmatch "download" }
$match | Set-Content $tmp -Encoding utf8
$remain | Set-Content $src -Encoding utf8
Invoke-Item $tmp
