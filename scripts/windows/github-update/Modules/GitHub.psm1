# GitHub.psm1 - GitHub API交互模块
# 提供GitHub API请求、release信息获取和asset匹配功能

# 导入日志模块
if (-not (Get-Module -Name "Logging" -ErrorAction SilentlyContinue)) {
    try {
        Import-Module -Name "$PSScriptRoot\Logging.psm1" -Force -ErrorAction Stop
    }
    catch {
        Write-Host "警告: 无法加载日志模块，使用简化日志输出" -ForegroundColor Yellow
    }
}

# 全局缓存
$global:GITHUB_CACHE = @{}
$global:GITHUB_CACHE_TIMESTAMP = @{}

# 缓存有效期（秒）
$CACHE_EXPIRY_SECONDS = 300  # 5分钟

# 获取GitHub Token
function Get-GitHubToken {
    param([PSCustomObject]$Config)

    $token = $null

    # 从配置中获取token设置
    $useToken = $Config.config.useGithubToken
    $tokenEnvVar = $Config.config.githubTokenEnv

    if ($useToken) {
        # 从环境变量获取
        if (-not [string]::IsNullOrEmpty($tokenEnvVar)) {
            $token = [Environment]::GetEnvironmentVariable($tokenEnvVar)
            if ($token) {
                Write-DebugLog "从环境变量 $tokenEnvVar 获取GitHub Token"
                return $token
            } else {
                Write-WarnLog "配置要求使用GitHub Token，但环境变量 $tokenEnvVar 未设置"
                Write-InfoLog "请设置环境变量: setx $tokenEnvVar your_personal_access_token"
                Write-InfoLog "或访问: https://github.com/settings/personal-access-tokens 创建Token"
            }
        }
    }

    return $null
}

# 构造GitHub API URL
function Build-GitHubApiUrl {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoUrl,

        [string]$Endpoint = "releases"
    )

    # 将GitHub页面URL转换为API URL
    # 例如: https://github.com/owner/repo -> https://api.github.com/repos/owner/repo
    # 或: https://github.com/owner/repo/releases -> https://api.github.com/repos/owner/repo/releases

    $repoUrl = $RepoUrl.TrimEnd('/')

    # 移除可能的/releases后缀
    if ($repoUrl -match '/releases$') {
        $repoUrl = $repoUrl -replace '/releases$', ''
    }

    # 提取owner和repo
    if ($repoUrl -match '^https://github\.com/([^/]+)/([^/]+)') {
        $owner = $matches[1]
        $repo = $matches[2]

        $apiUrl = "https://api.github.com/repos/$owner/$repo"

        # 添加端点
        if ($Endpoint) {
            $apiUrl = "$apiUrl/$Endpoint"
        }

        return $apiUrl
    } else {
        $errorMsg = "无效的GitHub仓库URL格式: $RepoUrl"
        Write-ErrorLog $errorMsg
        throw $errorMsg
    }
}

