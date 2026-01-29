# Config.psm1 - 配置文件管理模块
# 提供JSONC解析、配置验证和环境变量替换功能

# 导入日志模块
if (-not (Get-Module -Name "Logging" -ErrorAction SilentlyContinue)) {
    try {
        Import-Module -Name "$PSScriptRoot\Logging.psm1" -Force -ErrorAction Stop
    }
    catch {
        Write-Host "警告: 无法加载日志模块，使用简化日志输出" -ForegroundColor Yellow
    }
}

# 全局配置缓存
$global:CONFIG_CACHE = @{}

# 移除JSONC中的注释
function Remove-JsoncComments {
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$JsoncContent
    )

    process {
        # 先处理块注释（跨行）
        # 移除 /* ... */ 注释（非贪婪匹配）
        $content = $JsoncContent -replace '(?s)/\*.*?\*/', ''

        # 按行处理行注释
        $lines = $content -split "`r?`n"
        $resultLines = @()

        foreach ($line in $lines) {
            # 移除行注释，但要排除http://和https://
            # 使用更精确的匹配：查找不在字符串内的//
            $inString = $false
            $escapeNext = $false
            $chars = $line.ToCharArray()
            $resultChars = @()
            $commentFound = $false

            for ($i = 0; $i -lt $chars.Count; $i++) {
                $char = $chars[$i]

                if ($escapeNext) {
                    $resultChars += $char
                    $escapeNext = $false
                    continue
                }

                if ($char -eq '"' -and -not $inString) {
                    $inString = $true
                    $resultChars += $char
                } elseif ($char -eq '"' -and $inString) {
                    $inString = $false
                    $resultChars += $char
                } elseif ($char -eq '\' -and $inString) {
                    $escapeNext = $true
                    $resultChars += $char
                } elseif ($char -eq '/' -and $i -lt ($chars.Count - 1) -and $chars[$i + 1] -eq '/' -and -not $inString) {
                    # 找到行注释，跳过行的剩余部分
                    $commentFound = $true
                    break
                } else {
                    $resultChars += $char
                }
            }

            $processedLine = -join $resultChars
            # 修剪行尾空格
            $processedLine = $processedLine.TrimEnd()

            # 如果行不为空，添加到结果
            if ($processedLine -ne '') {
                $resultLines += $processedLine
            }
        }

        return $resultLines -join "`n"
    }
}

# 解析环境变量（支持 %VAR% 和 ${VAR} 格式）
function Resolve-EnvironmentVariables {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Text,

        [bool]$SuppressWarnings = $false
    )

    # 存储原始文本用于错误报告
    $originalText = $Text

    try {
        # 处理 %VAR% 格式
        $pattern1 = '%([^%]+)%'
        # 获取所有唯一匹配
        $matches1 = [regex]::Matches($Text, $pattern1)
        $uniqueVars1 = @{}

        foreach ($match in $matches1) {
            $varName = $match.Groups[1].Value
            $fullMatch = $match.Value  # %varName%
            if (-not $uniqueVars1.ContainsKey($fullMatch)) {
                $uniqueVars1[$fullMatch] = $varName
            }
        }

        # 替换每个唯一变量
        foreach ($fullMatch in $uniqueVars1.Keys) {
            $varName = $uniqueVars1[$fullMatch]
            $varValue = [Environment]::GetEnvironmentVariable($varName)

            if ($null -ne $varValue) {
                $Text = $Text -replace [regex]::Escape($fullMatch), $varValue
                Write-DebugLog "替换环境变量: $fullMatch -> $varValue"
            } else {
                # 检查变量名是否看起来像环境变量（全大写）
                $isLikelyEnvVar = $varName -match '^[A-Z0-9_]+$'

                if ($isLikelyEnvVar -and -not $SuppressWarnings) {
                    Write-WarnLog "环境变量未找到: $fullMatch"
                } elseif ($isLikelyEnvVar) {
                    Write-DebugLog "环境变量未找到（但已静默）: $fullMatch"
                } else {
                    Write-DebugLog "跳过脚本变量: $fullMatch"
                }
                # 保持原样，不替换
            }
        }

        # 处理 ${VAR} 格式
        $pattern2 = '\$\{([^}]+)\}'
        # 获取所有唯一匹配
        $matches2 = [regex]::Matches($Text, $pattern2)
        $uniqueVars2 = @{}

        foreach ($match in $matches2) {
            $varName = $match.Groups[1].Value
            $fullMatch = $match.Value  # ${varName}
            if (-not $uniqueVars2.ContainsKey($fullMatch)) {
                $uniqueVars2[$fullMatch] = $varName
            }
        }

        # 替换每个唯一变量
        foreach ($fullMatch in $uniqueVars2.Keys) {
            $varName = $uniqueVars2[$fullMatch]
            $varValue = [Environment]::GetEnvironmentVariable($varName)

            if ($null -ne $varValue) {
                $Text = $Text -replace [regex]::Escape($fullMatch), $varValue
                Write-DebugLog "替换环境变量: $fullMatch -> $varValue"
            } else {
                # 检查变量名是否看起来像环境变量（全大写）
                $isLikelyEnvVar = $varName -match '^[A-Z0-9_]+$'

                if ($isLikelyEnvVar -and -not $SuppressWarnings) {
                    Write-WarnLog "环境变量未找到: $fullMatch"
                } elseif ($isLikelyEnvVar) {
                    Write-DebugLog "环境变量未找到（但已静默）: $fullMatch"
                } else {
                    Write-DebugLog "跳过脚本变量: $fullMatch"
                }
                # 保持原样，不替换
            }
        }

        return $Text
    }
    catch {
        if (-not $SuppressWarnings) {
            Write-WarnLog "解析环境变量时出错: $($_.Exception.Message)，返回原始文本"
        }
        return $originalText
    }
}

