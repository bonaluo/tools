$ErrorActionPreference = "Stop"

# 检查并选择设备，解释：列出所有设备，跳过第一行，过滤出结尾为"device"的行，提取设备ID
# 只有一个设备时列出设备失败问题，当只有一个设备时，$devices 就是字符串，$selecteddev = $devices[0] 取的是第一个字符
# $devices = @( ...你的管道代码... ) 是为了把结果强制存成数组
$devices = @(& adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "device$" } | ForEach-Object { ($_ -split '\s+')[0] })
if ($devices.Count -eq 0) {
    Write-Host "未检测到任何设备，请连接设备后重试。"
    Pause
    exit
}
if ($devices.Count -eq 1) {
    $selecteddev = $devices[0]
    Write-Host "检测到设备: $selecteddev"
} else {
    Write-Host "检测到多个设备："
    for ($i=0; $i -lt $devices.Count; $i++) {
        Write-Host "$($i+1). $($devices[$i])"
    }
    $devsel = Read-Host "请选择设备编号"
    $selecteddev = $devices[$devsel-1]
    Write-Host "已选择设备: $selecteddev"
}

# 设置日期和时间格式
$startTime = Get-Date
$dt = $startTime.ToString('yyyyMMddHHmmss')
$startTimeFormatted = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
Write-Host "开始时间: $startTimeFormatted"
Write-Host ""
$dttimestamp = [int][double]::Parse((Get-Date -UFormat %s))

# 创建目标目录
$targetDir = "P:\video\bilibili\bilibili_download_$dt"
Write-Host "创建目标目录：$targetDir"
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
$sourceDir = "/sdcard/Android/data/tv.danmaku.bili/download"
$count = 100

# 统计源目录文件总数
$cmdTotal = "cd $sourceDir && ls -l | awk '{print `$8}'"
$allFiles = & adb -s $selecteddev shell $cmdTotal | Where-Object { $_.Trim() -ne "" }
$allTotal = $allFiles.Count
Write-Host "源目录文件总数: $allTotal"

# 使用ADB拉取文件
$tempFile = "$env:TEMP\bili_temp.txt"
# `$8是转义的$符号
$cmd = "cd $sourceDir && ls -ltr | head -n $count | awk '{print `$8}'"
& adb -s $selecteddev shell $cmd | Out-File -Encoding utf8 $tempFile

# 计算进度
$files = Get-Content $tempFile | Where-Object { $_.Trim() -ne "" }
$total = $files.Count
$count = 0
Write-Host "本次待拉取文件数: $total"
foreach ($f in $files) {
    Write-Host "$count/$total"
    & adb -s $selecteddev pull -a -z any "$sourceDir/$f/" "$targetDir/$f"
    $count++
    & Write-Host "已拉取 $sourceDir/$f 到 $targetDir/$f"
    & adb -s $selecteddev shell "rm -rf '$sourceDir/$f'"
    & Write-Host "已删除 $sourceDir$f"
}
Write-Host "$count/$total"
Remove-Item $tempFile -Force

Write-Host "文件已成功拉取到目录：$targetDir"

# 打印拉取耗时
Write-Host ""
$endTime = Get-Date
$endTimeFormatted = $endTime.ToString('yyyy-MM-dd HH:mm:ss')
Write-Host "结束时间: $endTimeFormatted"
Write-Host "时间范围: $startTimeFormatted ~ $endTimeFormatted"
Write-Host ""

$ettimestamp = [int][double]::Parse((Get-Date -UFormat %s))
$result = $ettimestamp - $dttimestamp
$costtimeh = [math]::Floor($result / 3600)
$remainingSeconds = $result % 3600
$costtimem = [math]::Floor($remainingSeconds / 60)
$costtimes = $remainingSeconds % 60
Write-Host "拉取耗时：${costtimeh}h${costtimem}m${costtimes}s ($result`s)"

$ifopen = Read-Host "是否打开文件夹（直接回车跳过）？(y/n)"
if ($ifopen -eq 'y') {
    Start-Process explorer $targetDir
}
