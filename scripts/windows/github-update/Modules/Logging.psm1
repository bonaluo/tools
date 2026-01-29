# Logging.psm1 - 日志和错误处理模块
# 提供多级日志记录、彩色输出和错误处理功能

# 日志级别常量
$LOG_LEVELS = @{
    DEBUG = 0
    INFO  = 1
    WARN  = 2
    ERROR = 3
}

# 日志级别颜色
$LOG_COLORS = @{
    DEBUG = "Gray"
    INFO  = "White"
    WARN  = "Yellow"
    ERROR = "Red"
}

# 全局日志级别（可在主脚本中设置）
if (-not (Get-Variable -Name "global:LOG_LEVEL" -ErrorAction SilentlyContinue)) {
    $global:LOG_LEVEL = "INFO"
}

# 日志文件路径（如果启用文件日志）
$global:LOG_FILE_PATH = $null

# 是否启用彩色输出（默认启用）
$global:LOG_ENABLE_COLORS = $true

# 初始化日志模块
function Initialize-Logging {
    param(
        [string]$LogLevel = "INFO",
        [string]$LogFile = $null,
        [bool]$EnableColors = $true
    )

    # 设置日志级别
    if ($LOG_LEVELS.ContainsKey($LogLevel.ToUpper())) {
        $global:LOG_LEVEL = $LogLevel.ToUpper()
    } else {
        Write-Warning "无效的日志级别: $LogLevel，使用默认级别: INFO"
        $global:LOG_LEVEL = "INFO"
    }

    # 设置日志文件
    if ($LogFile) {
        $global:LOG_FILE_PATH = $LogFile
        try {
            $logDir = Split-Path $LogFile -Parent
            if (!(Test-Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            "=== 日志开始于 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -FilePath $LogFile -Encoding UTF8
            Write-Log "INFO" "日志文件已初始化: $LogFile"
        }
        catch {
            Write-Warning "无法初始化日志文件: $($_.Exception.Message)"
            $global:LOG_FILE_PATH = $null
        }
    }

    # 设置彩色输出
    $global:LOG_ENABLE_COLORS = $EnableColors

    Write-Log "DEBUG" "日志模块已初始化 - 级别: $global:LOG_LEVEL, 文件: $(if ($global:LOG_FILE_PATH) { $global:LOG_FILE_PATH } else { '未启用' }), 彩色输出: $EnableColors"
}

# 记录日志
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Level,

        [Parameter(Mandatory=$true)]
        [string]$Message,

        [object]$Exception = $null
    )

    # 检查日志级别
    $currentLevelValue = $LOG_LEVELS[$global:LOG_LEVEL]
    $messageLevelValue = $LOG_LEVELS[$Level.ToUpper()]

    if ($messageLevelValue -lt $currentLevelValue) {
        return
    }

    # 构建日志条目
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $levelUpper = $Level.ToUpper()

    # 添加异常信息
    $fullMessage = $Message
    if ($Exception) {
        if ($Exception -is [System.Exception]) {
            $fullMessage = "$Message `n异常: $($Exception.Message)`n堆栈: $($Exception.StackTrace)"
        } else {
            $fullMessage = "$Message `n错误详情: $Exception"
        }
    }

    $logEntry = "[$timestamp] [$levelUpper] $fullMessage"

    # 控制台输出
    if ($global:LOG_ENABLE_COLORS -and $LOG_COLORS.ContainsKey($levelUpper)) {
        $color = $LOG_COLORS[$levelUpper]
        Write-Host $logEntry -ForegroundColor $color
    } else {
        Write-Host $logEntry
    }

    # 文件输出
    if ($global:LOG_FILE_PATH) {
        try {
            # 移除颜色代码（如果有）并写入文件
            $fileEntry = $logEntry -replace '\x1b\[[0-9;]*m', ''
            $fileEntry | Out-File -FilePath $global:LOG_FILE_PATH -Append -Encoding UTF8
        }
        catch {
            # 文件写入失败时不阻止程序运行
            Write-Host "[WARN] 无法写入日志文件: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# 快捷函数
function Write-DebugLog {
    param([string]$Message)
    Write-Log "DEBUG" $Message
}

function Write-InfoLog {
    param([string]$Message)
    Write-Log "INFO" $Message
}

function Write-WarnLog {
    param([string]$Message)
    Write-Log "WARN" $Message
}

function Write-ErrorLog {
    param([string]$Message, [object]$Exception = $null)
    Write-Log "ERROR" $Message $Exception
}

# 错误处理函数
function Handle-Error {
    param(
        [Parameter(Mandatory=$true)]
        [object]$ErrorObject,

        [string]$Context = "",

        [bool]$Rethrow = $false,

        [int]$ExitCode = 1,

        [bool]$Fatal = $false
    )

    $errorMessage = if ($Context) { "${Context}: $($ErrorObject.ToString())" } else { $ErrorObject.ToString() }

    Write-ErrorLog "处理错误" -Exception $ErrorObject

    if ($Fatal) {
        Write-ErrorLog "致命错误，脚本将退出" -Exception $ErrorObject
        if ($global:LOG_FILE_PATH) {
            Write-InfoLog "详细错误信息请查看日志文件: $global:LOG_FILE_PATH"
        }
        exit $ExitCode
    }

    if ($Rethrow) {
        throw $ErrorObject
    }
}

# 带重试的执行
function Invoke-WithRetry {
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,

        [int]$MaxRetries = 3,

        [int]$RetryDelay = 5,

        [string]$OperationName = "操作",

        [bool]$ThrowOnFinalFailure = $true
    )

    $retryCount = 0
    $lastError = $null

    while ($retryCount -le $MaxRetries) {
        try {
            if ($retryCount -gt 0) {
                Write-WarnLog "$OperationName 第 $retryCount/$MaxRetries 次重试..."
                Start-Sleep -Seconds $RetryDelay
            }

            $result = & $ScriptBlock
            return $result
        }
        catch {
            $lastError = $_
            $retryCount++

            if ($retryCount -le $MaxRetries) {
                Write-WarnLog "$OperationName 失败，将在 ${RetryDelay}秒后重试: $($_.Exception.Message)"
            } else {
                Write-ErrorLog "$OperationName 重试 $MaxRetries 次后仍然失败" -Exception $_

                if ($ThrowOnFinalFailure) {
                    throw $_
                } else {
                    return $null
                }
            }
        }
    }

    return $null
}

# 进度显示函数
function Write-ProgressLog {
    param(
        [string]$Activity,

        [string]$Status,

        [int]$PercentComplete = -1,

        [int]$SecondsRemaining = -1
    )

    $progressParams = @{
        Activity = $Activity
        Status = $Status
    }

    if ($PercentComplete -ge 0 -and $PercentComplete -le 100) {
        $progressParams.PercentComplete = $PercentComplete
    }

    if ($SecondsRemaining -ge 0) {
        $progressParams.SecondsRemaining = $SecondsRemaining
    }

    Write-Progress @progressParams
}

# 完成进度显示
function Complete-ProgressLog {
    Write-Progress -Activity "完成" -Completed
}

# 导出模块函数
Export-ModuleMember -Function @(
    'Initialize-Logging',
    'Write-Log',
    'Write-DebugLog',
    'Write-InfoLog',
    'Write-WarnLog',
    'Write-ErrorLog',
    'Handle-Error',
    'Invoke-WithRetry',
    'Write-ProgressLog',
    'Complete-ProgressLog'
)