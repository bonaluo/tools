$ErrorActionPreference = "Stop"

# 动态获取 Sunshine 安装目录
$installDir = $null
try {
    # 首先尝试从 Get-Command 获取实际安装路径
    $sunshineCmd = Get-Command sunshine.exe -ErrorAction SilentlyContinue
    if ($sunshineCmd) {
        $installDir = Split-Path $sunshineCmd.Source
    }
} catch {}

Write-Host "Sunshine 安装目录: $installDir"

$tempDir = "$env:TEMP\sunshine-update"
$githubApiUrl = "https://api.github.com/repos/LizardByte/Sunshine/releases/latest"
# GitHub token 用于提高 API 速率限制（可选，若未设置则使用无认证请求）
# 可在环境变量 GITHUB_TOKEN 中设置，或在此硬编码
$githubToken = $env:GITHUB_TOKEN

# 创建临时目录
if (!(Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }

# 检查本地版本（尝试读取可执行文件的文件版本信息）
$localVersion = ""
$exePath = Join-Path $installDir "sunshine.exe"
if (Test-Path $exePath) {
    try {
        $fv = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
        $localVersion = $fv.ProductVersion
    } catch {}
}
Write-Host "本地版本: $localVersion"

Write-Host "正在查询最新版本..."
# 构造请求头：自定义 User-Agent 和可选的 GitHub token
$headers = @{ 'User-Agent' = 'sunshine-update-script' }
if ($githubToken) {
    $headers['Authorization'] = "token $githubToken"
    Write-Host "使用 GitHub token 进行认证"
}

# 获取最新版本，带重试机制
$maxRetries = 3
$retryCount = 0
$latestJson = $null
while ($retryCount -lt $maxRetries) {
    try {
        $latestJson = Invoke-RestMethod -Uri $githubApiUrl -Headers $headers -ErrorAction Stop
        break
    } catch {
        $retryCount++
        if ($retryCount -ge $maxRetries) {
            Write-Host "错误：无法获取最新版本信息，已重试 $maxRetries 次。"
            Write-Host "错误详情: $($_.Exception.Message)"
            Write-Host ""
            Write-Host "解决方案："
            Write-Host "  1. 等待几分钟后重试（GitHub API 有速率限制）"
            Write-Host "  2. 设置 GitHub token 以获得更高的请求限制："
            Write-Host "     set GITHUB_TOKEN=your_personal_access_token"
            Write-Host "     然后重新运行此脚本"
            Remove-Item -Recurse -Force $tempDir
            Read-Host -Prompt "按回车键退出"
            exit 1
        }
        Write-Host "查询失败（第 $retryCount/$maxRetries 次），等待 5 秒后重试..."
        Start-Sleep -Seconds 5
    }
}

$latestVersion = $latestJson.tag_name
Write-Host "最新版本: $latestVersion"

# 在 assets 中查找 Windows installer (.exe)
# 优先匹配 Windows + .exe 的组合，避免选中 Linux/Debian 包
$asset = $latestJson.assets | Where-Object { 
    $_.name -match "(?i)windows.*\.exe$|\.exe$.*windows" -or $_.name -match "(?i)windows-amd64.*\.exe$"
} | Select-Object -First 1

# 如果没找到，退回到宽松匹配
if (-not $asset) {
    $asset = $latestJson.assets | Where-Object { 
        $_.name -match "(?i)installer.*exe$|exe$.*installer" 
    } | Select-Object -First 1
}

if (-not $asset) {
    Write-Host "未在 release 中找到 Windows 安装程序 (.exe)，脚本退出。"
    Write-Host "可用的 assets："
    $latestJson.assets | ForEach-Object { Write-Host "  - $($_.name)" }
    Remove-Item -Recurse -Force $tempDir
    Read-Host -Prompt "按回车键退出"
    exit 1
}

$assetName = $asset.name
$downloadUrl = $asset.browser_download_url
Write-Host "发现安装包: $assetName"

# 简单版本比较：如果本地版本字符串包含最新版本号（去掉前导 v），则认为已是最新
$verNoV = $latestVersion.TrimStart('v')
if ($localVersion -and $localVersion.Contains($verNoV)) {
    Write-Host "已是最新版本，无需更新。"
    Remove-Item -Recurse -Force $tempDir
    Read-Host -Prompt "按回车键退出"
    exit 0
}

# 在文件名中插入版本号（如果可用），例如 sunshine-installer.exe -> sunshine-installer-2026.105.231052.exe
$base = [System.IO.Path]::GetFileNameWithoutExtension($assetName)
$ext = [System.IO.Path]::GetExtension($assetName)
$verSuffix = ''
if ($script:verNoV) { $verSuffix = "-$script:verNoV" } elseif ($verNoV) { $verSuffix = "-$verNoV" }
$fileNameVersioned = "$base$verSuffix$ext"
# 下载 installer
$installerPath = Join-Path $tempDir $fileNameVersioned
Write-Host "下载: $downloadUrl"

Function Download-File($url, $outPath) {
    # 优先使用 IDM（Internet Download Manager），记得添加idm home到 PATH 中
    $idm = $null
    if (Get-Command 'IDMan.exe' -ErrorAction SilentlyContinue) {
        $idm = (Get-Command 'IDMan.exe').Source
    }

    function Wait-ForFileComplete($path, $timeoutSec) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $prevSize = -1
        $stable = 0
        while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
            if (Test-Path $path) {
                try {
                    $size = (Get-Item $path).Length
                } catch {
                    $size = -1
                }
                if ($size -gt 0 -and $size -eq $prevSize) {
                    $stable++
                } else {
                    $stable = 0
                }
                if ($stable -ge 2) { return $true }
                $prevSize = $size
            }
            Start-Sleep -Seconds 2
        }
        return $false
    }

    if ($idm) {
        Write-Host "检测到 IDM: $idm，使用 IDM 下载..."
        $outDir = Split-Path $outPath -Parent
        $fileName = Split-Path $outPath -Leaf
        if (!(Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
        $args = @('/d', $url, '/p', $outDir, '/f', $fileName, '/n')
        try {
            $proc = Start-Process -FilePath $idm -ArgumentList $args -PassThru -NoNewWindow -ErrorAction Stop
        } catch {
            Write-Host "启动 IDM 失败：$($_.Exception.Message)，回退到其它下载方式。"
            $proc = $null
        }
        if ($proc) {
            # 等待文件下载完成（最多 10 分钟）
            $ok = Wait-ForFileComplete $outPath 600
            if ($ok) { return $true } else { Write-Host "IDM 下载等待超时或失败，回退到其它方法。" }
        }
    } else {
        Write-Host "未检测到 IDM，使用其他下载方式。"
    }

    # 优先使用 curl.exe（系统自带或已安装的 aria2/curl）
    if (Get-Command 'curl.exe' -ErrorAction SilentlyContinue) {
        Write-Host "使用 curl.exe 下载..."
        $args = @('-L', '--retry', '3', '--connect-timeout', '10', '-o', $outPath, $url)
        $proc = Start-Process -FilePath 'curl.exe' -ArgumentList $args -Wait -PassThru -NoNewWindow -ErrorAction SilentlyContinue
        if ($proc -and $proc.ExitCode -eq 0) { return $true }
        Write-Host "curl.exe 下载失败: ExitCode $($proc.ExitCode)"
    }

    # 然后尝试使用 BITS（可断点续传，适合较大文件）
    if (Get-Command 'Start-BitsTransfer' -ErrorAction SilentlyContinue) {
        Write-Host "使用 Start-BitsTransfer 下载..."
        try {
            Start-BitsTransfer -Source $url -Destination $outPath -ErrorAction Stop
            return $true
        } catch {
            Write-Host "BITS 下载失败：$($_.Exception.Message)"
        }
    }

    # 最后回退到 Invoke-WebRequest
    Write-Host "使用 Invoke-WebRequest 下载（回退）..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $outPath -Headers $headers -UseBasicParsing
        return $true
    } catch {
        Write-Host "Invoke-WebRequest 失败: $($_.Exception.Message)"
        return $false
    }
}