# 读取和解析配置文件
function Read-ConfigFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath,

        [bool]$UseCache = $true,

        [bool]$ResolveEnvVars = $true
    )

    # 检查缓存
    $cacheKey = $ConfigPath
    if ($UseCache -and $global:CONFIG_CACHE.ContainsKey($cacheKey)) {
        Write-DebugLog "使用缓存的配置: $ConfigPath"
        return $global:CONFIG_CACHE[$cacheKey]
    }

    Write-InfoLog "读取配置文件: $ConfigPath"

    # 检查文件是否存在
    if (!(Test-Path $ConfigPath)) {
        $errorMsg = "配置文件不存在: $ConfigPath"
        Write-ErrorLog $errorMsg
        throw $errorMsg
    }

    try {
        # 读取文件内容
        $jsoncContent = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
        Write-DebugLog "配置文件大小: $($jsoncContent.Length) 字符"

        # 移除注释
        $jsonContent = Remove-JsoncComments -JsoncContent $jsoncContent
        Write-DebugLog "移除注释后大小: $($jsonContent.Length) 字符"

        # 解析JSON
        $config = $jsonContent | ConvertFrom-Json -ErrorAction Stop

        # 解析环境变量
        if ($ResolveEnvVars) {
            $config = Resolve-EnvVarsInObject -Object $config
        }

        # 验证配置
        $validationResult = Validate-Config -Config $config
        if (-not $validationResult.IsValid) {
            $errorMsg = "配置文件验证失败: $($validationResult.ErrorMessage)"
            Write-ErrorLog $errorMsg
            throw $errorMsg
        }

        # 填充默认值
        $config = Set-ConfigDefaults -Config $config

        # 缓存配置
        if ($UseCache) {
            $global:CONFIG_CACHE[$cacheKey] = $config
        }

        Write-InfoLog "配置文件解析成功"
        return $config
    }
    catch {
        $errorMsg = "解析配置文件失败: $($_.Exception.Message)"
        Write-ErrorLog $errorMsg -Exception $_
        throw $errorMsg
    }
}

