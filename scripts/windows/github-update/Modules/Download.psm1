# Download.psm1 - 下载处理模块
# 提供多种下载方式、进度显示和错误重试功能

# 导入日志模块
if (-not (Get-Module -Name "Logging" -ErrorAction SilentlyContinue)) {
    try {
        Import-Module -Name "$PSScriptRoot\Logging.psm1" -Force -ErrorAction Stop
    }
    catch {
        Write-Host "警告: 无法加载日志模块，使用简化日志输出" -ForegroundColor Yellow
    }
}

# 检测可用下载方式
function Get-DownloadMethod {
    param([string]$PreferredMethod = "auto")

    $availableMethods = @()

    # 检查IDM
    if (Get-Command 'IDMan.exe' -ErrorAction SilentlyContinue) {
        $idmPath = (Get-Command 'IDMan.exe').Source
        $availableMethods += @{
            Name = "idm"
            Path = $idmPath
            Priority = 10  # 最高优先级
        }
        Write-DebugLog "检测到IDM: $idmPath"
    }

    # 检查curl
    if (Get-Command 'curl.exe' -ErrorAction SilentlyContinue) {
        $curlPath = (Get-Command 'curl.exe').Source
        $availableMethods += @{
            Name = "curl"
            Path = $curlPath
            Priority = 20
        }
        Write-DebugLog "检测到curl: $curlPath"
    }

    # 检查BITS（Windows内置）
    if (Get-Command 'Start-BitsTransfer' -ErrorAction SilentlyContinue) {
        $availableMethods += @{
            Name = "bits"
            Path = $null  # 内置命令
            Priority = 30
        }
        Write-DebugLog "检测到BITS (Background Intelligent Transfer Service)"
    }

    # Invoke-WebRequest总是可用（PowerShell内置）
    $availableMethods += @{
        Name = "webrequest"
        Path = $null
        Priority = 40  # 最低优先级
    }
    Write-DebugLog "Invoke-WebRequest可用"

    # 按优先级排序
    $availableMethods = $availableMethods | Sort-Object Priority

    # 如果指定了首选方法，尝试使用它
    if ($PreferredMethod -ne "auto") {
        $preferred = $availableMethods | Where-Object { $_.Name -eq $PreferredMethod } | Select-Object -First 1
        if ($preferred) {
            Write-InfoLog "使用首选下载方式: $PreferredMethod"
            return $preferred
        } else {
            Write-WarnLog "首选下载方式不可用: $PreferredMethod，使用自动选择"
        }
    }

    # 返回第一个可用的方法（最高优先级）
    if ($availableMethods.Count -gt 0) {
        $selectedMethod = $availableMethods[0]
        Write-InfoLog "自动选择下载方式: $($selectedMethod.Name)"
        return $selectedMethod
    }

    # 没有可用的下载方法
    $errorMsg = "没有可用的下载方法"
    Write-ErrorLog $errorMsg
    throw $errorMsg
}

# 等待文件下载完成
function Wait-ForFileComplete {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [int]$TimeoutSeconds = 600,  # 10分钟

        [int]$CheckInterval = 2,     # 检查间隔（秒）

        [int]$StableChecks = 2       # 稳定检查次数
    )

    Write-DebugLog "等待文件下载完成: $FilePath, 超时: ${TimeoutSeconds}秒"

    $startTime = Get-Date
    $stableCount = 0
    $lastSize = -1

    while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        if (Test-Path $FilePath) {
            try {
                $currentSize = (Get-Item $FilePath -ErrorAction Stop).Length

                if ($currentSize -gt 0 -and $currentSize -eq $lastSize) {
                    $stableCount++
                    if ($stableCount -ge $StableChecks) {
                        Write-DebugLog "文件大小稳定，下载完成: $currentSize 字节"
                        return $true
                    }
                } else {
                    $stableCount = 0
                }

                $lastSize = $currentSize

                # 显示进度（如果大小大于0）
                if ($currentSize -gt 0) {
                    $elapsed = ((Get-Date) - $startTime).TotalSeconds
                    $speed = if ($elapsed -gt 0) { [Math]::Round($currentSize / $elapsed / 1024, 2) } else { 0 }
                    Write-DebugLog "下载中: $([Math]::Round($currentSize/1024/1024, 2)) MB, 速度: $speed KB/s"
                }
            }
            catch {
                # 文件可能正在被写入，继续等待
            }
        }

        Start-Sleep -Seconds $CheckInterval
    }

    Write-WarnLog "等待文件下载超时: $FilePath"
    return $false
}

