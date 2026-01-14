$ErrorActionPreference = "Stop"

# 动态获取 Sunshine 安装目录
$installDir = $null
$isInstalled = $false
try {
    # 首先尝试从 Get-Command 获取实际安装路径
    $sunshineCmd = Get-Command sunshine.exe -ErrorAction SilentlyContinue
    if ($sunshineCmd) {
        $installDir = Split-Path $sunshineCmd.Source
        $isInstalled = $true
    }
} catch {}

# 如果通过 PATH 找不到，尝试检查常见的安装位置
if (-not $isInstalled) {
    $commonPaths = @(
        "$env:ProgramFiles\Sunshine",
        "${env:ProgramFiles(x86)}\Sunshine",
        "$env:LOCALAPPDATA\Programs\Sunshine"
    )
    foreach ($path in $commonPaths) {
        $exePath = Join-Path $path "sunshine.exe"
        if (Test-Path $exePath) {
            $installDir = $path
            $isInstalled = $true
            break
        }
    }
}

if ($isInstalled) {
    Write-Host "检测到 Sunshine 已安装，安装目录: $installDir"
} else {
    Write-Host "未检测到 Sunshine 安装，将进行首次安装。"
}

$tempDir = "$env:TEMP\sunshine-update"
$githubApiUrl = "https://api.github.com/repos/LizardByte/Sunshine/releases"
# GitHub token 用于提高 API 速率限制（可选，若未设置则使用无认证请求）
# 可在环境变量 GITHUB_TOKEN 中设置，或在此硬编码
$githubToken = $env:GITHUB_TOKEN

