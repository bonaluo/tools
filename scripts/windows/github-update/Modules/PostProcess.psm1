# PostProcess.psm1 - 后处理模块
# 提供后处理脚本执行、变量替换、服务重启和临时文件清理功能

# 导入日志模块
if (-not (Get-Module -Name "Logging" -ErrorAction SilentlyContinue)) {
    try {
        Import-Module -Name "$PSScriptRoot\Logging.psm1" -Force -ErrorAction Stop
    }
    catch {
        Write-Host "警告: 无法加载日志模块，使用简化日志输出" -ForegroundColor Yellow
    }
}

# 执行后处理脚本
function Execute-PostScripts {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$SoftwareConfig,

        [Parameter(Mandatory=$true)]
        [string]$SoftwareName,

        [string]$InstallDir,

        [string]$Version,

        [string]$AssetPath,

        [bool]$DryRun = $false
    )

    Write-InfoLog "执行后处理脚本"

    # 检查是否有后处理脚本配置
    $scripts = $SoftwareConfig.extra.scripts.after
    if (-not $scripts -or $scripts.Count -eq 0) {
        Write-InfoLog "没有配置后处理脚本"
        return @{
            Success = $true
            ExecutedCount = 0
            Results = @()
        }
    }

    Write-InfoLog "找到 $($scripts.Count) 个后处理脚本"

    $results = @()
    $executedCount = 0

    # 准备变量替换
    $variables = @{
        'installHome' = $InstallDir
        'version' = $Version
        'assetPath' = $AssetPath
        'softwareName' = $SoftwareName
        'tempDir' = $env:TEMP
    }

    foreach ($script in $scripts) {
        $scriptIndex = $executedCount + 1
        Write-InfoLog "执行脚本 $scriptIndex/$($scripts.Count): $script"

        try {
            # 替换变量
            $resolvedScript = Replace-Variables -Text $script -Variables $variables

            if ($DryRun) {
                Write-InfoLog "干运行模式，跳过执行: $resolvedScript"
                $results += @{
                    Script = $script
                    ResolvedScript = $resolvedScript
                    Success = $null
                    DryRun = $true
                }
                $executedCount++
                continue
            }

            # 执行脚本
            Write-DebugLog "执行命令: $resolvedScript"

            # 记录开始时间
            $startTime = Get-Date

            # 根据脚本类型执行
            $scriptResult = Execute-ScriptCommand -Command $resolvedScript

            # 记录执行时间
            $elapsed = ((Get-Date) - $startTime).TotalSeconds

            $scriptResult.Script = $script
            $scriptResult.ResolvedScript = $resolvedScript
            $scriptResult.ElapsedSeconds = $elapsed

            $results += $scriptResult

            if ($scriptResult.Success) {
                Write-InfoLog "脚本执行成功 ($([Math]::Round($elapsed, 2)) 秒)"
                $executedCount++
            } else {
                Write-ErrorLog "脚本执行失败: $($scriptResult.Error)"

                # 根据配置决定是否继续执行后续脚本
                $stopOnError = if ($SoftwareConfig.extra.scripts.stopOnError) {
                    $SoftwareConfig.extra.scripts.stopOnError
                } else {
                    $true  # 默认在错误时停止
                }

                if ($stopOnError) {
                    Write-WarnLog "由于脚本执行失败，停止执行后续脚本"
                    break
                } else {
                    Write-WarnLog "继续执行后续脚本"
                    $executedCount++
                }
            }
        }
        catch {
            Write-ErrorLog "执行脚本时出错: $($_.Exception.Message)" -Exception $_

            $results += @{
                Script = $script
                Success = $false
                Error = $_.Exception.Message
                Exception = $_
            }

            # 根据配置决定是否继续
            $stopOnError = if ($SoftwareConfig.extra.scripts.stopOnError) {
                $SoftwareConfig.extra.scripts.stopOnError
            } else {
                $true
            }

            if ($stopOnError) {
                Write-WarnLog "由于执行出错，停止执行后续脚本"
                break
            }
        }
    }

    $success = $executedCount -eq $scripts.Count

    return @{
        Success = $success
        ExecutedCount = $executedCount
        TotalCount = $scripts.Count
        Results = $results
    }
}