# 递归解析对象中的环境变量
function Resolve-EnvVarsInObject {
    param(
        [object]$Object,
        [string]$Path = ""
    )

    if ($null -eq $Object) {
        return $null
    }

    # 检查是否在脚本部分，如果是则跳过环境变量解析
    if ($Path -match '\.extra\.scripts\.') {
        return $Object
    }

    switch ($Object.GetType().Name) {
        "String" {
            # 对于路径中包含extra.scripts的字符串，不解析环境变量
            if ($Path -match '\.extra\.scripts\.') {
                return $Object
            }
            return Resolve-EnvironmentVariables -Text $Object -SuppressWarnings $true
        }
        "PSCustomObject" {
            $result = @{}
            $Object.PSObject.Properties | ForEach-Object {
                $newPath = if ($Path) { "$Path.$($_.Name)" } else { $_.Name }
                $result[$_.Name] = Resolve-EnvVarsInObject -Object $_.Value -Path $newPath
            }
            return [PSCustomObject]$result
        }
        "Object[]" {
            return $Object | ForEach-Object {
                Resolve-EnvVarsInObject -Object $_ -Path $Path
            }
        }
        "Hashtable" {
            $result = @{}
            $Object.Keys | ForEach-Object {
                $newPath = if ($Path) { "$Path.$_" } else { $_ }
                $result[$_] = Resolve-EnvVarsInObject -Object $Object[$_] -Path $newPath
            }
            return $result
        }
        default {
            return $Object
        }
    }
}

# 验证配置
function Validate-Config {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config
    )

    $result = @{
        IsValid = $true
        ErrorMessage = ""
    }

    # 检查必需的结构
    if (-not $Config.softwares) {
        $result.IsValid = $false
        $result.ErrorMessage = "配置缺少 'softwares' 部分"
        return $result
    }

    # 验证每个软件配置
    foreach ($softwareItem in $Config.softwares) {
        foreach ($softwareName in $softwareItem.PSObject.Properties.Name) {
            $softwareConfig = $softwareItem.$softwareName

            # 验证必需字段
            $requiredFields = @("repoUrl", "suffix")
            foreach ($field in $requiredFields) {
                if (-not $softwareConfig.$field) {
                    $result.IsValid = $false
                    $result.ErrorMessage = "软件 '$softwareName' 缺少必需字段: '$field'"
                    return $result
                }
            }

            # 验证repoUrl格式
            if ($softwareConfig.repoUrl -notmatch '^https://github\.com/') {
                Write-WarnLog "软件 '$softwareName' 的 repoUrl 可能不是有效的 GitHub URL: $($softwareConfig.repoUrl)"
            }

            # 验证installHome结构
            if ($softwareConfig.installHome) {
                if ($softwareConfig.installHome.type -and $softwareConfig.installHome.type -notin @("command", "path")) {
                    $result.IsValid = $false
                    $result.ErrorMessage = "软件 '$softwareName' 的 installHome.type 必须是 'command' 或 'path'"
                    return $result
                }
            }
        }
    }

    return $result
}

# 设置配置默认值
function Set-ConfigDefaults {
    param([PSCustomObject]$Config)

    # 确保config部分存在
    if (-not $Config.config) {
        $Config | Add-Member -MemberType NoteProperty -Name "config" -Value @{} -Force
    }

    # 设置全局配置默认值
    $defaultConfig = @{
        useGithubToken = $false
        githubTokenEnv = "GITHUB_TOKEN"
        installIfNotFound = $false
    }

    foreach ($key in $defaultConfig.Keys) {
        if (-not $Config.config.$key) {
            $Config.config | Add-Member -MemberType NoteProperty -Name $key -Value $defaultConfig[$key] -Force
        }
    }

    # 设置每个软件的默认值
    foreach ($softwareItem in $Config.softwares) {
        foreach ($softwareName in $softwareItem.PSObject.Properties.Name) {
            $softwareConfig = $softwareItem.$softwareName

            # 设置installIfNotFound默认值
            if (-not $softwareConfig.installIfNotFound) {
                $softwareConfig | Add-Member -MemberType NoteProperty -Name "installIfNotFound" -Value $Config.config.installIfNotFound -Force
            }

            # 确保extra部分存在
            if (-not $softwareConfig.extra) {
                $softwareConfig | Add-Member -MemberType NoteProperty -Name "extra" -Value @{} -Force
            }

            # 确保scripts部分存在
            if (-not $softwareConfig.extra.scripts) {
                $softwareConfig.extra | Add-Member -MemberType NoteProperty -Name "scripts" -Value @{} -Force
            }

            # 确保after数组存在
            if (-not $softwareConfig.extra.scripts.after) {
                $softwareConfig.extra.scripts | Add-Member -MemberType NoteProperty -Name "after" -Value @() -Force
            }
        }
    }

    return $Config
}

