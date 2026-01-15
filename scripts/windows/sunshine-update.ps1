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
}
catch {}

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

$tempDir = "$env:TEMP\sunshine-update"
$githubApiUrl = "https://api.github.com/repos/LizardByte/Sunshine/releases"
# GitHub token 用于提高 API 速率限制（可选，若未设置则使用无认证请求）
# 可在环境变量 GITHUB_TOKEN 中设置，或在此硬编码
$githubToken = $env:GITHUB_TOKEN

# 创建临时目录
if (!(Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }

# 版本信息缓存（全局变量）
$script:allReleasesCache = $null

# 退出函数
Function Exit-Script {
    param([int]$exitCode = 0)
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    if ($exitCode -eq 0) {
        Read-Host -Prompt "按回车键退出"
    }
    exit $exitCode
}

# 获取所有 releases（带缓存）
Function Get-AllReleases {
    # 如果已缓存，直接返回
    if ($null -ne $script:allReleasesCache) {
        Write-Host "使用缓存的版本信息。"
        return $script:allReleasesCache
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
            # 缓存版本信息
            $script:allReleasesCache = $allReleases
            Write-Host "版本信息查询成功，已缓存。"
            return $allReleases
        }
        catch {
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
                return $null
            }
            Write-Host "查询失败（第 $retryCount/$maxRetries 次），等待 5 秒后重试..."
            Start-Sleep -Seconds 5
        }
    }
    return $null
}

# 计算 Sunshine 所需端口
Function Get-SunshinePorts {
    param($basePort)
    
    # 确保转换为单个整数
    [int]$bp = 0
    if ($basePort -is [array]) {
        $bp = [int]($basePort[0])
    }
    else {
        $bp = [int]$basePort
    }
    
    $ports = @{
        TcpPorts = @(
            $bp            # 基础端口（TCP）
            $bp - 5
            $bp + 1
            $bp + 21
        )
        UdpPorts = @(
            $bp + 9
            $bp + 10
            $bp + 11
        )
    }
    
    return $ports
}

# 验证端口号是否有效（检查是否小于 1024）
Function Test-PortRange {
    param([int[]]$ports)
    
    foreach ($port in $ports) {
        if ($port -lt 1024) {
            return $false
        }
        if ($port -gt 65535) {
            return $false
        }
    }
    return $true
}