# 创建临时目录
if (!(Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }

# 退出函数
Function Exit-Script {
    param([int]$exitCode = 0)
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    if ($exitCode -eq 0) {
        Read-Host -Prompt "按回车键退出"
    }
    exit $exitCode
}

# 检查本地版本（尝试读取可执行文件的文件版本信息）
$localVersion = ""
if ($isInstalled -and $installDir) {
    $exePath = Join-Path $installDir "sunshine.exe"
    if (Test-Path $exePath) {
        try {
            $fv = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
            $localVersion = $fv.ProductVersion
        } catch {}
    }
    Write-Host "本地版本: $localVersion"
}

Write-Host "正在查询可用版本..."
# 构造请求头：自定义 User-Agent 和可选的 GitHub token
$headers = @{ 'User-Agent' = 'sunshine-update-script' }
if ($githubToken) {
    $headers['Authorization'] = "token $githubToken"
    Write-Host "使用 GitHub token 进行认证"
}

# 获取所有 releases，带重试机制
$maxRetries = 3
$retryCount = 0
$allReleases = $null
while ($retryCount -lt $maxRetries) {
    try {
        $allReleases = Invoke-RestMethod -Uri $githubApiUrl -Headers $headers -ErrorAction Stop
        break
    } catch {
        $retryCount++
        if ($retryCount -ge $maxRetries) {
            Write-Host "错误：无法获取版本信息，已重试 $maxRetries 次。"
            Write-Host "错误详情: $($_.Exception.Message)"
            Write-Host ""
            Write-Host "解决方案："
            Write-Host "  1. 等待几分钟后重试（GitHub API 有速率限制）"
            Write-Host "  2. 设置 GitHub token 以获得更高的请求限制："
            Write-Host "     set GITHUB_TOKEN=your_personal_access_token"
            Write-Host "     然后重新运行此脚本"
            Exit-Script 1
        }
        Write-Host "查询失败（第 $retryCount/$maxRetries 次），等待 5 秒后重试..."
        Start-Sleep -Seconds 5
    }
}

# 主菜单循环：选择版本类型和版本
$selectedRelease = $null
$shouldExit = $false

while ($null -eq $selectedRelease -and -not $shouldExit) {
    # 询问用户选择版本类型
    Write-Host ""
    Write-Host "请选择要安装的版本类型："
    Write-Host "  1. 稳定版本 (Stable)"
    Write-Host "  2. Pre-release 版本 (包括 Beta、Alpha 等)"
    Write-Host "  0. 退出"
    $versionTypeChoice = Read-Host "请输入选项 (0/1/2，默认为 1)"
    
    # 处理退出选项
    if ($versionTypeChoice -eq "0") {
        Write-Host "已取消操作。"
        Exit-Script 0
    }
    
    # 确定版本类型
    if ($versionTypeChoice -eq "2") {
        $includePrerelease = $true
        Write-Host "已选择：Pre-release 版本"
    } else {
        $includePrerelease = $false
        Write-Host "已选择：稳定版本"
    }
    
    # 过滤 releases：根据用户选择过滤稳定版或包含 pre-release
    $filteredReleases = $allReleases | Where-Object {
        if ($includePrerelease) {
            $true  # 包含所有版本（稳定版和 pre-release）
        } else {
            -not $_.prerelease  # 只包含稳定版本
        }
    } | Select-Object -First 10
    
    if ($filteredReleases.Count -eq 0) {
        Write-Host "错误：未找到符合条件的版本。"
        Write-Host ""
        $retryChoice = Read-Host "是否返回重新选择？(Y/N，默认为 Y)"
        if ($retryChoice -ne "N" -and $retryChoice -ne "n") {
            continue  # 返回重新选择版本类型
        } else {
            Exit-Script 1
        }
    }
    
    # 版本选择循环
    $versionSelected = $false
    while (-not $versionSelected -and -not $shouldExit) {
        # 显示版本列表供用户选择
        Write-Host ""
        Write-Host "可用的版本列表（最近 10 个）："
        Write-Host "=========================================="
        for ($i = 0; $i -lt $filteredReleases.Count; $i++) {
            $release = $filteredReleases[$i]
            $versionLabel = $release.tag_name
            $prereleaseLabel = if ($release.prerelease) { " [Pre-release]" } else { " [Stable]" }
            $publishedDate = [DateTime]::Parse($release.published_at).ToString("yyyy-MM-dd")
            Write-Host "  $($i + 1). $versionLabel$prereleaseLabel (发布于: $publishedDate)"
        }
        Write-Host "=========================================="
        Write-Host "  B. 返回上一层（重新选择版本类型）"
        Write-Host "  0. 退出"
        Write-Host "=========================================="
        
        # 让用户选择版本
        $selectedIndex = -1
        $userInput = Read-Host "请输入要安装的版本编号 (1-$($filteredReleases.Count))，或输入 B/0"
        
        # 处理特殊选项
        if ($userInput -eq "0" -or $userInput -eq "q" -or $userInput -eq "Q") {
            Write-Host "已取消操作。"
            Exit-Script 0
        }
        
        if ($userInput -eq "B" -or $userInput -eq "b" -or $userInput -eq "back") {
            Write-Host "返回上一层..."
            break  # 跳出版本选择循环，返回版本类型选择
        }
        
        # 处理数字输入
        if ([int]::TryParse($userInput, [ref]$selectedIndex)) {
            if ($selectedIndex -ge 1 -and $selectedIndex -le $filteredReleases.Count) {
                $selectedRelease = $filteredReleases[$selectedIndex - 1]
                $versionSelected = $true
            } else {
                Write-Host "无效的选择，请输入 1 到 $($filteredReleases.Count) 之间的数字，或输入 B/0。"
            }
        } else {
            Write-Host "无效的输入，请输入数字、B（返回）或 0（退出）。"
        }
    }
}

# 如果用户选择退出，清理并退出
if ($shouldExit) {
    Exit-Script 0
}

# 确认选择的版本
$latestVersion = $selectedRelease.tag_name
Write-Host ""
Write-Host "已选择版本: $latestVersion"

# 在 assets 中查找 Windows installer (.exe)
# 优先匹配 Windows + .exe 的组合，避免选中 Linux/Debian 包
$asset = $selectedRelease.assets | Where-Object { 
    $_.name -match "(?i)windows.*\.exe$|\.exe$.*windows" -or $_.name -match "(?i)windows-amd64.*\.exe$"
} | Select-Object -First 1

# 如果没找到，退回到宽松匹配
if (-not $asset) {
    $asset = $selectedRelease.assets | Where-Object { 
        $_.name -match "(?i)installer.*exe$|exe$.*installer" 
    } | Select-Object -First 1
}

if (-not $asset) {
    Write-Host "未在 release 中找到 Windows 安装程序 (.exe)，脚本退出。"
    Write-Host "可用的 assets："
    $selectedRelease.assets | ForEach-Object { Write-Host "  - $($_.name)" }
    Exit-Script 1
}

$assetName = $asset.name
$downloadUrl = $asset.browser_download_url
Write-Host "发现安装包: $assetName"

# 版本比较：如果本地版本字符串包含所选版本号（去掉前导 v），则询问用户是否仍要安装
# 如果未安装，跳过版本检查，直接进行安装
$verNoV = $latestVersion.TrimStart('v')
if ($isInstalled -and $localVersion -and $localVersion.Contains($verNoV)) {
    Write-Host ""
    Write-Host "检测到本地已安装版本 $localVersion，与选择的版本 $latestVersion 相同。"
    $continueChoice = Read-Host "是否仍要继续安装？(Y/N，默认为 N)"
    if ($continueChoice -ne "Y" -and $continueChoice -ne "y") {
        Write-Host "已取消安装。"
        Exit-Script 0
    }
    Write-Host "将继续安装..."
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
    Exit-Script 1
}

Write-Host "下载完成: $installerPath"

# 将 Sunshine 安装目录添加到系统 PATH
Function Add-SunshineToPath {
    param([string]$sunshinePath)
    
    if (-not $sunshinePath -or -not (Test-Path $sunshinePath)) {
        Write-Host "警告：无法将 Sunshine 添加到 PATH，安装路径无效: $sunshinePath"
        return $false
    }
    
    Write-Host ""
    Write-Host "开始将 Sunshine 添加到系统 PATH..."
    
    # 检查管理员权限
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "警告：需要管理员权限才能修改系统 PATH。请以管理员身份运行此脚本。"
        Write-Host "您可以手动将以下路径添加到系统 PATH："
        Write-Host "  $sunshinePath"
        return $false
    }
    
    # 获取当前系统 PATH
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    
    # 检查是否已包含该路径
    $pathArray = $currentPath -split ';' | Where-Object { $_ -ne '' }
    if ($pathArray -contains $sunshinePath) {
        Write-Host "Sunshine 安装目录已在系统 PATH 中，无需添加。"
        return $true
    }
    
    # 添加到系统 PATH
    try {
        $newPath = $currentPath
        if ($newPath -and -not $newPath.EndsWith(';')) {
            $newPath += ';'
        }
        $newPath += $sunshinePath
        
        [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
        Write-Host "成功将 Sunshine 安装目录添加到系统 PATH：$sunshinePath"
        Write-Host "注意：需要重新打开命令行窗口或重新登录才能使 PATH 更改生效。"
        
        # 更新当前会话的 PATH（立即生效）
        $env:Path += ";$sunshinePath"
        Write-Host "已更新当前会话的 PATH。"
        return $true
    } catch {
        Write-Host "添加 Sunshine 到系统 PATH 失败：$($_.Exception.Message)"
        Write-Host "您可以手动将以下路径添加到系统 PATH："
        Write-Host "  $sunshinePath"
        return $false
    }
}

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
    Write-Host ""
    Write-Host "注意：安装完成后，请重新运行此脚本以配置 PATH 和防火墙规则。"
} else {
    Write-Host "安装已完成。"
    
    # 重新检测安装目录（安装后可能位置发生变化）
    $newInstallDir = $null
    try {
        $sunshineCmd = Get-Command sunshine.exe -ErrorAction SilentlyContinue
        if ($sunshineCmd) {
            $newInstallDir = Split-Path $sunshineCmd.Source
        }
    } catch {}
    
    # 如果通过 PATH 找不到，尝试检查常见的安装位置
    if (-not $newInstallDir) {
        $commonPaths = @(
            "$env:ProgramFiles\Sunshine",
            "${env:ProgramFiles(x86)}\Sunshine",
            "$env:LOCALAPPDATA\Programs\Sunshine"
        )
        foreach ($path in $commonPaths) {
            $exePath = Join-Path $path "sunshine.exe"
            if (Test-Path $exePath) {
                $newInstallDir = $path
                break
            }
        }
    }
    
    # 如果找到了新的安装目录，添加到 PATH
    if ($newInstallDir) {
        Add-SunshineToPath -sunshinePath $newInstallDir
        $installDir = $newInstallDir
    } elseif ($installDir) {
        # 如果之前有安装目录，也尝试添加到 PATH
        Add-SunshineToPath -sunshinePath $installDir
    } else {
        Write-Host "警告：无法自动检测 Sunshine 安装目录，请手动将其添加到系统 PATH。"
    }
}