# 使用IDM下载
function Download-WithIDM {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,

        [Parameter(Mandatory=$true)]
        [string]$OutputPath,

        [string]$IDMPath
    )

    Write-InfoLog "使用IDM下载: $Url"

    try {
        $outputDir = Split-Path $OutputPath -Parent
        $fileName = Split-Path $OutputPath -Leaf

        # 确保输出目录存在
        if (!(Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        # IDM参数: /d URL, /p 保存路径, /f 文件名, /n 不显示确认对话框
        $arguments = @('/d', $Url, '/p', $outputDir, '/f', $fileName, '/n')

        Write-DebugLog "IDM命令行: $IDMPath $arguments"

        $process = Start-Process -FilePath $IDMPath -ArgumentList $arguments -PassThru -NoNewWindow -ErrorAction Stop

        # 等待下载完成
        $downloadComplete = Wait-ForFileComplete -FilePath $OutputPath -TimeoutSeconds 600
        if ($downloadComplete) {
            Write-InfoLog "IDM下载完成: $OutputPath"
            return $true
        } else {
            Write-WarnLog "IDM下载可能未完成"
            return $false
        }
    }
    catch {
        Write-ErrorLog "IDM下载失败: $($_.Exception.Message)" -Exception $_
        return $false
    }
}

# 使用curl下载
function Download-WithCurl {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,

        [Parameter(Mandatory=$true)]
        [string]$OutputPath,

        [string]$CurlPath = "curl.exe"
    )

    Write-InfoLog "使用curl下载: $Url"

    try {
        $outputDir = Split-Path $OutputPath -Parent
        if (!(Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        # curl参数: -L 跟随重定向, --retry 重试次数, --connect-timeout 连接超时, -o 输出文件
        $arguments = @('-L', '--retry', '3', '--connect-timeout', '30', '-o', $OutputPath, $Url)

        Write-DebugLog "curl命令行: $CurlPath $arguments"

        $process = Start-Process -FilePath $CurlPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow -ErrorAction Stop

        if ($process.ExitCode -eq 0) {
            if (Test-Path $OutputPath -and (Get-Item $OutputPath).Length -gt 0) {
                Write-InfoLog "curl下载完成: $OutputPath"
                return $true
            } else {
                Write-WarnLog "curl下载完成但文件为空或不存在"
                return $false
            }
        } else {
            Write-WarnLog "curl下载失败，退出代码: $($process.ExitCode)"
            return $false
        }
    }
    catch {
        Write-ErrorLog "curl下载失败: $($_.Exception.Message)" -Exception $_
        return $false
    }
}

# 使用BITS下载
function Download-WithBITS {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,

        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )

    Write-InfoLog "使用BITS下载: $Url"

    try {
        $outputDir = Split-Path $OutputPath -Parent
        if (!(Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        # BITS支持断点续传和后台传输
        Start-BitsTransfer -Source $Url -Destination $OutputPath -DisplayName "下载 $Url" -ErrorAction Stop

        if (Test-Path $OutputPath -and (Get-Item $OutputPath).Length -gt 0) {
            Write-InfoLog "BITS下载完成: $OutputPath"
            return $true
        } else {
            Write-WarnLog "BITS下载完成但文件为空或不存在"
            return $false
        }
    }
    catch {
        Write-ErrorLog "BITS下载失败: $($_.Exception.Message)" -Exception $_
        return $false
    }
}

# 使用Invoke-WebRequest下载
function Download-WithWebRequest {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,

        [Parameter(Mandatory=$true)]
        [string]$OutputPath,

        [hashtable]$Headers = $null
    )

    Write-InfoLog "使用Invoke-WebRequest下载: $Url"

    try {
        $outputDir = Split-Path $OutputPath -Parent
        if (!(Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        $requestParams = @{
            Uri = $Url
            OutFile = $OutputPath
            UseBasicParsing = $true
            ErrorAction = 'Stop'
        }

        if ($Headers) {
            $requestParams.Headers = $Headers
        }

        # 显示进度
        Write-Progress -Activity "下载文件" -Status "正在下载 $Url" -PercentComplete 0

        Invoke-WebRequest @requestParams

        Write-Progress -Activity "下载文件" -Status "下载完成" -Completed

        if (Test-Path $OutputPath -and (Get-Item $OutputPath).Length -gt 0) {
            Write-InfoLog "Invoke-WebRequest下载完成: $OutputPath"
            return $true
        } else {
            Write-WarnLog "Invoke-WebRequest下载完成但文件为空或不存在"
            return $false
        }
    }
    catch {
        Write-Progress -Activity "下载文件" -Status "下载失败" -Completed
        Write-ErrorLog "Invoke-WebRequest下载失败: $($_.Exception.Message)" -Exception $_
        return $false
    }
}

# 通用下载函数
function Download-File {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url,

        [Parameter(Mandatory=$true)]
        [string]$OutputPath,

        [string]$Method = "auto",

        [hashtable]$Headers = $null,

        [int]$Retries = 3,

        [int]$RetryDelay = 5
    )

    Write-InfoLog "开始下载: $Url -> $OutputPath"

    # 检查URL是否有效
    if ([string]::IsNullOrEmpty($Url)) {
        $errorMsg = "下载URL为空"
        Write-ErrorLog $errorMsg
        throw $errorMsg
    }

    # 检查输出路径
    if ([string]::IsNullOrEmpty($OutputPath)) {
        $errorMsg = "输出路径为空"
        Write-ErrorLog $errorMsg
        throw $errorMsg
    }

    $downloadSuccess = $false
    $lastError = $null

    # 获取下载方法
    $downloadMethod = Get-DownloadMethod -PreferredMethod $Method

    # 重试循环
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        if ($attempt -gt 1) {
            Write-WarnLog "下载重试 ($attempt/$Retries): $Url"
            Start-Sleep -Seconds $RetryDelay
        }

        try {
            # 根据选择的方法调用相应的下载函数
            switch ($downloadMethod.Name) {
                "idm" {
                    $downloadSuccess = Download-WithIDM -Url $Url -OutputPath $OutputPath -IDMPath $downloadMethod.Path
                }
                "curl" {
                    $downloadSuccess = Download-WithCurl -Url $Url -OutputPath $OutputPath -CurlPath $downloadMethod.Path
                }
                "bits" {
                    $downloadSuccess = Download-WithBITS -Url $Url -OutputPath $OutputPath
                }
                "webrequest" {
                    $downloadSuccess = Download-WithWebRequest -Url $Url -OutputPath $OutputPath -Headers $Headers
                }
                default {
                    $errorMsg = "不支持的下载方法: $($downloadMethod.Name)"
                    Write-ErrorLog $errorMsg
                    throw $errorMsg
                }
            }

            if ($downloadSuccess) {
                # 验证下载的文件
                if (Test-FileIntegrity -FilePath $OutputPath) {
                    $fileSize = (Get-Item $OutputPath).Length
                    Write-InfoLog "下载成功: $OutputPath (大小: $([Math]::Round($fileSize/1024/1024, 2)) MB)"
                    return $true
                } else {
                    Write-WarnLog "文件完整性检查失败，将重试"
                    $downloadSuccess = $false
                }
            }
        }
        catch {
            $lastError = $_
            Write-ErrorLog "下载尝试 $attempt/$Retries 失败: $($_.Exception.Message)" -Exception $_
        }
    }

    # 所有重试都失败
    $errorMsg = "下载失败: $Url (尝试 $Retries 次)"
    if ($lastError) {
        $errorMsg += "，最后错误: $($lastError.Exception.Message)"
    }

    Write-ErrorLog $errorMsg
    throw $errorMsg
}

# 文件完整性检查
function Test-FileIntegrity {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [int64]$MinSize = 1024,  # 最小1KB

        [int64]$MaxSize = 10GB   # 最大10GB
    )

    if (!(Test-Path $FilePath)) {
        Write-WarnLog "文件不存在: $FilePath"
        return $false
    }

    try {
        $fileInfo = Get-Item $FilePath -ErrorAction Stop
        $fileSize = $fileInfo.Length

        # 检查文件大小
        if ($fileSize -lt $MinSize) {
            Write-WarnLog "文件大小过小: $fileSize 字节 (最小要求: $MinSize)"
            return $false
        }

        if ($fileSize -gt $MaxSize) {
            Write-WarnLog "文件大小过大: $fileSize 字节 (最大限制: $MaxSize)"
            return $false
        }

        # 检查文件是否可读
        $stream = $null
        try {
            $stream = [System.IO.File]::OpenRead($FilePath)
            $buffer = New-Object byte[] 1024
            $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
            if ($bytesRead -eq 0) {
                Write-WarnLog "文件不可读或为空"
                return $false
            }
        }
        finally {
            if ($stream) { $stream.Close() }
        }

        Write-DebugLog "文件完整性检查通过: $FilePath (大小: $fileSize 字节)"
        return $true
    }
    catch {
        Write-WarnLog "文件完整性检查失败: $($_.Exception.Message)"
        return $false
    }
}

# 计算下载速度
function Get-DownloadSpeed {
    param(
        [int64]$BytesDownloaded,
        [TimeSpan]$TimeElapsed
    )

    if ($TimeElapsed.TotalSeconds -le 0) {
        return 0
    }

    $bytesPerSecond = $BytesDownloaded / $TimeElapsed.TotalSeconds

    if ($bytesPerSecond -ge 1GB) {
        return "$([Math]::Round($bytesPerSecond / 1GB, 2)) GB/s"
    } elseif ($bytesPerSecond -ge 1MB) {
        return "$([Math]::Round($bytesPerSecond / 1MB, 2)) MB/s"
    } elseif ($bytesPerSecond -ge 1KB) {
        return "$([Math]::Round($bytesPerSecond / 1KB, 2)) KB/s"
    } else {
        return "$([Math]::Round($bytesPerSecond, 2)) B/s"
    }
}

# 获取文件大小的人类可读格式
function Format-FileSize {
    param([int64]$Bytes)

    if ($Bytes -ge 1GB) {
        return "$([Math]::Round($Bytes / 1GB, 2)) GB"
    } elseif ($Bytes -ge 1MB) {
        return "$([Math]::Round($Bytes / 1MB, 2)) MB"
    } elseif ($Bytes -ge 1KB) {
        return "$([Math]::Round($Bytes / 1KB, 2)) KB"
    } else {
        return "$Bytes B"
    }
}

# 导出模块函数
Export-ModuleMember -Function @(
    'Download-File',
    'Get-DownloadMethod',
    'Test-FileIntegrity',
    'Wait-ForFileComplete',
    'Format-FileSize',
    'Get-DownloadSpeed'
)