$success = Download-File $downloadUrl $installerPath
if (-not $success) {
    Write-Host "下载失败，脚本退出。"
    Remove-Item -Recurse -Force $tempDir
    Read-Host -Prompt "按回车键退出"
    exit 1
}

Write-Host "下载完成: $installerPath"

# 尝试静默安装的常见参数列表
$silentFlagsList = @('/S','/VERYSILENT','/SILENT','/quiet','/qn')
$installed = $false
foreach ($flag in $silentFlagsList) {
    Write-Host "尝试静默安装参数: $flag"
    try {
        $proc = Start-Process -FilePath $installerPath -ArgumentList $flag -Wait -PassThru -ErrorAction Stop
        if ($proc.ExitCode -eq 0) {
            Write-Host "静默安装成功（参数: $flag）。"
            $installed = $true
            break
        } else {
            Write-Host "安装返回代码: $($proc.ExitCode)（参数: $flag），尝试下一个参数。"
        }
    } catch {
        Write-Host "使用参数 $flag 启动安装器失败：$($_.Exception.Message)"
    }
}

if (-not $installed) {
    Write-Host "未能以常见静默参数完成安装，将以交互方式运行安装程序。"
    Start-Process -FilePath $installerPath
    Write-Host "请按照安装程序完成安装。"
} else {
    Write-Host "安装已完成。"
}

# 清理临时文件
Remove-Item -Recurse -Force $tempDir

Write-Host "更新/安装流程结束。"
Read-Host -Prompt "按回车键退出"