# 获取GitHub releases（带缓存）
function Get-GitHubReleases {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoUrl,

        [PSCustomObject]$Config,

        [bool]$IncludePrerelease = $false,

        [int]$PerPage = 100,

        [bool]$UseCache = $true,

        [bool]$ForceRefresh = $false
    )

    # 构建缓存键
    $cacheKey = "$RepoUrl|$IncludePrerelease|$PerPage"

    # 检查缓存
    if ($UseCache -and -not $ForceRefresh) {
        if ($global:GITHUB_CACHE.ContainsKey($cacheKey)) {
            $cacheTime = $global:GITHUB_CACHE_TIMESTAMP[$cacheKey]
            $timeSinceCache = (Get-Date) - $cacheTime

            if ($timeSinceCache.TotalSeconds -lt $CACHE_EXPIRY_SECONDS) {
                Write-DebugLog "使用缓存的releases信息: $RepoUrl"
                return $global:GITHUB_CACHE[$cacheKey]
            } else {
                Write-DebugLog "缓存已过期，重新获取: $RepoUrl"
            }
        }
    }

    Write-InfoLog "获取GitHub releases: $RepoUrl"

    try {
        # 构建API URL
        $apiUrl = Build-GitHubApiUrl -RepoUrl $RepoUrl -Endpoint "releases"
        Write-DebugLog "GitHub API URL: $apiUrl"

        # 获取GitHub Token
        $githubToken = Get-GitHubToken -Config $Config

        # 准备请求头
        $headers = @{
            'Accept' = 'application/vnd.github.v3+json'
            'User-Agent' = 'github-update-script'
        }

        if ($githubToken) {
            $headers['Authorization'] = "token $githubToken"
            Write-DebugLog "使用GitHub Token认证"
        }

        # 构造查询参数
        $queryParams = @{
            per_page = $PerPage
        }

        if ($IncludePrerelease) {
            $queryParams.per_page = $PerPage  # 包含预发布版本
        }

        # 发送请求
        Write-DebugLog "发送GitHub API请求..."
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get -ErrorAction Stop

        # 过滤预发布版本
        if (-not $IncludePrerelease) {
            $response = $response | Where-Object { -not $_.prerelease }
        }

        Write-InfoLog "成功获取 $($response.Count) 个releases"

        # 缓存结果
        if ($UseCache) {
            $global:GITHUB_CACHE[$cacheKey] = $response
            $global:GITHUB_CACHE_TIMESTAMP[$cacheKey] = Get-Date
        }

        return $response
    }
    catch [System.Net.WebException] {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $statusDescription = $_.Exception.Response.StatusDescription

        if ($statusCode -eq 403) {
            # API速率限制
            Write-ErrorLog "GitHub API速率限制，请稍后重试或使用GitHub Token"
            Write-InfoLog "建议设置GitHub Token以提高速率限制"
            Write-InfoLog "访问: https://github.com/settings/personal-access-tokens 创建Token"
        } elseif ($statusCode -eq 404) {
            Write-ErrorLog "仓库未找到或没有releases: $RepoUrl"
        } else {
            Write-ErrorLog "GitHub API请求失败: $statusCode $statusDescription"
        }

        throw $_
    }
    catch {
        Write-ErrorLog "获取GitHub releases失败: $($_.Exception.Message)" -Exception $_
        throw $_
    }
}

# 获取最新release
function Get-LatestRelease {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoUrl,

        [PSCustomObject]$Config,

        [bool]$IncludePrerelease = $false
    )

    Write-InfoLog "获取最新release: $RepoUrl (预发布: $IncludePrerelease)"

    try {
        $releases = Get-GitHubReleases -RepoUrl $RepoUrl -Config $Config -IncludePrerelease $IncludePrerelease -PerPage 1

        if ($releases -and $releases.Count -gt 0) {
            $latestRelease = $releases[0]
            Write-InfoLog "最新release: $($latestRelease.tag_name) (发布于: $($latestRelease.published_at))"
            return $latestRelease
        } else {
            $errorMsg = "未找到releases"
            Write-ErrorLog $errorMsg
            throw $errorMsg
        }
    }
    catch {
        Write-ErrorLog "获取最新release失败: $($_.Exception.Message)" -Exception $_
        throw $_
    }
}

# 根据suffix匹配asset
function Find-MatchingAsset {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Assets,

        [Parameter(Mandatory=$true)]
        [string]$SuffixPattern,

        [bool]$CaseInsensitive = $true,

        [string]$SoftwareName = ""
    )

    if (-not $Assets -or $Assets.Count -eq 0) {
        Write-WarnLog "没有assets可供匹配"
        return $null
    }

    Write-InfoLog "在 $($Assets.Count) 个assets中匹配模式: $SuffixPattern"

    # 将suffix模式转换为正则表达式
    $regexPattern = $SuffixPattern

    # 如果suffix不是正则表达式，进行转义并添加通配符支持
    if ($SuffixPattern -notmatch '^[.*+?^${}()|\[\]\\]') {
        # 将通配符*转换为.*
        $regexPattern = $SuffixPattern -replace '\*', '.*'
        # 转义其他正则特殊字符
        $regexPattern = [regex]::Escape($regexPattern)
        # 恢复通配符功能
        $regexPattern = $regexPattern -replace '\\\.\\\*', '.*'
        # 确保匹配整个文件名
        $regexPattern = ".*$regexPattern$"
    }

    # 设置匹配选项
    $regexOptions = [System.Text.RegularExpressions.RegexOptions]::None
    if ($CaseInsensitive) {
        $regexOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    }

    try {
        $regex = New-Object System.Text.RegularExpressions.Regex($regexPattern, $regexOptions)

        # 查找匹配的asset
        $matchingAssets = @()
        foreach ($asset in $Assets) {
            if ($regex.IsMatch($asset.name)) {
                $matchingAssets += $asset
                Write-DebugLog "匹配asset: $($asset.name) (大小: $($asset.size) bytes)"
            }
        }

        if ($matchingAssets.Count -eq 0) {
            Write-WarnLog "没有找到匹配模式 '$SuffixPattern' 的asset"
            Write-DebugLog "可用的assets:"
            foreach ($asset in $Assets) {
                Write-DebugLog "  - $($asset.name) (大小: $($asset.size) bytes)"
            }
            return $null
        }

        # 如果有多个匹配，尝试选择最合适的
        if ($matchingAssets.Count -gt 1) {
            Write-InfoLog "找到 $($matchingAssets.Count) 个匹配的assets，尝试选择最合适的"

            # 根据软件名称和常见模式进行优先级排序
            $sortedAssets = $matchingAssets | Sort-Object {
                $score = 0

                # 优先选择包含软件名称的
                if ($SoftwareName -and $_.name -match $SoftwareName) {
                    $score -= 100
                }

                # 优先选择Windows相关的
                if ($_.name -match '(?i)windows|win') {
                    $score -= 50
                }

                # 优先选择.exe或.msi安装程序
                if ($_.name -match '\.(exe|msi)$') {
                    $score -= 30
                }

                # 优先选择较小的文件（可能是安装程序而非压缩包）
                $score += $_.size / 1024 / 1024  # 大小以MB为单位，越大分数越高（优先级越低）

                return $score
            }

            $selectedAsset = $sortedAssets[0]
            Write-InfoLog "选择asset: $($selectedAsset.name) (从 $($matchingAssets.Count) 个匹配项中)"
            return $selectedAsset
        } else {
            $selectedAsset = $matchingAssets[0]
            Write-InfoLog "找到匹配的asset: $($selectedAsset.name)"
            return $selectedAsset
        }
    }
    catch {
        Write-ErrorLog "匹配asset时出错: $($_.Exception.Message)" -Exception $_
        return $null
    }
}