# 配置防火墙规则（支持动态端口）
Function Configure-FirewallRules {
    param($basePort = 0)
    
    Write-Host ""
    Write-Host "开始配置防火墙规则..."
    
    # 检查管理员权限
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "警告：需要管理员权限才能配置防火墙规则。请以管理员身份运行此脚本。"
        return $false
    }
    
    # 如果没有提供基础端口，使用默认值
    if ($basePort -eq 0) {
        $basePort = 47989
        Write-Host "使用默认基础端口: $basePort"
    }
    
    # 计算所需端口
    $sunshinePorts = Get-SunshinePorts -basePort $basePort
    
    # 验证所有端口
    $allPorts = $sunshinePorts.TcpPorts + $sunshinePorts.UdpPorts
    if (-not (Test-PortRange -ports $allPorts)) {
        Write-Host "错误：计算出的端口号无效。"
        Write-Host "TCP 端口: $($sunshinePorts.TcpPorts -join ', ')"
        Write-Host "UDP 端口: $($sunshinePorts.UdpPorts -join ', ')"
        Write-Host "所有端口必须大于等于 1024 且小于等于 65535。"
        return $false
    }
    
    Write-Host ""
    Write-Host "将配置以下端口："
    Write-Host "  TCP 端口: $($sunshinePorts.TcpPorts -join ', ')"
    Write-Host "  UDP 端口: $($sunshinePorts.UdpPorts[0])-$($sunshinePorts.UdpPorts[-1])"
    
    # 检查现有规则
    $tcpRuleName = "sunshine tcp"
    $udpRuleName = "sunshine udp"
    $tcpRuleExists = Get-NetFirewallRule -DisplayName $tcpRuleName -ErrorAction SilentlyContinue
    $udpRuleExists = Get-NetFirewallRule -DisplayName $udpRuleName -ErrorAction SilentlyContinue
    
    # 显示将要添加/更新的防火墙规则详情
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "防火墙规则详情："
    Write-Host "=========================================="
    
    if ($tcpRuleExists) {
        Write-Host "TCP 规则：更新现有规则 '$tcpRuleName'"
    }
    else {
        Write-Host "TCP 规则：创建新规则 '$tcpRuleName'"
    }
    Write-Host "  规则名称: $tcpRuleName"
    Write-Host "  协议: TCP"
    Write-Host "  方向: 入站 (Inbound)"
    Write-Host "  端口: $($sunshinePorts.TcpPorts -join ', ')"
    Write-Host "  操作: 允许 (Allow)"
    
    Write-Host ""
    
    if ($udpRuleExists) {
        Write-Host "UDP 规则：更新现有规则 '$udpRuleName'"
    }
    else {
        Write-Host "UDP 规则：创建新规则 '$udpRuleName'"
    }
    Write-Host "  规则名称: $udpRuleName"
    Write-Host "  协议: UDP"
    Write-Host "  方向: 入站 (Inbound)"
    Write-Host "  端口: $($sunshinePorts.UdpPorts[0])-$($sunshinePorts.UdpPorts[-1])"
    Write-Host "  操作: 允许 (Allow)"
    
    Write-Host "=========================================="
    Write-Host ""
    
    # 等待用户确认
    $confirmChoice = Read-Host "是否确认添加/更新以上防火墙规则？(Y/N，默认为 Y)"
    if ($confirmChoice -ne "Y" -and $confirmChoice -ne "y" -and $confirmChoice -ne "") {
        Write-Host "已取消防火墙规则配置。"
        return $false
    }
    
    Write-Host ""
    Write-Host "正在配置防火墙规则..."
    
    # 处理 TCP 规则
    if ($tcpRuleExists) {
        Write-Host ""
        Write-Host "TCP 防火墙规则 '$tcpRuleName' 已存在，正在更新..."
        try {
            # 删除旧规则
            Remove-NetFirewallRule -DisplayName $tcpRuleName -ErrorAction Stop
            Write-Host "已删除旧的 TCP 规则。"
        }
        catch {
            Write-Host "删除旧 TCP 规则失败：$($_.Exception.Message)"
            Write-Host "尝试直接创建新规则..."
        }
    }
    
    # 创建或更新 TCP 规则
    try {
        $tcpPortsStr = $sunshinePorts.TcpPorts | ForEach-Object { $_.ToString() }
        New-NetFirewallRule -DisplayName $tcpRuleName -Direction Inbound -Protocol TCP -LocalPort $tcpPortsStr -Action Allow -ErrorAction Stop
        Write-Host "TCP 防火墙规则 '$tcpRuleName' 配置成功。"
    }
    catch {
        Write-Host "配置 TCP 防火墙规则失败：$($_.Exception.Message)"
        Write-Host "尝试为每个端口单独创建规则..."
        # 尝试为每个端口单独创建规则
        foreach ($port in $sunshinePorts.TcpPorts) {
            try {
                $ruleName = "$tcpRuleName - $port"
                $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
                if ($existingRule) {
                    Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction Stop
                }
                New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow -ErrorAction Stop
            }
            catch {
                Write-Host "  创建端口 $port 的规则失败：$($_.Exception.Message)"
            }
        }
    }
    
    # 处理 UDP 规则
    if ($udpRuleExists) {
        Write-Host ""
        Write-Host "UDP 防火墙规则 '$udpRuleName' 已存在，正在更新..."
        try {
            # 删除旧规则
            Remove-NetFirewallRule -DisplayName $udpRuleName -ErrorAction Stop
            Write-Host "已删除旧的 UDP 规则。"
        }
        catch {
            Write-Host "删除旧 UDP 规则失败：$($_.Exception.Message)"
            Write-Host "尝试直接创建新规则..."
        }
    }
    
    # 创建或更新 UDP 规则
    try {
        $udpPortRange = "$($sunshinePorts.UdpPorts[0])-$($sunshinePorts.UdpPorts[-1])"
        New-NetFirewallRule -DisplayName $udpRuleName -Direction Inbound -Protocol UDP -LocalPort $udpPortRange -Action Allow -ErrorAction Stop
        Write-Host "UDP 防火墙规则 '$udpRuleName' 配置成功。"
    }
    catch {
        Write-Host "配置 UDP 防火墙规则失败：$($_.Exception.Message)"
        Write-Host "尝试为每个端口单独创建规则..."
        # 尝试为每个端口单独创建规则
        foreach ($port in $sunshinePorts.UdpPorts) {
            try {
                $ruleName = "$udpRuleName - $port"
                $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
                if ($existingRule) {
                    Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction Stop
                }
                New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol UDP -LocalPort $port -Action Allow -ErrorAction Stop
            }
            catch {
                Write-Host "  创建端口 $port 的规则失败：$($_.Exception.Message)"
            }
        }
    }
    
    # 验证防火墙规则
    Write-Host ""
    Write-Host "防火墙规则验证："
    $rules = Get-NetFirewallRule -DisplayName "sunshine*" -ErrorAction SilentlyContinue
    if ($rules) {
        $rules | Format-Table DisplayName, Enabled, Direction, Action -AutoSize
    }
    else {
        Write-Host "未找到 Sunshine 防火墙规则。"
    }
    
    return $true
}

