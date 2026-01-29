# Version.psm1 - 版本管理模块
# 提供本地版本检测、版本号比较和更新决策功能

# 导入日志模块
if (-not (Get-Module -Name "Logging" -ErrorAction SilentlyContinue)) {
    try {
        Import-Module -Name "$PSScriptRoot\Logging.psm1" -Force -ErrorAction Stop
    }
    catch {
        Write-Host "警告: 无法加载日志模块，使用简化日志输出" -ForegroundColor Yellow
    }
}

# 版本缓存
$global:VERSION_CACHE = @{}

# 规范化版本号
function Normalize-Version {
    param(
        [Parameter(Mandatory=$true)]
        [string]$VersionString
    )

    if ([string]::IsNullOrWhiteSpace($VersionString)) {
        return $null
    }

    $original = $VersionString

    try {
        # 移除前导的v或V
        $version = $VersionString.Trim()
        if ($version -match '^[vV](.+)') {
            $version = $matches[1]
        }

        # 提取版本号部分（移除构建信息等）
        if ($version -match '^(\d+(?:\.\d+)*)') {
            $version = $matches[1]
        }

        # 确保版本号格式正确
        $parts = $version -split '\.'

        # 补全缺失的部分（如1.0 -> 1.0.0）
        while ($parts.Count -lt 3) {
            $parts += "0"
        }

        # 限制最多4个部分
        if ($parts.Count -gt 4) {
            $parts = $parts[0..3]
        }

        $normalized = $parts -join '.'
        Write-DebugLog "规范化版本号: '$original' -> '$normalized'"

        return $normalized
    }
    catch {
        Write-WarnLog "版本号规范化失败: '$original', 错误: $($_.Exception.Message)"
        return $original
    }
}

# 比较版本号
function Compare-Versions {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Version1,

        [Parameter(Mandatory=$true)]
        [string]$Version2
    )

    if ([string]::IsNullOrEmpty($Version1) -or [string]::IsNullOrEmpty($Version2)) {
        Write-DebugLog "版本号为空，无法比较: '$Version1' vs '$Version2'"
        return $null
    }

    Write-DebugLog "比较版本号: '$Version1' vs '$Version2'"

    try {
        $v1 = Normalize-Version -VersionString $Version1
        $v2 = Normalize-Version -VersionString $Version2

        if (-not $v1 -or -not $v2) {
            return $null
        }

        $v1Parts = $v1 -split '\.' | ForEach-Object { [int]$_ }
        $v2Parts = $v2 -split '\.' | ForEach-Object { [int]$_ }

        # 确保长度相同
        $maxLength = [Math]::Max($v1Parts.Count, $v2Parts.Count)
        while ($v1Parts.Count -lt $maxLength) { $v1Parts += 0 }
        while ($v2Parts.Count -lt $maxLength) { $v2Parts += 0 }

        # 逐部分比较
        for ($i = 0; $i -lt $maxLength; $i++) {
            if ($v1Parts[$i] -gt $v2Parts[$i]) {
                Write-DebugLog "版本比较结果: $Version1 > $Version2"
                return 1  # v1 > v2
            }
            if ($v1Parts[$i] -lt $v2Parts[$i]) {
                Write-DebugLog "版本比较结果: $Version1 < $Version2"
                return -1  # v1 < v2
            }
        }

        Write-DebugLog "版本比较结果: $Version1 = $Version2"
        return 0  # 相等
    }
    catch {
        Write-WarnLog "版本比较失败: '$Version1' vs '$Version2', 错误: $($_.Exception.Message)"
        return $null
    }
}