# 测试GitHub连接
function Test-GitHubConnection {
    param([int]$Timeout = 10)

    Write-InfoLog "测试GitHub连接..."

    try {
        $testUrl = "https://api.github.com"
        $response = Invoke-WebRequest -Uri $testUrl -Method Head -TimeoutSec $Timeout -ErrorAction Stop

        if ($response.StatusCode -eq 200) {
            Write-InfoLog "GitHub连接测试成功"
            return $true
        } else {
            Write-WarnLog "GitHub连接测试返回状态码: $($response.StatusCode)"
            return $false
        }
    }
    catch {
        Write-ErrorLog "GitHub连接测试失败: $($_.Exception.Message)" -Exception $_
        return $false
    }
}

# 获取release的下载URL
function Get-ReleaseDownloadUrl {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Release,

        [Parameter(Mandatory=$true)]
        [string]$SuffixPattern,

        [string]$SoftwareName = ""
    )

    if (-not $Release.assets -or $Release.assets.Count -eq 0) {
        $errorMsg = "release没有assets"
        Write-ErrorLog $errorMsg
        throw $errorMsg
    }

    $asset = Find-MatchingAsset -Assets $Release.assets -SuffixPattern $SuffixPattern -SoftwareName $SoftwareName

    if (-not $asset) {
        $errorMsg = "未找到匹配suffix模式 '$SuffixPattern' 的asset"
        Write-ErrorLog $errorMsg
        throw $errorMsg
    }

    Write-InfoLog "找到下载URL: $($asset.browser_download_url)"
    return $asset.browser_download_url
}

# 清空GitHub缓存
function Clear-GitHubCache {
    param([string]$RepoUrl = $null)

    if ($RepoUrl) {
        # 清除特定仓库的缓存
        $keysToRemove = @()
        foreach ($key in $global:GITHUB_CACHE.Keys) {
            if ($key -match "^$([regex]::Escape($RepoUrl))") {
                $keysToRemove += $key
            }
        }

        foreach ($key in $keysToRemove) {
            $global:GITHUB_CACHE.Remove($key)
            $global:GITHUB_CACHE_TIMESTAMP.Remove($key)
        }

        if ($keysToRemove.Count -gt 0) {
            Write-InfoLog "已清除 $($keysToRemove.Count) 个缓存项: $RepoUrl"
        }
    } else {
        # 清除所有缓存
        $global:GITHUB_CACHE.Clear()
        $global:GITHUB_CACHE_TIMESTAMP.Clear()
        Write-InfoLog "已清除所有GitHub缓存"
    }
}

# 导出模块函数
Export-ModuleMember -Function @(
    'Get-GitHubReleases',
    'Get-LatestRelease',
    'Find-MatchingAsset',
    'Get-ReleaseDownloadUrl',
    'Test-GitHubConnection',
    'Get-GitHubToken',
    'Build-GitHubApiUrl',
    'Clear-GitHubCache'
)