# 变量替换
function Replace-Variables {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Text,

        [hashtable]$Variables = @{}
    )

    $result = $Text

    foreach ($key in $Variables.Keys) {
        $value = $Variables[$key]

        # 替换 %VAR% 格式
        $result = $result -replace "%$key%", $value

        # 替换 ${VAR} 格式
        $result = $result -replace "\${$key\}", $value

        # 替换 $(VAR) 格式（某些脚本格式）
        $result = $result -replace "\$\($key\)", $value
    }

    # 替换常见环境变量
    $result = $result -replace "%TEMP%", $env:TEMP
    $result = $result -replace "%APPDATA%", $env:APPDATA
    $result = $result -replace "%PROGRAMFILES%", ${env:ProgramFiles}
    $result = $result -replace "%PROGRAMFILES(X86)%", ${env:ProgramFiles(x86)}
    $result = $result -replace "%USERPROFILE%", $env:USERPROFILE
    $result = $result -replace "%WINDIR%", $env:WINDIR
    $result = $result -replace "%SYSTEMROOT%", $env:SystemRoot

    # 确保路径使用正确的分隔符
    $result = $result -replace '/', '\'

    # 移除多余的路径分隔符
    $result = $result -replace '\\\\+', '\'

    Write-DebugLog "变量替换: '$Text' -> '$result'"

    return $result
}

# 执行脚本命令
function Execute-ScriptCommand {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Command
    )

    try {
        # 尝试判断命令类型
        $commandLower = $Command.Trim().ToLower()

        # 如果是PowerShell命令（以特定关键字开头）
        $isPowerShell = $commandLower -match '^powershell|^pwsh|^\.\\|^\./'

        # 如果是批处理命令
        $isBatch = $commandLower -match '^cmd|^\.bat|^\.cmd'

        # 如果是可执行文件
        $isExecutable = $commandLower -match '\.(exe|msi|bat|cmd|ps1)$'

        if ($isPowerShell) {
            # 执行PowerShell命令
            Write-DebugLog "检测到PowerShell命令"

            # 移除可能的powershell前缀
            $psCommand = $Command
            if ($psCommand -match '^powershell\s+(.+)$') {
                $psCommand = $matches[1]
            } elseif ($psCommand -match '^pwsh\s+(.+)$') {
                $psCommand = $matches[1]
            }

            # 执行PowerShell命令
            $output = Invoke-Expression $psCommand 2>&1
            $success = $? -eq $true

            return @{
                Success = $success
                Output = if ($output) { $output | Out-String } else { "" }
                Error = if (-not $success) { $Error[0] } else { $null }
                CommandType = "PowerShell"
            }
        }
        elseif ($isBatch) {
            # 执行批处理命令
            Write-DebugLog "检测到批处理命令"

            $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$Command`"" -Wait -NoNewWindow -PassThru -RedirectStandardOutput "output.txt" -RedirectStandardError "error.txt"

            $output = Get-Content "output.txt" -ErrorAction SilentlyContinue
            $errorOutput = Get-Content "error.txt" -ErrorAction SilentlyContinue

            # 清理临时文件
            Remove-Item "output.txt" -ErrorAction SilentlyContinue
            Remove-Item "error.txt" -ErrorAction SilentlyContinue

            $success = $process.ExitCode -eq 0

            return @{
                Success = $success
                Output = if ($output) { $output -join "`n" } else { "" }
                Error = if ($errorOutput) { $errorOutput -join "`n" } else { $null }
                ExitCode = $process.ExitCode
                CommandType = "Batch"
            }
        }
        else {
            # 直接执行命令
            Write-DebugLog "执行通用命令"

            try {
                # 尝试使用Invoke-Expression
                $output = Invoke-Expression $Command 2>&1

                if ($LASTEXITCODE -ne 0) {
                    return @{
                        Success = $false
                        Output = if ($output) { $output | Out-String } else { "" }
                        Error = "命令返回非零退出代码: $LASTEXITCODE"
                        ExitCode = $LASTEXITCODE
                        CommandType = "Generic"
                    }
                }

                return @{
                    Success = $true
                    Output = if ($output) { $output | Out-String } else { "" }
                    Error = $null
                    ExitCode = 0
                    CommandType = "Generic"
                }
            }
            catch {
                # Invoke-Expression失败，尝试使用Start-Process
                Write-DebugLog "Invoke-Expression失败，尝试Start-Process: $($_.Exception.Message)"

                # 提取可执行文件和参数
                $commandParts = $Command -split '\s+', 2
                $executable = $commandParts[0]
                $arguments = if ($commandParts.Count -gt 1) { $commandParts[1] } else { "" }

                if (Test-Path $executable) {
                    $process = Start-Process -FilePath $executable -ArgumentList $arguments -Wait -NoNewWindow -PassThru

                    return @{
                        Success = ($process.ExitCode -eq 0)
                        Output = ""
                        Error = if ($process.ExitCode -ne 0) { "退出代码: $($process.ExitCode)" } else { $null }
                        ExitCode = $process.ExitCode
                        CommandType = "Executable"
                    }
                } else {
                    # 最后尝试作为shell命令执行
                    Write-DebugLog "尝试作为shell命令执行"

                    $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$Command`"" -Wait -NoNewWindow -PassThru -RedirectStandardOutput "output.txt" -RedirectStandardError "error.txt"

                    $output = Get-Content "output.txt" -ErrorAction SilentlyContinue
                    $errorOutput = Get-Content "error.txt" -ErrorAction SilentlyContinue

                    Remove-Item "output.txt" -ErrorAction SilentlyContinue
                    Remove-Item "error.txt" -ErrorAction SilentlyContinue

                    return @{
                        Success = ($process.ExitCode -eq 0)
                        Output = if ($output) { $output -join "`n" } else { "" }
                        Error = if ($errorOutput) { $errorOutput -join "`n" } else { $null }
                        ExitCode = $process.ExitCode
                        CommandType = "Shell"
                    }
                }
            }
        }
    }
    catch {
        Write-ErrorLog "执行命令失败: $($_.Exception.Message)" -Exception $_

        return @{
            Success = $false
            Output = ""
            Error = $_.Exception.Message
            Exception = $_
            CommandType = "Unknown"
        }
    }
}