# 检测本地版本
function Get-LocalVersion {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SoftwareName,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$SoftwareConfig,

        [string]$InstallHome = $null
    )

    # 检查缓存
    $cacheKey = "$SoftwareName|$InstallHome"
    if ($global:VERSION_CACHE.ContainsKey($cacheKey)) {
        Write-DebugLog "使用缓存的本地版本: $SoftwareName"
        return $global:VERSION_CACHE[$cacheKey]
    }

    Write-InfoLog "检测本地版本: $SoftwareName"

    $localVersion = $null

    try {
        # 首先尝试通过版本检查配置
        if ($SoftwareConfig.versionCheck) {
            $versionConfig = $SoftwareConfig.versionCheck

            switch ($versionConfig.type) {
                "command" {
                    # 通过命令获取版本
                    if ($versionConfig.command) {
                        Write-DebugLog "通过命令获取版本: $($versionConfig.command)"
                        $commandOutput = Invoke-Expression $versionConfig.command 2>$null

                        if ($commandOutput) {
                            # 使用正则表达式提取版本号
                            if ($versionConfig.pattern) {
                                if ($commandOutput -match $versionConfig.pattern) {
                                    $localVersion = $matches[1]
                                }
                            } else {
                                # 尝试提取常见的版本号格式
                                if ($commandOutput -match 'v?(\d+(?:\.\d+)*)') {
                                    $localVersion = $matches[1]
                                }
                            }
                        }
                    }
                }
                "fileVersion" {
                    # 通过文件版本信息获取
                    if ($versionConfig.filePath) {
                        $filePath = $versionConfig.filePath

                        # 如果提供了安装目录，使用完整路径
                        if ($InstallHome -and -not [System.IO.Path]::IsPathRooted($filePath)) {
                            $filePath = Join-Path $InstallHome $filePath
                        }

                        Write-DebugLog "通过文件版本获取: $filePath"

                        if (Test-Path $filePath) {
                            $fileVersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($filePath)
                            $localVersion = $fileVersionInfo.ProductVersion
                            if (-not $localVersion) {
                                $localVersion = $fileVersionInfo.FileVersion
                            }
                        }
                    }
                }
                "regex" {
                    # 通过正则表达式从文件中提取
                    if ($versionConfig.filePath -and $versionConfig.pattern) {
                        $filePath = $versionConfig.filePath

                        if ($InstallHome -and -not [System.IO.Path]::IsPathRooted($filePath)) {
                            $filePath = Join-Path $InstallHome $filePath
                        }

                        Write-DebugLog "通过正则表达式从文件获取: $filePath"

                        if (Test-Path $filePath) {
                            $fileContent = Get-Content -Path $filePath -Raw
                            if ($fileContent -match $versionConfig.pattern) {
                                $localVersion = $matches[1]
                            }
                        }
                    }
                }
            }
        }

        # 如果版本检查配置未提供或未成功，尝试通用方法
        if (-not $localVersion -and $InstallHome) {
            Write-DebugLog "尝试通用版本检测方法"

            # 1. 查找可执行文件并尝试获取版本
            $exeFiles = @("$SoftwareName.exe", "${SoftwareName}.exe")
            foreach ($exeFile in $exeFiles) {
                $exePath = Join-Path $InstallHome $exeFile
                if (Test-Path $exePath) {
                    try {
                        $fileVersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
                        $localVersion = $fileVersionInfo.ProductVersion
                        if (-not $localVersion) {
                            $localVersion = $fileVersionInfo.FileVersion
                        }
                        if ($localVersion) {
                            Write-DebugLog "通过文件版本信息获取: $localVersion"
                            break
                        }
                    }
                    catch {
                        Write-DebugLog "无法获取文件版本信息: $exePath"
                    }
                }
            }

            # 2. 尝试运行程序并获取版本（常见参数: -v, --version, /version）
            if (-not $localVersion) {
                $exePath = Join-Path $InstallHome "$SoftwareName.exe"
                if (Test-Path $exePath) {
                    $versionArgs = @("-v", "--version", "/version", "-version")
                    foreach ($arg in $versionArgs) {
                        try {
                            $output = & $exePath $arg 2>&1
                            if ($output -and $output -match 'v?(\d+(?:\.\d+)*)') {
                                $localVersion = $matches[1]
                                Write-DebugLog "通过命令行参数 $arg 获取: $localVersion"
                                break
                            }
                        }
                        catch {
                            # 继续尝试下一个参数
                        }
                    }
                }
            }
        }

        # 3. 如果软件已安装但不在预期位置，尝试在PATH中查找
        if (-not $localVersion) {
            Write-DebugLog "尝试在PATH中查找软件"
            $command = Get-Command $SoftwareName -ErrorAction SilentlyContinue
            if ($command) {
                $exePath = $command.Source
                try {
                    $fileVersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
                    $localVersion = $fileVersionInfo.ProductVersion
                    if (-not $localVersion) {
                        $localVersion = $fileVersionInfo.FileVersion
                    }
                    if ($localVersion) {
                        Write-DebugLog "通过PATH中的文件获取: $localVersion"
                    }
                }
                catch {
                    Write-DebugLog "无法获取PATH中文件的版本信息: $exePath"
                }
            }
        }

        if ($localVersion) {
            $localVersion = $localVersion.Trim()
            Write-InfoLog "检测到本地版本: $localVersion"

            # 缓存结果
            $global:VERSION_CACHE[$cacheKey] = $localVersion
        } else {
            Write-InfoLog "未检测到本地版本，可能是首次安装"
        }

        return $localVersion
    }
    catch {
        Write-ErrorLog "检测本地版本失败: $($_.Exception.Message)" -Exception $_
        return $null
    }
}

