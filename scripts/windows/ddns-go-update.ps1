$ErrorActionPreference = "Stop"

# 设置路径和URL
$installDir = "C:\Program Files\ddns-go"
$tempDir = "$env:TEMP\ddns-go-update"
$githubApiUrl = "https://api.github.com/repos/jeessy2/ddns-go/releases/latest"

# 创建临时目录
if (!(Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }

# 检查本地版本
$localVersion = ""
$exePath = Join-Path $installDir "ddns-go.exe"
if (Test-Path $exePath) {
    try {
        $localVersion = & $exePath -v
        # $localVersion = "v6.9.2" # 用于测试升级
    } catch {}
}
Write-Host "本地版本: $localVersion"

# 获取最新版本信息
Write-Host "正在查询最新版本..."
$latestJsonPath = Join-Path $tempDir "latest.json"
Invoke-WebRequest -Uri $githubApiUrl -OutFile $latestJsonPath
$latestJson = Get-Content $latestJsonPath | ConvertFrom-Json
$latestVersion = $latestJson.tag_name
Write-Host "最新版本: $latestVersion"

# 比较版本
if ($localVersion -eq $latestVersion) {
    Write-Host "已是最新版本，无需更新。"
    Remove-Item -Recurse -Force $tempDir
    Pause
    exit
}


if ([string]::IsNullOrEmpty($localVersion)) {
    Write-Host "首次安装 ddns-go $latestVersion"
} else {
    Write-Host "升级 ddns-go 从 $localVersion 到 $latestVersion"
    Write-Host "卸载旧服务..."
    & $exePath -s uninstall
}

# 构造下载链接（第一个版本号带v，第二个不带v）
$verWithV = $latestVersion
$verNoV = $latestVersion.TrimStart('v')
$downloadUrl = "https://github.com/jeessy2/ddns-go/releases/download/$verWithV/ddns-go_${verNoV}_windows_x86_64.zip"
$tarPath = Join-Path $tempDir "ddns-go.zip"
Write-Host "下载: $downloadUrl"
Invoke-WebRequest -Uri $downloadUrl -OutFile $tarPath

# 解压
Write-Host "正在解压..."
tar -xf $tarPath -C $tempDir

# 查找解压后的 ddns-go.exe
$extractedExe = Get-ChildItem -Path $tempDir -Filter "ddns-go.exe" -Recurse | Select-Object -First 1
if (-not $extractedExe) {
    Write-Host "未找到解压后的 ddns-go.exe，脚本退出。"
    Remove-Item -Recurse -Force $tempDir
    Pause
    exit 1
}


# 拷贝到安装目录
if (!(Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir | Out-Null }
Copy-Item -Force $extractedExe.FullName $exePath

# 安装服务
Write-Host "安装服务..."
& $exePath -s install

# 清理临时文件
Remove-Item -Recurse -Force $tempDir

Write-Host "更新/安装完成！"
Pause