# 配置防火墙规则的交互式函数（用于安装流程中询问是否配置）
Function Configure-FirewallRulesInteractive {
    Write-Host ""
    Write-Host "是否要配置防火墙规则？"
    Write-Host "  1. 是，使用默认端口（基础端口 47989）"
    Write-Host "  2. 是，自定义基础端口"
    Write-Host "  0. 跳过防火墙配置"
    $firewallChoice = Read-Host "请输入选项 (0/1/2，默认为 1)"
    
    if ($firewallChoice -eq "0") {
        Write-Host "跳过防火墙配置。"
        return
    }
    
    $basePort = 0
    if ($firewallChoice -eq "2") {
        # 用户自定义基础端口
        $portValid = $false
        while (-not $portValid) {
            $portInput = Read-Host "请输入基础端口号（必须 >= 1029，建议 >= 47989）"
            $parsedPort = 0
            if ([int]::TryParse($portInput, [ref]$parsedPort)) {
                # 确保 basePort 是整数类型
                $basePort = [int]$parsedPort
                # 先计算端口，然后验证（确保传递整数）
                $testPorts = Get-SunshinePorts -basePort ([int]$basePort)
                $allTestPorts = $testPorts.TcpPorts + $testPorts.UdpPorts
                
                if (-not (Test-PortRange -ports $allTestPorts)) {
                    Write-Host ""
                    Write-Host "错误：基于端口 $basePort 计算出的端口号无效："
                    Write-Host "  TCP 端口: $($testPorts.TcpPorts -join ', ')"
                    Write-Host "  UDP 端口: $($testPorts.UdpPorts[0])-$($testPorts.UdpPorts[-1])"
                    Write-Host "所有端口必须大于等于 1024 且小于等于 65535。"
                    Write-Host "请重新输入一个更大的基础端口号（建议 >= 1029）。"
                    Write-Host ""
                }
                else {
                    $portValid = $true
                }
            }
            else {
                Write-Host "无效的输入，请输入数字。"
            }
        }
    }
    else {
        # 使用默认端口 47989
        $basePort = [int]47989
    }
    
    # 配置防火墙规则（确保 basePort 是整数）
    Configure-FirewallRules -basePort ([int]$basePort)
}