# 重启服务
function Restart-ServiceIfNeeded {
    param(
        [PSCustomObject]$SoftwareConfig,

        [string]$ServiceName,

        [bool]$Force = $false
    )

    # 从配置中获取服务名
    if ([string]::IsNullOrEmpty($ServiceName)) {
        $ServiceName = $SoftwareConfig.extra.restartService
    }

    if ([string]::IsNullOrEmpty($ServiceName)) {
        Write-DebugLog "未配置需要重启的服务"
        return @{
            Success = $true
            Restarted = $false
            ServiceName = $null
        }
    }

    Write-InfoLog "检查服务: $ServiceName"

    try {
        # 检查服务是否存在
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-WarnLog "服务不存在: $ServiceName"
            return @{
                Success = $false
                Restarted = $false
                ServiceName = $ServiceName
                Error = "服务不存在"
            }
        }

        Write-InfoLog "服务状态: $($service.Status)"

        # 检查是否需要重启
        $shouldRestart = $Force -or ($service.Status -eq 'Running')

        if ($shouldRestart) {
            Write-InfoLog "重启服务: $ServiceName"

            # 停止服务
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            Write-InfoLog "服务已停止"

            # 等待服务停止
            $maxWait = 30  # 秒
            $waitCount = 0
            while ($service.Status -ne 'Stopped' -and $waitCount -lt $maxWait) {
                Start-Sleep -Seconds 1
                $service.Refresh()
                $waitCount++
            }

            if ($service.Status -eq 'Stopped') {
                Write-InfoLog "服务成功停止"
            } else {
                Write-WarnLog "服务停止超时，状态: $($service.Status)"
            }

            # 启动服务
            Start-Service -Name $ServiceName -ErrorAction Stop
            Write-InfoLog "服务已启动"

            # 等待服务启动
            $waitCount = 0
            while ($service.Status -ne 'Running' -and $waitCount -lt $maxWait) {
                Start-Sleep -Seconds 1
                $service.Refresh()
                $waitCount++
            }

            if ($service.Status -eq 'Running') {
                Write-InfoLog "服务成功启动"
                return @{
                    Success = $true
                    Restarted = $true
                    ServiceName = $ServiceName
                    OriginalStatus = $service.Status
                }
            } else {
                Write-WarnLog "服务启动超时，状态: $($service.Status)"
                return @{
                    Success = $false
                    Restarted = $true
                    ServiceName = $ServiceName
                    Error = "服务启动超时"
                    CurrentStatus = $service.Status
                }
            }
        } else {
            Write-InfoLog "服务未运行，无需重启"
            return @{
                Success = $true
                Restarted = $false
                ServiceName = $ServiceName
                OriginalStatus = $service.Status
            }
        }
    }
    catch {
        Write-ErrorLog "重启服务失败: $($_.Exception.Message)" -Exception $_

        return @{
            Success = $false
            Restarted = $false
            ServiceName = $ServiceName
            Error = $_.Exception.Message
        }
    }
}