# 获取软件配置
function Get-SoftwareConfig {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config,

        [string]$SoftwareName
    )

    if ([string]::IsNullOrEmpty($SoftwareName)) {
        # 返回所有软件配置
        $allSoftware = @()
        foreach ($softwareItem in $Config.softwares) {
            foreach ($name in $softwareItem.PSObject.Properties.Name) {
                $allSoftware += @{
                    Name = $name
                    Config = $softwareItem.$name
                }
            }
        }
        return $allSoftware
    } else {
        # 查找指定软件
        foreach ($softwareItem in $Config.softwares) {
            if ($softwareItem.PSObject.Properties.Name -contains $SoftwareName) {
                return @{
                    Name = $SoftwareName
                    Config = $softwareItem.$SoftwareName
                }
            }
        }

        $errorMsg = "软件未在配置中找到: $SoftwareName"
        Write-ErrorLog $errorMsg
        throw $errorMsg
    }
}

# 解析安装目录
function Resolve-InstallHome {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$SoftwareConfig,

        [bool]$ThrowIfNotFound = $false
    )

    $installHome = $null

    # 检查installHome配置
    if ($SoftwareConfig.installHome) {
        $installHomeConfig = $SoftwareConfig.installHome

        switch ($installHomeConfig.type) {
            "command" {
                # 通过命令获取安装目录
                if ($installHomeConfig.command) {
                    try {
                        $commandResult = Invoke-Expression $installHomeConfig.command 2>$null
                        if ($commandResult -and (Test-Path $commandResult)) {
                            $installHome = Split-Path $commandResult -Parent
                        }
                    }
                    catch {
                        Write-DebugLog "通过命令获取安装目录失败: $($installHomeConfig.command), 错误: $($_.Exception.Message)"
                    }
                }
            }
            "path" {
                # 直接使用路径
                if ($installHomeConfig.path -and (Test-Path $installHomeConfig.path)) {
                    $installHome = $installHomeConfig.path
                }
            }
        }

        # 如果未找到，使用默认路径
        if (-not $installHome -and $installHomeConfig.default) {
            $installHome = $installHomeConfig.default
            Write-InfoLog "使用默认安装目录: $installHome"
        }
    } else {
        # 如果没有installHome配置，使用默认位置
        $programFiles = ${env:ProgramFiles}
        $defaultPath = Join-Path $programFiles $softwareName
        if (Test-Path $defaultPath) {
            $installHome = $defaultPath
        }
    }

    # 检查是否找到安装目录
    if (-not $installHome) {
        $errorMsg = "无法确定安装目录"
        if ($ThrowIfNotFound) {
            Write-ErrorLog $errorMsg
            throw $errorMsg
        } else {
            Write-WarnLog $errorMsg
            return $null
        }
    }

    # 确保路径存在
    if (-not (Test-Path $installHome)) {
        Write-InfoLog "安装目录不存在，将创建: $installHome"
        try {
            New-Item -ItemType Directory -Path $installHome -Force | Out-Null
        }
        catch {
            $errorMsg = "无法创建安装目录: $installHome, 错误: $($_.Exception.Message)"
            if ($ThrowIfNotFound) {
                Write-ErrorLog $errorMsg
                throw $errorMsg
            } else {
                Write-WarnLog $errorMsg
                return $null
            }
        }
    }

    return $installHome
}

# 清空配置缓存
function Clear-ConfigCache {
    param([string]$ConfigPath = $null)

    if ($ConfigPath) {
        if ($global:CONFIG_CACHE.ContainsKey($ConfigPath)) {
            $global:CONFIG_CACHE.Remove($ConfigPath)
            Write-DebugLog "已清除配置缓存: $ConfigPath"
        }
    } else {
        $global:CONFIG_CACHE.Clear()
        Write-InfoLog "已清除所有配置缓存"
    }
}

# 导出模块函数
Export-ModuleMember -Function @(
    'Read-ConfigFile',
    'Get-SoftwareConfig',
    'Resolve-InstallHome',
    'Validate-Config',
    'Clear-ConfigCache',
    'Remove-JsoncComments',
    'Resolve-EnvironmentVariables'
)