# 配置防火墙规则的直接函数（用于主菜单的"仅配置防火墙"选项）
Function Configure-FirewallRulesDirect {
    Write-Host ""
    Write-Host "配置防火墙规则"
    Write-Host "  1. 使用默认端口（基础端口 47989）"
    Write-Host "  2. 自定义基础端口"
    Write-Host "  0. 返回主菜单"
    $firewallChoice = Read-Host "请输入选项 (0/1/2，默认为 1)"
    
    if ($firewallChoice -eq "0") {
        Write-Host "返回主菜单..."
        return
    }
    
    $basePort = 0
    if ($firewallChoice -eq "2") {
        # 用户自定义基础端口
        $portValid = $false
        while (-not $portValid) {
            $portInput = Read-Host "请输入基础端口号（必须 >= 1029，建议 >= 47989），或输入 B 返回"
            if ($portInput -eq "B" -or $portInput -eq "b") {
                Write-Host "返回主菜单..."
                return
            }
            $parsedPort = 0
            if ([int]::TryParse($portInput, [ref]$parsedPort)) {
                # 确保 basePort 是整数类型
                $basePort = [int]$parsedPort
                # 先计算端口，然后验证（确保传递整数）
                $testPorts = Get-SunshinePorts -basePort ([int]$basePort)
                $allTestPorts = $testPorts.TcpPorts + $testPorts.UdpPorts
                
                if (-not (Test-PortRange -ports $allTestPorts)) {
                    Write-Host ""
                    Write-Host "错误：基于端口 $basePort 计算出的端口号无效："
                    Write-Host "  TCP 端口: $($testPorts.TcpPorts -join ', ')"
                    Write-Host "  UDP 端口: $($testPorts.UdpPorts[0])-$($testPorts.UdpPorts[-1])"
                    Write-Host "所有端口必须大于等于 1024 且小于等于 65535。"
                    Write-Host "请重新输入一个更大的基础端口号（建议 >= 1029）。"
                    Write-Host ""
                }
                else {
                    $portValid = $true
                }
            }
            else {
                Write-Host "无效的输入，请输入数字或 B（返回）。"
            }
        }
    }
    else {
        # 使用默认端口 47989
        $basePort = [int]47989
    }
    
    # 配置防火墙规则（确保 basePort 是整数）
    Configure-FirewallRules -basePort ([int]$basePort)
}

# 主菜单循环
$script:shouldReturnToMainMenu = $false
$mainMenuLoop = $true