# 清理临时文件
function Cleanup-TempFiles {
    param(
        [string[]]$TempFiles,

        [int]$MaxAgeDays = 7,

        [bool]$CleanAll = $false
    )

    Write-InfoLog "清理临时文件"

    $cleanedCount = 0
    $errors = @()
    $totalSize = 0

    try {
        if ($CleanAll) {
            # 清理所有github-update相关的临时文件
            $tempDir = $env:TEMP
            $pattern = "github-update-*"

            $tempItems = Get-ChildItem -Path $tempDir -Filter $pattern -Directory -ErrorAction SilentlyContinue

            foreach ($item in $tempItems) {
                try {
                    # 检查文件年龄
                    $age = (Get-Date) - $item.LastWriteTime
                    if ($age.TotalDays -ge $MaxAgeDays) {
                        $size = if ($item.PSIsContainer) {
                            (Get-ChildItem -Path $item.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                        } else {
                            $item.Length
                        }

                        Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                        $cleanedCount++
                        $totalSize += ($size / 1MB)
                        Write-DebugLog "清理临时目录: $($item.Name) (大小: $([Math]::Round($size/1MB, 2)) MB)"
                    }
                }
                catch {
                    $errors += "清理 $($item.Name) 失败: $($_.Exception.Message)"
                    Write-WarnLog "清理临时文件失败: $($item.Name), 错误: $($_.Exception.Message)"
                }
            }
        }
        else {
            # 清理指定的临时文件
            foreach ($tempFile in $TempFiles) {
                if (Test-Path $tempFile) {
                    try {
                        $size = if (Test-Path $tempFile -PathType Container) {
                            (Get-ChildItem -Path $tempFile -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                        } else {
                            (Get-Item $tempFile).Length
                        }

                        Remove-Item -Path $tempFile -Recurse -Force -ErrorAction Stop
                        $cleanedCount++
                        $totalSize += ($size / 1MB)
                        Write-DebugLog "清理临时文件: $tempFile (大小: $([Math]::Round($size/1MB, 2)) MB)"
                    }
                    catch {
                        $errors += "清理 $tempFile 失败: $($_.Exception.Message)"
                        Write-WarnLog "清理临时文件失败: $tempFile, 错误: $($_.Exception.Message)"
                    }
                }
            }
        }

        if ($cleanedCount -gt 0) {
            Write-InfoLog "清理完成: $cleanedCount 个文件/目录 (总计: $([Math]::Round($totalSize, 2)) MB)"
        } else {
            Write-InfoLog "没有需要清理的临时文件"
        }

        return @{
            Success = $errors.Count -eq 0
            CleanedCount = $cleanedCount
            TotalSizeMB = [Math]::Round($totalSize, 2)
            Errors = $errors
        }
    }
    catch {
        Write-ErrorLog "清理临时文件时出错: $($_.Exception.Message)" -Exception $_

        return @{
            Success = $false
            CleanedCount = $cleanedCount
            TotalSizeMB = [Math]::Round($totalSize, 2)
            Errors = $errors + $_.Exception.Message
        }
    }
}

# 执行完整的后处理流程
function Complete-PostProcessing {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$SoftwareConfig,

        [string]$SoftwareName,

        [string]$InstallDir,

        [string]$Version,

        [string]$AssetPath,

        [bool]$RestartServices = $true,

        [bool]$CleanupTemp = $true,

        [string[]]$AdditionalTempFiles = @()
    )

    Write-InfoLog "开始后处理流程"

    $results = @{
        Scripts = $null
        ServiceRestart = $null
        Cleanup = $null
        Success = $false
    }

    try {
        # 1. 执行后处理脚本
        $scriptsResult = Execute-PostScripts -SoftwareConfig $SoftwareConfig -SoftwareName $SoftwareName -InstallDir $InstallDir -Version $Version -AssetPath $AssetPath
        $results.Scripts = $scriptsResult

        if (-not $scriptsResult.Success) {
            Write-WarnLog "后处理脚本执行不完整或失败"
        }

        # 2. 重启服务（如果需要）
        if ($RestartServices) {
            $serviceResult = Restart-ServiceIfNeeded -SoftwareConfig $SoftwareConfig
            $results.ServiceRestart = $serviceResult

            if (-not $serviceResult.Success) {
                Write-WarnLog "服务重启失败: $($serviceResult.Error)"
            }
        }

        # 3. 清理临时文件
        if ($CleanupTemp) {
            # 收集临时文件
            $tempFiles = $AdditionalTempFiles

            # 如果AssetPath在TEMP目录中，添加它
            if ($AssetPath -and $AssetPath -match [regex]::Escape($env:TEMP)) {
                $tempFiles += $AssetPath
            }

            $cleanupResult = Cleanup-TempFiles -TempFiles $tempFiles
            $results.Cleanup = $cleanupResult

            if (-not $cleanupResult.Success) {
                Write-WarnLog "临时文件清理失败"
            }
        }

        # 总体成功条件：脚本执行成功（即使有服务或清理问题）
        $results.Success = $scriptsResult.Success

        if ($results.Success) {
            Write-InfoLog "后处理流程完成"
        } else {
            Write-WarnLog "后处理流程部分失败"
        }

        return $results
    }
    catch {
        Write-ErrorLog "后处理流程出错: $($_.Exception.Message)" -Exception $_

        $results.Success = $false
        $results.Error = $_.Exception.Message

        return $results
    }
}

# 导出模块函数
Export-ModuleMember -Function @(
    'Execute-PostScripts',
    'Replace-Variables',
    'Restart-ServiceIfNeeded',
    'Cleanup-TempFiles',
    'Complete-PostProcessing'
)