# 配置防火墙规则
Function Configure-FirewallRules {
    Write-Host ""
    Write-Host "开始配置防火墙规则..."
    
    # 检查管理员权限
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "警告：需要管理员权限才能配置防火墙规则。请以管理员身份运行此脚本。"
        Write-Host "防火墙规则未配置，您需要手动创建以下规则："
        Write-Host "  1. TCP 端口: 47984, 47989, 47990, 48010"
        Write-Host "  2. UDP 端口: 47998-48000"
        return
    }
    
    # 创建 TCP 入站规则
    $tcpRuleName = "sunshine tcp"
    $tcpRuleExists = Get-NetFirewallRule -DisplayName $tcpRuleName -ErrorAction SilentlyContinue
    if ($tcpRuleExists) {
        Write-Host "TCP 防火墙规则 '$tcpRuleName' 已存在，跳过创建。"
    } else {
        try {
            $tcpPorts = @("47984", "47989", "47990", "48010")
            New-NetFirewallRule -DisplayName $tcpRuleName -Direction Inbound -Protocol TCP -LocalPort $tcpPorts -Action Allow -ErrorAction Stop
            Write-Host "TCP 防火墙规则 '$tcpRuleName' 创建成功。"
        } catch {
            Write-Host "创建 TCP 防火墙规则失败：$($_.Exception.Message)"
            Write-Host "如果命令失败，请尝试为每个端口单独创建规则。"
        }
    }
    
    # 创建 UDP 入站规则
    $udpRuleName = "sunshine udp"
    $udpRuleExists = Get-NetFirewallRule -DisplayName $udpRuleName -ErrorAction SilentlyContinue
    if ($udpRuleExists) {
        Write-Host "UDP 防火墙规则 '$udpRuleName' 已存在，跳过创建。"
    } else {
        try {
            New-NetFirewallRule -DisplayName $udpRuleName -Direction Inbound -Protocol UDP -LocalPort 47998-48000 -Action Allow -ErrorAction Stop
            Write-Host "UDP 防火墙规则 '$udpRuleName' 创建成功。"
        } catch {
            Write-Host "创建 UDP 防火墙规则失败：$($_.Exception.Message)"
        }
    }
    
    # 验证防火墙规则
    Write-Host ""
    Write-Host "防火墙规则验证："
    $rules = Get-NetFirewallRule -DisplayName "sunshine*" -ErrorAction SilentlyContinue
    if ($rules) {
        $rules | Format-Table DisplayName, Enabled, Direction, Action -AutoSize
    } else {
        Write-Host "未找到 Sunshine 防火墙规则。"
    }
}

# 配置防火墙规则（仅在安装成功后执行）
if ($installed) {
    Configure-FirewallRules
}

# 清理临时文件并退出
Write-Host ""
Write-Host "更新/安装流程结束。"
Exit-Script 0