while ($mainMenuLoop) {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "Sunshine 安装/更新工具"
    Write-Host "=========================================="
    if ($isInstalled) {
        Write-Host "检测到 Sunshine 已安装，安装目录: $installDir"
    }
    else {
        Write-Host "未检测到 Sunshine 安装。"
    }
    Write-Host ""
    Write-Host "请选择操作："
    Write-Host "  1. 安装/更新 Sunshine"
    Write-Host "  2. 仅配置防火墙规则"
    Write-Host "  0. 退出"
    $mainChoice = Read-Host "请输入选项 (0/1/2，默认为 1)"

    if ($mainChoice -eq "0") {
        Write-Host "已退出。"
        Exit-Script 0
    }

    # 如果选择安装/更新，进入安装流程
    if ($mainChoice -eq "1" -or $mainChoice -eq "") {
        # 检查本地版本（尝试读取可执行文件的文件版本信息）
        $localVersion = ""
        if ($isInstalled -and $installDir) {
            $exePath = Join-Path $installDir "sunshine.exe"
            if (Test-Path $exePath) {
                try {
                    $fv = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
                    $localVersion = $fv.ProductVersion
                }
                catch {}
            }
            Write-Host "本地版本: $localVersion"
        }
        
        # 获取版本信息（带缓存）
        $allReleases = Get-AllReleases
        if ($null -eq $allReleases) {
            Exit-Script 1
        }

        # 版本选择流程（支持返回主菜单）
        $selectedRelease = $null
        $backToMainMenu = $false

        while ($null -eq $selectedRelease -and -not $backToMainMenu) {
            # 询问用户选择版本类型
            Write-Host ""
            Write-Host "请选择要安装的版本类型："
            Write-Host "  1. 稳定版本 (Stable)"
            Write-Host "  2. Pre-release 版本 (包括 Beta、Alpha 等)"
            Write-Host "  B. 返回主菜单"
            Write-Host "  0. 退出"
            $versionTypeChoice = Read-Host "请输入选项 (0/1/2/B，默认为 1)"
            
            # 处理返回主菜单选项
            if ($versionTypeChoice -eq "B" -or $versionTypeChoice -eq "b" -or $versionTypeChoice -eq "back") {
                Write-Host "返回主菜单..."
                $backToMainMenu = $true
                break
            }
            
            # 处理退出选项
            if ($versionTypeChoice -eq "0") {
                Write-Host "已取消操作。"
                Exit-Script 0
            }
            
            # 确定版本类型
            if ($versionTypeChoice -eq "2") {
                $includePrerelease = $true
                Write-Host "已选择：Pre-release 版本"
            }
            else {
                $includePrerelease = $false
                Write-Host "已选择：稳定版本"
            }
            
            # 过滤 releases：根据用户选择过滤稳定版或包含 pre-release
            $filteredReleases = $allReleases | Where-Object {
                if ($includePrerelease) {
                    $true  # 包含所有版本（稳定版和 pre-release）
                }
                else {
                    -not $_.prerelease  # 只包含稳定版本
                }
            } | Select-Object -First 10
            
            if ($filteredReleases.Count -eq 0) {
                Write-Host "错误：未找到符合条件的版本。"
                Write-Host ""
                $retryChoice = Read-Host "是否返回重新选择？(Y/N/B，Y=重新选择，N=退出，B=返回主菜单，默认为 Y)"
                if ($retryChoice -eq "B" -or $retryChoice -eq "b") {
                    $backToMainMenu = $true
                    break
                }
                elseif ($retryChoice -eq "N" -or $retryChoice -eq "n") {
                    Exit-Script 1
                }
                # 否则继续循环，重新选择版本类型
                continue
            }
            
            # 版本选择循环
            $versionSelected = $false
            while (-not $versionSelected -and -not $backToMainMenu) {
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
                    }
                    else {
                        Write-Host "无效的选择，请输入 1 到 $($filteredReleases.Count) 之间的数字，或输入 B/0。"
                    }
                }
                else {
                    Write-Host "无效的输入，请输入数字、B（返回）或 0（退出）。"
                }
            }
        }

        # 如果用户选择返回主菜单，抛出特殊标记以便外层处理
        if ($backToMainMenu) {
            # 设置一个标记，让外层知道需要重新显示主菜单
            $script:shouldReturnToMainMenu = $true
            continue  # 跳过后续的安装流程，返回主菜单
        }

        # 确认选择的版本
        if ($null -eq $selectedRelease) {
            continue  # 如果没有选择版本，返回主菜单
        }

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
            # 验证参数
            if (-not $url -or -not $outPath) {
                Write-Host "错误：下载参数无效。URL: $url, 输出路径: $outPath"
                return $false
            }
            
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
                        }
                        catch {
                            $size = -1
                        }
                        if ($size -gt 0 -and $size -eq $prevSize) {
                            $stable++
                        }
                        else {
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
                if (-not $outPath) {
                    Write-Host "错误：输出路径为空，无法使用 IDM 下载。"
                    $idm = $null  # 禁用 IDM，使用其他方法
                }
                else {
                    $outDir = Split-Path $outPath -Parent
                    $fileName = Split-Path $outPath -Leaf
                    if (!(Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
                    $args = @('/d', $url, '/p', $outDir, '/f', $fileName, '/n')
                    try {
                        $proc = Start-Process -FilePath $idm -ArgumentList $args -PassThru -NoNewWindow -ErrorAction Stop
                    }
                    catch {
                        Write-Host "启动 IDM 失败：$($_.Exception.Message)，回退到其它下载方式。"
                        $proc = $null
                    }
                    if ($proc) {
                        # 等待文件下载完成（最多 10 分钟）
                        $ok = Wait-ForFileComplete $outPath 600
                        if ($ok) { return $true } else { Write-Host "IDM 下载等待超时或失败，回退到其它方法。" }
                    }
                }
            }
            else {
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
                }
                catch {
                    Write-Host "BITS 下载失败：$($_.Exception.Message)"
                }
            }

            # 最后回退到 Invoke-WebRequest
            Write-Host "使用 Invoke-WebRequest 下载（回退）..."
            try {
                Invoke-WebRequest -Uri $url -OutFile $outPath -Headers $headers -UseBasicParsing
                return $true
            }
            catch {
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
            }
            catch {
                Write-Host "添加 Sunshine 到系统 PATH 失败：$($_.Exception.Message)"
                Write-Host "您可以手动将以下路径添加到系统 PATH："
                Write-Host "  $sunshinePath"
                return $false
            }
        }

        # 尝试静默安装的常见参数列表
        $silentFlagsList = @('/S', '/VERYSILENT', '/SILENT', '/quiet', '/qn')
        $installed = $false
        foreach ($flag in $silentFlagsList) {
            Write-Host "尝试静默安装参数: $flag"
            try {
                $proc = Start-Process -FilePath $installerPath -ArgumentList $flag -Wait -PassThru -ErrorAction Stop
                if ($proc.ExitCode -eq 0) {
                    Write-Host "静默安装成功（参数: $flag）。"
                    $installed = $true
                    break
                }
                else {
                    Write-Host "安装返回代码: $($proc.ExitCode)（参数: $flag），尝试下一个参数。"
                }
            }
            catch {
                Write-Host "使用参数 $flag 启动安装器失败：$($_.Exception.Message)"
            }
        }

        if (-not $installed) {
            Write-Host "未能以常见静默参数完成安装，将以交互方式运行安装程序。"
            Start-Process -FilePath $installerPath
            Write-Host "请按照安装程序完成安装。"
            Write-Host ""
            Write-Host "注意：安装完成后，请重新运行此脚本以配置 PATH 和防火墙规则。"
        }
        else {
            Write-Host "安装已完成。"
        
            # 重新检测安装目录（安装后可能位置发生变化）
            $newInstallDir = $null
            try {
                $sunshineCmd = Get-Command sunshine.exe -ErrorAction SilentlyContinue
                if ($sunshineCmd) {
                    $newInstallDir = Split-Path $sunshineCmd.Source
                }
            }
            catch {}
        
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
            }
            elseif ($installDir) {
                # 如果之前有安装目录，也尝试添加到 PATH
                Add-SunshineToPath -sunshinePath $installDir
            }
            else {
                Write-Host "警告：无法自动检测 Sunshine 安装目录，请手动将其添加到系统 PATH。"
            }
        
            # 如果安装成功，询问是否配置防火墙
            if ($installed) {
                Configure-FirewallRulesInteractive
            }
        
            # 检查是否需要返回主菜单
            if ($script:shouldReturnToMainMenu) {
                $script:shouldReturnToMainMenu = $false
                continue  # 继续主菜单循环
            }
        
            # 安装流程完成，退出主循环
            $mainMenuLoop = $false
        }  # 结束 else 块（安装成功）
    }  # 结束 if ($mainChoice -eq "1" -or $mainChoice -eq "")
    elseif ($mainChoice -eq "2") {
        # 如果选择了仅配置防火墙
        try {
            Configure-FirewallRulesDirect
        }
        catch {
            Write-Host "配置防火墙时发生错误: $($_.Exception.Message)"
            Write-Host "返回主菜单..."
        }
        # 配置完成后继续主菜单循环（用户可以再次选择）
        # continue 语句会跳转到 while 循环的开始，重新显示主菜单
        # 确保循环继续执行
        $mainMenuLoop = $true
        continue
    }
    else {
        # 无效的选择，提示用户重新选择
        Write-Host "无效的选择，请输入 0、1 或 2。"
        Write-Host ""
    }
}  # 结束主菜单循环 while ($mainMenuLoop)

# 只有在安装流程完成后才执行到这里（$mainMenuLoop = $false）
# 如果只是配置防火墙，应该 continue 继续循环，不会执行到这里

# 清理临时文件并退出
# 注意：只有在安装流程完成后（$mainMenuLoop = $false）才会执行到这里
# 如果只是配置防火墙，应该 continue 继续循环，不会执行到这里
Write-Host ""
Write-Host "更新/安装流程结束。"
Exit-Script 0
