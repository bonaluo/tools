# GitHub通用更新脚本 - 主入口
# 版本: 1.0.0
# 描述: 基于配置文件从GitHub release更新本地软件的通用脚本

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$ConfigPath,

    [Parameter(Position=1)]
    [string]$Software,

    [switch]$Force,
    [switch]$Help,
    [switch]$List,
    [switch]$Version
)

# 脚本信息
$SCRIPT_VERSION = "1.0.0"
$SCRIPT_NAME = "github-update"
$SCRIPT_AUTHOR = "通用更新脚本"
$SCRIPT_DESCRIPTION = "基于配置文件从GitHub release更新本地软件的通用脚本"

# 初始化日志级别
if ($PSBoundParameters.ContainsKey('Verbose') -and $PSBoundParameters['Verbose']) {
    $global:LOG_LEVEL = "DEBUG"
} else {
    $global:LOG_LEVEL = "INFO"
}

# 显示帮助信息
function Show-Help {
    Write-Host @"
GitHub通用更新脚本 v$SCRIPT_VERSION

用法: .\Main.ps1 [-ConfigPath <路径>] [-Software <软件名>] [-Force] [-Verbose] [-Help] [-List] [-Version]

参数:
  -ConfigPath <路径>   配置文件的路径（默认: ~/.auto-update/config.json）
  -Software <软件名>   指定要更新的软件名称（默认: 更新所有配置的软件）
  -Force               强制更新，即使版本相同也重新安装
  -Verbose             显示详细日志信息
  -Help                显示此帮助信息
  -List                列出配置中的所有软件
  -Version             显示脚本版本信息

示例:
  .\Main.ps1                          # 更新所有配置的软件
  .\Main.ps1 -Software ddns-go       # 只更新ddns-go
  .\Main.ps1 -ConfigPath "C:\config.json" -Verbose  # 使用指定配置文件并显示详细日志
  .\Main.ps1 -List                   # 列出所有可更新的软件

配置文件:
  默认配置文件: ~/.auto-update/config.json
  支持JSONC格式（支持注释）
  参考: Examples/config.example.jsonc

注意事项:
  - 需要PowerShell 5.1或更高版本
  - 某些操作需要管理员权限
  - 确保网络连接正常以访问GitHub API
"@
}

# 显示版本信息
function Show-Version {
    Write-Host @"
$SCRIPT_NAME v$SCRIPT_VERSION
$SCRIPT_DESCRIPTION
作者: $SCRIPT_AUTHOR
"@
}