# 判断是否需要更新
function Should-Update {
    param(
        [string]$LocalVersion,
        [string]$RemoteVersion,
        [bool]$Force = $false,
        [bool]$InstallIfNotFound = $false
    )

    Write-DebugLog "判断是否需要更新 - 本地: '$LocalVersion', 远程: '$RemoteVersion', 强制: $Force, 安装未找到: $InstallIfNotFound"

    # 如果强制更新，直接返回true
    if ($Force) {
        Write-InfoLog "强制更新模式，将进行更新"
        return $true
    }

    # 如果本地没有安装
    if ([string]::IsNullOrEmpty($LocalVersion)) {
        if ($InstallIfNotFound) {
            Write-InfoLog "软件未安装，将进行首次安装"
            return $true
        } else {
            Write-InfoLog "软件未安装且未启用自动安装，跳过"
            return $false
        }
    }

    # 比较版本
    $comparison = Compare-Versions -Version1 $LocalVersion -Version2 $RemoteVersion

    if ($null -eq $comparison) {
        Write-WarnLog "无法比较版本号，假设需要更新"
        return $true
    }

    if ($comparison -lt 0) {
        Write-InfoLog "发现新版本: $RemoteVersion (当前: $LocalVersion)"
        return $true
    } elseif ($comparison -eq 0) {
        Write-InfoLog "已是最新版本: $RemoteVersion"
        return $false
    } else {
        Write-WarnLog "本地版本比远程版本新: $LocalVersion > $RemoteVersion"
        return $false
    }
}

# 获取版本信息摘要
function Get-VersionSummary {
    param(
        [string]$SoftwareName,
        [string]$LocalVersion,
        [string]$RemoteVersion,
        [bool]$UpdateNeeded
    )

    $summary = @{
        Software = $SoftwareName
        LocalVersion = if ($LocalVersion) { $LocalVersion } else { "未安装" }
        RemoteVersion = $RemoteVersion
        UpdateNeeded = $UpdateNeeded
        Status = if ($UpdateNeeded) { "需要更新" } else { "已是最新" }
    }

    return $summary
}

# 清空版本缓存
function Clear-VersionCache {
    param([string]$SoftwareName = $null)

    if ($SoftwareName) {
        $keysToRemove = @()
        foreach ($key in $global:VERSION_CACHE.Keys) {
            if ($key -match "^$([regex]::Escape($SoftwareName))") {
                $keysToRemove += $key
            }
        }

        foreach ($key in $keysToRemove) {
            $global:VERSION_CACHE.Remove($key)
        }

        if ($keysToRemove.Count -gt 0) {
            Write-DebugLog "已清除 $($keysToRemove.Count) 个版本缓存项: $SoftwareName"
        }
    } else {
        $global:VERSION_CACHE.Clear()
        Write-InfoLog "已清除所有版本缓存"
    }
}

# 验证版本号格式
function Test-VersionFormat {
    param(
        [Parameter(Mandatory=$true)]
        [string]$VersionString
    )

    if ([string]::IsNullOrWhiteSpace($VersionString)) {
        return $false
    }

    # 移除前导v
    $version = $VersionString -replace '^[vV]', ''

    # 检查是否匹配常见的版本号格式
    if ($version -match '^\d+(?:\.\d+)*$') {
        return $true
    }

    return $false
}

# 导出模块函数
Export-ModuleMember -Function @(
    'Get-LocalVersion',
    'Compare-Versions',
    'Should-Update',
    'Normalize-Version',
    'Get-VersionSummary',
    'Clear-VersionCache',
    'Test-VersionFormat'
)