# 更新单个软件
function Update-Software {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SoftwareName,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$SoftwareConfig,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config,

        [bool]$Force = $false
    )

    Write-InfoLog "开始更新软件: $SoftwareName"

    $result = @{
        SoftwareName = $SoftwareName
        Success = $false
        LocalVersion = $null
        RemoteVersion = $null
        InstallDir = $null
        Error = $null
        Details = $null
    }

    try {
        # 1. 解析安装目录
        $installDir = Resolve-InstallHome -SoftwareConfig $SoftwareConfig -ThrowIfNotFound $false
        $result.InstallDir = $installDir

        # 2. 检测本地版本
        $localVersion = Get-LocalVersion -SoftwareName $SoftwareName -SoftwareConfig $SoftwareConfig -InstallHome $installDir
        $result.LocalVersion = $localVersion

        # 3. 获取远程版本信息
        Write-InfoLog "获取GitHub release信息..."
        $latestRelease = Get-LatestRelease -RepoUrl $SoftwareConfig.repoUrl -Config $Config -IncludePrerelease $false
        $remoteVersion = $latestRelease.tag_name
        $result.RemoteVersion = $remoteVersion

        Write-InfoLog "本地版本: $localVersion, 远程版本: $remoteVersion"

        # 4. 判断是否需要更新
        $updateNeeded = Should-Update -LocalVersion $localVersion -RemoteVersion $remoteVersion -Force $Force -InstallIfNotFound $SoftwareConfig.installIfNotFound

        if (-not $updateNeeded) {
            Write-InfoLog "不需要更新: $SoftwareName"
            $result.Success = $true
            $result.Details = "Already up to date"
            return $result
        }

        # 5. 获取下载URL
        Write-InfoLog "查找匹配的下载文件..."
        $downloadUrl = Get-ReleaseDownloadUrl -Release $latestRelease -SuffixPattern $SoftwareConfig.suffix -SoftwareName $SoftwareName

        # 6. 下载文件
        Write-InfoLog "下载文件: $downloadUrl"

        # 创建临时目录
        $tempDir = Join-Path $env:TEMP "github-update-$SoftwareName-$(Get-Date -Format 'yyyyMMddHHmmss')"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        $downloadPath = Join-Path $tempDir (Split-Path $downloadUrl -Leaf)

        $downloadSuccess = Download-File -Url $downloadUrl -OutputPath $downloadPath -Retries 3
        if (-not $downloadSuccess) {
            throw "下载文件失败"
        }

        # 7. 安装软件
        Write-InfoLog "开始安装..."
        $installResult = Install-Software -SoftwareName $SoftwareName -SoftwareConfig $SoftwareConfig -AssetPath $downloadPath -InstallDir $installDir -Force:$Force -CreateBackup $true

        if (-not $installResult.Success) {
            throw "安装失败: $($installResult.Error)"
        }

        # 8. 执行后处理脚本
        Write-InfoLog "执行后处理脚本..."
        $postProcessResult = Complete-PostProcessing -SoftwareConfig $SoftwareConfig -SoftwareName $SoftwareName -InstallDir $installDir -Version $remoteVersion -AssetPath $downloadPath

        # 9. 验证安装
        Write-InfoLog "验证安装..."
        $validation = Test-Installation -SoftwareName $SoftwareName -InstallDir $installDir -SoftwareConfig $SoftwareConfig

        if (-not $validation.IsValid) {
            Write-WarnLog "安装验证失败: $($validation.Errors -join ', ')"
        }

        # 10. 清理临时文件（保留下载文件用于后处理）
        Write-InfoLog "清理临时文件..."
        Cleanup-TempFiles -TempFiles @($tempDir) | Out-Null

        # 更新成功
        $result.Success = $true
        $result.Details = @{
            InstallResult = $installResult
            PostProcessResult = $postProcessResult
            Validation = $validation
        }

        Write-InfoLog "软件更新成功: $SoftwareName"
        return $result
    }
    catch {
        $errorMsg = "更新软件 '$SoftwareName' 失败: $($_.Exception.Message)"
        Write-ErrorLog $errorMsg -Exception $_

        $result.Success = $false
        $result.Error = $errorMsg

        return $result
    }
}
function Main {
    # 处理帮助和版本参数
    if ($Help) {
        Show-Help
        return
    }

    if ($Version) {
        Show-Version
        return
    }

    Write-Host "GitHub通用更新脚本 v$SCRIPT_VERSION"
    Write-Host "=========================================="

    # 加载模块
    Write-Host "正在加载模块..." -ForegroundColor Cyan
    try {
        # 模块路径
        $modulesPath = Join-Path $PSScriptRoot "Modules"

        # 加载所有模块（按依赖顺序）
        $modules = @(
            "Logging.psm1",
            "Config.psm1",
            "GitHub.psm1",
            "Version.psm1",
            "Download.psm1",
            "Install.psm1",
            "PostProcess.psm1"
        )

        foreach ($module in $modules) {
            $modulePath = Join-Path $modulesPath $module
            Write-Host "  - 加载 $module" -ForegroundColor Gray

            try {
                Import-Module -Name $modulePath -Force -ErrorAction Stop
            }
            catch {
                $errorMsg = "加载模块失败: $module, 错误: $($_.Exception.Message)"
                Write-Host "错误: $errorMsg" -ForegroundColor Red
                return 1
            }
        }

        Write-Host "模块加载完成" -ForegroundColor Green
    }
    catch {
        Write-Host "错误: 加载模块失败 - $_" -ForegroundColor Red
        return 1
    }

    # 设置日志级别（模块加载后）
    if ($PSBoundParameters.ContainsKey('Verbose') -and $PSBoundParameters['Verbose']) {
        $global:LOG_LEVEL = "DEBUG"
        Write-InfoLog "启用详细日志模式"
    } else {
        $global:LOG_LEVEL = "INFO"
    }

    # 确定配置文件路径
    if ([string]::IsNullOrEmpty($ConfigPath)) {
        # 使用默认路径: 首先检查~/.auto-update/config.json
        $userProfile = [Environment]::GetFolderPath("UserProfile")
        $defaultConfig = Join-Path $userProfile ".auto-update\config.json"

        # 然后检查项目中的配置文件
        $projectConfig = "..\..\配置\github\release\update.jsonc"

        if (Test-Path $defaultConfig) {
            $ConfigPath = $defaultConfig
            Write-Host "使用默认配置文件: $ConfigPath"
        } elseif (Test-Path $projectConfig) {
            $ConfigPath = $projectConfig
            Write-Host "使用项目配置文件: $ConfigPath"
        } else {
            Write-Host "错误: 未找到配置文件" -ForegroundColor Red
            Write-Host "请使用-ConfigPath参数指定配置文件路径，或创建默认配置文件:" -ForegroundColor Yellow
            Write-Host "  ~/.auto-update/config.json" -ForegroundColor Yellow
            Write-Host "或使用示例配置文件: Examples/config.example.jsonc" -ForegroundColor Yellow
            return 1
        }
    }

    # 检查配置文件是否存在
    if (!(Test-Path $ConfigPath)) {
        Write-Host "错误: 配置文件不存在: $ConfigPath" -ForegroundColor Red
        return 1
    }

    Write-Host "使用配置文件: $ConfigPath"

    # 列出软件（如果指定了-List参数）
    if ($List) {
        Write-InfoLog "列出配置中的软件"

        try {
            $config = Read-ConfigFile -ConfigPath $ConfigPath
            $softwareList = Get-SoftwareConfig -Config $config

            Write-Host "`n配置中的软件列表:" -ForegroundColor Cyan
            Write-Host "==============================="

            foreach ($software in $softwareList) {
                Write-Host "名称: $($software.Name)" -ForegroundColor Yellow
                Write-Host "  仓库: $($software.Config.repoUrl)"

                # 尝试获取本地版本
                try {
                    $installDir = Resolve-InstallHome -SoftwareConfig $software.Config -ThrowIfNotFound $false
                    $localVersion = Get-LocalVersion -SoftwareName $software.Name -SoftwareConfig $software.Config -InstallHome $installDir

                    if ($localVersion) {
                        Write-Host "  本地版本: $localVersion" -ForegroundColor Green
                    } else {
                        Write-Host "  本地版本: 未安装" -ForegroundColor Gray
                    }
                }
                catch {
                    Write-Host "  本地版本: 检测失败" -ForegroundColor Red
                }

                Write-Host ""
            }

            Write-Host "总计: $($softwareList.Count) 个软件" -ForegroundColor Cyan
            return 0
        }
        catch {
            Write-ErrorLog "列出软件失败: $($_.Exception.Message)" -Exception $_
            Write-Host "错误: 列出软件失败 - $($_.Exception.Message)" -ForegroundColor Red
            return 1
        }
    }

    # 执行更新
    Write-InfoLog "开始更新流程"

    # 读取配置文件
    try {
        $config = Read-ConfigFile -ConfigPath $ConfigPath
    }
    catch {
        Write-ErrorLog "读取配置文件失败: $($_.Exception.Message)" -Exception $_
        Write-Host "错误: 读取配置文件失败 - $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }

    # 获取要更新的软件列表
    $softwareList = Get-SoftwareConfig -Config $config

    # 如果指定了特定软件，进行过滤
    if (-not [string]::IsNullOrEmpty($Software)) {
        $softwareList = $softwareList | Where-Object { $_.Name -eq $Software }
        if ($softwareList.Count -eq 0) {
            Write-ErrorLog "软件未在配置中找到: $Software"
            Write-Host "错误: 软件 '$Software' 未在配置中找到" -ForegroundColor Red
            return 1
        }
    }

    Write-InfoLog "将更新 $($softwareList.Count) 个软件"

    $results = @()
    $successCount = 0
    $failCount = 0

    foreach ($softwareItem in $softwareList) {
        $softwareName = $softwareItem.Name
        $softwareConfig = $softwareItem.Config

        Write-Host "`n==========================================" -ForegroundColor Cyan
        Write-Host "软件: $softwareName" -ForegroundColor Yellow
        Write-Host "==========================================" -ForegroundColor Cyan

        $softwareResult = Update-Software -SoftwareName $softwareName -SoftwareConfig $softwareConfig -Config $config -Force:$Force
        $results += $softwareResult

        if ($softwareResult.Success) {
            $successCount++
            Write-Host "更新成功: $softwareName" -ForegroundColor Green
        } else {
            $failCount++
            Write-Host "更新失败: $softwareName" -ForegroundColor Red
        }
    }

    # 输出汇总报告
    Write-Host "`n==========================================" -ForegroundColor Cyan
    Write-Host "更新汇总报告" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "总计软件: $($softwareList.Count)" -ForegroundColor White
    Write-Host "成功更新: $successCount" -ForegroundColor Green
    Write-Host "失败更新: $failCount" -ForegroundColor Red

    foreach ($result in $results) {
        $statusColor = if ($result.Success) { "Green" } else { "Red" }
        $statusText = if ($result.Success) { "成功" } else { "失败" }

        Write-Host "`n$($result.SoftwareName): " -ForegroundColor White -NoNewline
        Write-Host $statusText -ForegroundColor $statusColor

        if ($result.LocalVersion) {
            Write-Host "  本地版本: $($result.LocalVersion)" -ForegroundColor Gray
        }

        if ($result.RemoteVersion) {
            Write-Host "  远程版本: $($result.RemoteVersion)" -ForegroundColor Gray
        }

        if ($result.InstallDir) {
            Write-Host "  安装目录: $($result.InstallDir)" -ForegroundColor Gray
        }

        if (-not $result.Success -and $result.Error) {
            Write-Host "  错误信息: $($result.Error)" -ForegroundColor Red
        }
    }

    Write-Host "`n==========================================" -ForegroundColor Cyan
    if ($failCount -eq 0) {
        Write-Host "所有软件更新完成！" -ForegroundColor Green
        return 0
    } else {
        Write-Host "部分软件更新失败，请检查错误信息" -ForegroundColor Yellow
        return 1
    }
}

# 脚本入口点
try {
    $exitCode = Main
    exit $exitCode
}
catch {
    Write-Host "未处理的错误: $_" -ForegroundColor Red
    Write-Host "堆栈跟踪: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}