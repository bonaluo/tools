# Install.psm1 - 安装处理模块
# 提供软件安装、文件解压和静默安装功能

# 导入日志模块
if (-not (Get-Module -Name "Logging" -ErrorAction SilentlyContinue)) {
    try {
        Import-Module -Name "$PSScriptRoot\Logging.psm1" -Force -ErrorAction Stop
    }
    catch {
        Write-Host "警告: 无法加载日志模块，使用简化日志输出" -ForegroundColor Yellow
    }
}

# 导入下载模块（用于进度显示）
if (-not (Get-Module -Name "Download" -ErrorAction SilentlyContinue)) {
    try {
        Import-Module -Name "$PSScriptRoot\Download.psm1" -Force -ErrorAction Stop
    }
    catch {
        # 如果下载模块不可用，继续但不使用其功能
    }
}

# 常见静默安装参数
$SILENT_INSTALL_FLAGS = @(
    "/S",           # NSIS, Inno Setup
    "/VERYSILENT",  # Inno Setup
    "/SILENT",      # Inno Setup
    "/quiet",       # MSI, 一些安装程序
    "/qn",          # MSI (无界面)
    "/passive",     # MSI (被动模式)
    "/s",           # 一些安装程序
    "/exenoui",     # 一些安装程序
    "/install",     # 一些安装程序
    "/sp-",         # 跳过欢迎页面
    "/suppressmsgboxes"  # 抑制消息框
)

# 备份现有文件
function Backup-ExistingFiles {
    param(
        [Parameter(Mandatory=$true)]
        [string]$InstallDir,

        [string]$BackupDir = $null,

        [string[]]$ExcludePatterns = @()
    )

    if (!(Test-Path $InstallDir)) {
        Write-DebugLog "安装目录不存在，无需备份: $InstallDir"
        return $null
    }

    # 确定备份目录
    if ([string]::IsNullOrEmpty($BackupDir)) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $BackupDir = Join-Path (Split-Path $InstallDir -Parent) "$(Split-Path $InstallDir -Leaf)_backup_$timestamp"
    }

    Write-InfoLog "备份现有文件: $InstallDir -> $BackupDir"

    try {
        # 创建备份目录
        if (!(Test-Path $BackupDir)) {
            New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
        }

        # 复制文件
        $files = Get-ChildItem -Path $InstallDir -Recurse -File | Where-Object {
            $include = $true
            foreach ($pattern in $ExcludePatterns) {
                if ($_.Name -like $pattern) {
                    $include = $false
                    break
                }
            }
            $include
        }

        $backupCount = 0
        foreach ($file in $files) {
            $relativePath = $file.FullName.Substring($InstallDir.Length).TrimStart('\')
            $backupPath = Join-Path $BackupDir $relativePath

            $backupDirPath = Split-Path $backupPath -Parent
            if (!(Test-Path $backupDirPath)) {
                New-Item -ItemType Directory -Path $backupDirPath -Force | Out-Null
            }

            Copy-Item -Path $file.FullName -Destination $backupPath -Force -ErrorAction Stop
            $backupCount++
        }

        Write-InfoLog "备份完成: $backupCount 个文件已备份到 $BackupDir"
        return $BackupDir
    }
    catch {
        Write-ErrorLog "备份文件失败: $($_.Exception.Message)" -Exception $_
        return $null
    }
}

# 解压ZIP文件
function Extract-Zip {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ZipPath,

        [Parameter(Mandatory=$true)]
        [string]$OutputDir,

        [bool]$Overwrite = $true
    )

    Write-InfoLog "解压ZIP文件: $ZipPath -> $OutputDir"

    if (!(Test-Path $ZipPath)) {
        $errorMsg = "ZIP文件不存在: $ZipPath"
        Write-ErrorLog $errorMsg
        throw $errorMsg
    }

    try {
        # 确保输出目录存在
        if (!(Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }

        # 使用Expand-Archive（PowerShell 5.0+）
        if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
            $expandParams = @{
                Path = $ZipPath
                DestinationPath = $OutputDir
                Force = $Overwrite
                ErrorAction = 'Stop'
            }
            Expand-Archive @expandParams
        } else {
            # 回退到.NET方法
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $OutputDir)
        }

        Write-InfoLog "ZIP解压完成: $ZipPath"
        return $true
    }
    catch {
        Write-ErrorLog "解压ZIP文件失败: $($_.Exception.Message)" -Exception $_
        return $false
    }
}

# 解压TAR.GZ文件
function Extract-TarGz {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TarGzPath,

        [Parameter(Mandatory=$true)]
        [string]$OutputDir
    )

    Write-InfoLog "解压TAR.GZ文件: $TarGzPath -> $OutputDir"

    if (!(Test-Path $TarGzPath)) {
        $errorMsg = "TAR.GZ文件不存在: $TarGzPath"
        Write-ErrorLog $errorMsg
        throw $errorMsg
    }

    try {
        # 确保输出目录存在
        if (!(Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }

        # 使用tar命令（Windows 10+内置）
        if (Get-Command tar -ErrorAction SilentlyContinue) {
            $arguments = @('-xzf', $TarGzPath, '-C', $OutputDir)
            $process = Start-Process -FilePath 'tar' -ArgumentList $arguments -Wait -NoNewWindow -PassThru

            if ($process.ExitCode -eq 0) {
                Write-InfoLog "TAR.GZ解压完成: $TarGzPath"
                return $true
            } else {
                Write-WarnLog "tar解压失败，退出代码: $($process.ExitCode)"
                return $false
            }
        } else {
            $errorMsg = "未找到tar命令，无法解压TAR.GZ文件"
            Write-ErrorLog $errorMsg
            throw $errorMsg
        }
    }
    catch {
        Write-ErrorLog "解压TAR.GZ文件失败: $($_.Exception.Message)" -Exception $_
        return $false
    }
}

# 解压7Z文件
function Extract-7z {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ArchivePath,

        [Parameter(Mandatory=$true)]
        [string]$OutputDir,

        [string]$SevenZipPath = $null
    )

    Write-InfoLog "解压7Z文件: $ArchivePath -> $OutputDir"

    if (!(Test-Path $ArchivePath)) {
        $errorMsg = "7Z文件不存在: $ArchivePath"
        Write-ErrorLog $errorMsg
        throw $errorMsg
    }

    try {
        # 查找7-Zip
        $sevenZip = $SevenZipPath
        if (-not $sevenZip) {
            $possiblePaths = @(
                "$env:ProgramFiles\7-Zip\7z.exe",
                "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
                "7z.exe"
            )

            foreach ($path in $possiblePaths) {
                if (Test-Path $path) {
                    $sevenZip = $path
                    break
                }
            }
        }

        if (-not $sevenZip -or -not (Test-Path $sevenZip)) {
            $errorMsg = "未找到7-Zip，无法解压7Z文件"
            Write-ErrorLog $errorMsg
            throw $errorMsg
        }

        # 确保输出目录存在
        if (!(Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }

        # 使用7-Zip解压
        $arguments = @('x', $ArchivePath, "-o$OutputDir", '-y')
        $process = Start-Process -FilePath $sevenZip -ArgumentList $arguments -Wait -NoNewWindow -PassThru

        if ($process.ExitCode -eq 0) {
            Write-InfoLog "7Z解压完成: $ArchivePath"
            return $true
        } else {
            Write-WarnLog "7-Zip解压失败，退出代码: $($process.ExitCode)"
            return $false
        }
    }
    catch {
        Write-ErrorLog "解压7Z文件失败: $($_.Exception.Message)" -Exception $_
        return $false
    }
}

# 通用解压函数
function Extract-Archive {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ArchivePath,

        [Parameter(Mandatory=$true)]
        [string]$OutputDir,

        [string]$ArchiveType = "auto"
    )

    Write-InfoLog "解压文件: $ArchivePath -> $OutputDir"

    # 自动检测文件类型
    if ($ArchiveType -eq "auto") {
        $extension = [System.IO.Path]::GetExtension($ArchivePath).ToLower()

        switch ($extension) {
            ".zip" { $ArchiveType = "zip" }
            ".tar.gz" { $ArchiveType = "targz" }
            ".tgz" { $ArchiveType = "targz" }
            ".7z" { $ArchiveType = "7z" }
            default {
                $errorMsg = "不支持的压缩格式: $extension"
                Write-ErrorLog $errorMsg
                throw $errorMsg
            }
        }
    }

    # 根据文件类型调用相应的解压函数
    switch ($ArchiveType.ToLower()) {
        "zip" {
            return Extract-Zip -ZipPath $ArchivePath -OutputDir $OutputDir
        }
        "targz" {
            return Extract-TarGz -TarGzPath $ArchivePath -OutputDir $OutputDir
        }
        "7z" {
            return Extract-7z -ArchivePath $ArchivePath -OutputDir $OutputDir
        }
        default {
            $errorMsg = "不支持的压缩格式: $ArchiveType"
            Write-ErrorLog $errorMsg
            throw $errorMsg
        }
    }
}

# 尝试静默安装
function Try-SilentInstall {
    param(
        [Parameter(Mandatory=$true)]
        [string]$InstallerPath,

        [string[]]$SilentFlags = $null
    )

    Write-InfoLog "尝试静默安装: $InstallerPath"

    if (!(Test-Path $InstallerPath)) {
        $errorMsg = "安装程序不存在: $InstallerPath"
        Write-ErrorLog $errorMsg
        throw $errorMsg
    }

    # 使用提供的参数或默认参数
    $flagsToTry = if ($SilentFlags) { $SilentFlags } else { $SILENT_INSTALL_FLAGS }

    $installed = $false
    $lastExitCode = $null
    $lastError = $null

    foreach ($flag in $flagsToTry) {
        Write-DebugLog "尝试静默安装参数: $flag"

        try {
            $process = Start-Process -FilePath $InstallerPath -ArgumentList $flag -Wait -PassThru -NoNewWindow -ErrorAction Stop

            $lastExitCode = $process.ExitCode

            if ($lastExitCode -eq 0) {
                Write-InfoLog "静默安装成功 (参数: $flag)"
                $installed = $true
                break
            } else {
                Write-DebugLog "安装返回代码: $lastExitCode (参数: $flag)"
                $lastError = "退出代码: $lastExitCode"
            }
        }
        catch {
            $lastError = $_.Exception.Message
            Write-DebugLog "使用参数 $flag 启动安装程序失败: $lastError"
        }
    }

    if ($installed) {
        return @{
            Success = $true
            ExitCode = $lastExitCode
            Flag = $flag
        }
    } else {
        Write-WarnLog "所有静默安装参数尝试失败"
        return @{
            Success = $false
            ExitCode = $lastExitCode
            LastError = $lastError
        }
    }
}

# 复制文件到安装目录
function Copy-ToInstallDir {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,

        [Parameter(Mandatory=$true)]
        [string]$InstallDir,

        [string[]]$FilePatterns = @("*.*"),

        [bool]$Overwrite = $true,

        [bool]$CreateBackup = $true
    )

    Write-InfoLog "复制文件到安装目录: $SourcePath -> $InstallDir"

    if (!(Test-Path $SourcePath)) {
        $errorMsg = "源路径不存在: $SourcePath"
        Write-ErrorLog $errorMsg
        throw $errorMsg
    }

    try {
        # 确保安装目录存在
        if (!(Test-Path $InstallDir)) {
            New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        }

        $sourceIsFile = Test-Path $SourcePath -PathType Leaf
        $copiedCount = 0

        if ($sourceIsFile) {
            # 复制单个文件
            $destPath = Join-Path $InstallDir (Split-Path $SourcePath -Leaf)
            Copy-Item -Path $SourcePath -Destination $destPath -Force:$Overwrite -ErrorAction Stop
            $copiedCount = 1
            Write-DebugLog "复制文件: $SourcePath -> $destPath"
        } else {
            # 复制目录内容
            foreach ($pattern in $FilePatterns) {
                $files = Get-ChildItem -Path $SourcePath -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue
                foreach ($file in $files) {
                    $relativePath = $file.FullName.Substring($SourcePath.Length).TrimStart('\')
                    $destPath = Join-Path $InstallDir $relativePath

                    $destDir = Split-Path $destPath -Parent
                    if (!(Test-Path $destDir)) {
                        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                    }

                    Copy-Item -Path $file.FullName -Destination $destPath -Force:$Overwrite -ErrorAction Stop
                    $copiedCount++
                }
            }
        }

        Write-InfoLog "复制完成: $copiedCount 个文件已复制到 $InstallDir"
        return $copiedCount
    }
    catch {
        Write-ErrorLog "复制文件失败: $($_.Exception.Message)" -Exception $_
        throw $_
    }
}

# 主安装函数
function Install-Software {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SoftwareName,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$SoftwareConfig,

        [Parameter(Mandatory=$true)]
        [string]$AssetPath,

        [string]$InstallDir = $null,

        [bool]$Force = $false,

        [bool]$CreateBackup = $true
    )

    Write-InfoLog "开始安装: $SoftwareName"

    # 确定安装目录
    if ([string]::IsNullOrEmpty($InstallDir)) {
        $InstallDir = Resolve-InstallHome -SoftwareConfig $SoftwareConfig -ThrowIfNotFound $false
        if (-not $InstallDir) {
            # 使用默认目录
            $programFiles = ${env:ProgramFiles}
            $InstallDir = Join-Path $programFiles $SoftwareName
            Write-InfoLog "使用默认安装目录: $InstallDir"
        }
    }

    Write-InfoLog "安装目录: $InstallDir"

    # 检查asset文件
    if (!(Test-Path $AssetPath)) {
        $errorMsg = "安装文件不存在: $AssetPath"
        Write-ErrorLog $errorMsg
        throw $errorMsg
    }

    # 创建备份（如果启用）
    $backupDir = $null
    if ($CreateBackup -and (Test-Path $InstallDir)) {
        $backupDir = Backup-ExistingFiles -InstallDir $InstallDir
        if ($backupDir) {
            Write-InfoLog "已创建备份: $backupDir"
        }
    }

    try {
        $fileExtension = [System.IO.Path]::GetExtension($AssetPath).ToLower()
        $installResult = $null

        # 根据文件类型执行不同的安装逻辑
        switch ($fileExtension) {
            ".exe" {
                Write-InfoLog "检测到EXE安装程序"
                $installResult = Try-SilentInstall -InstallerPath $AssetPath

                if (-not $installResult.Success) {
                    Write-WarnLog "静默安装失败，将尝试交互式安装"
                    # 这里可以添加交互式安装逻辑
                    # 目前我们只是记录信息
                    Write-InfoLog "请手动运行安装程序: $AssetPath"
                }
            }
            ".msi" {
                Write-InfoLog "检测到MSI安装程序"
                $installResult = Try-SilentInstall -InstallerPath $AssetPath -SilentFlags @("/quiet", "/qn", "/passive")
            }
            ".zip" {
                Write-InfoLog "检测到ZIP压缩包"
                $tempDir = Join-Path $env:TEMP "github-update-$SoftwareName-$(Get-Date -Format 'yyyyMMddHHmmss')"
                $extractSuccess = Extract-Archive -ArchivePath $AssetPath -OutputDir $tempDir -ArchiveType "zip"

                if ($extractSuccess) {
                    # 复制解压后的文件到安装目录
                    $copiedCount = Copy-ToInstallDir -SourcePath $tempDir -InstallDir $InstallDir -Overwrite $true
                    $installResult = @{ Success = $true; CopiedFiles = $copiedCount }

                    # 清理临时目录
                    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                } else {
                    $installResult = @{ Success = $false; Error = "解压失败" }
                }
            }
            ".tar.gz" {
                Write-InfoLog "检测到TAR.GZ压缩包"
                $tempDir = Join-Path $env:TEMP "github-update-$SoftwareName-$(Get-Date -Format 'yyyyMMddHHmmss')"
                $extractSuccess = Extract-Archive -ArchivePath $AssetPath -OutputDir $tempDir -ArchiveType "targz"

                if ($extractSuccess) {
                    $copiedCount = Copy-ToInstallDir -SourcePath $tempDir -InstallDir $InstallDir -Overwrite $true
                    $installResult = @{ Success = $true; CopiedFiles = $copiedCount }

                    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                } else {
                    $installResult = @{ Success = $false; Error = "解压失败" }
                }
            }
            ".7z" {
                Write-InfoLog "检测到7Z压缩包"
                $tempDir = Join-Path $env:TEMP "github-update-$SoftwareName-$(Get-Date -Format 'yyyyMMddHHmmss')"
                $extractSuccess = Extract-Archive -ArchivePath $AssetPath -OutputDir $tempDir -ArchiveType "7z"

                if ($extractSuccess) {
                    $copiedCount = Copy-ToInstallDir -SourcePath $tempDir -InstallDir $InstallDir -Overwrite $true
                    $installResult = @{ Success = $true; CopiedFiles = $copiedCount }

                    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                } else {
                    $installResult = @{ Success = $false; Error = "解压失败" }
                }
            }
            default {
                Write-InfoLog "检测到其他类型文件: $fileExtension"
                # 直接复制文件
                $copiedCount = Copy-ToInstallDir -SourcePath $AssetPath -InstallDir $InstallDir -Overwrite $true
                $installResult = @{ Success = $true; CopiedFiles = $copiedCount }
            }
        }

        if ($installResult.Success) {
            Write-InfoLog "安装成功: $SoftwareName 到 $InstallDir"
            return @{
                Success = $true
                InstallDir = $InstallDir
                BackupDir = $backupDir
                Details = $installResult
            }
        } else {
            Write-ErrorLog "安装失败: $SoftwareName"

            # 尝试恢复备份
            if ($backupDir -and (Test-Path $backupDir)) {
                Write-InfoLog "尝试从备份恢复: $backupDir"
                try {
                    Copy-ToInstallDir -SourcePath $backupDir -InstallDir $InstallDir -Overwrite $true
                    Write-InfoLog "已从备份恢复文件"
                }
                catch {
                    Write-ErrorLog "恢复备份失败: $($_.Exception.Message)"
                }
            }

            return @{
                Success = $false
                InstallDir = $InstallDir
                BackupDir = $backupDir
                Error = $installResult.Error
            }
        }
    }
    catch {
        Write-ErrorLog "安装过程中出错: $($_.Exception.Message)" -Exception $_

        # 尝试恢复备份
        if ($backupDir -and (Test-Path $backupDir)) {
            Write-InfoLog "尝试从备份恢复..."
            try {
                Copy-ToInstallDir -SourcePath $backupDir -InstallDir $InstallDir -Overwrite $true
            }
            catch {
                # 忽略恢复错误
            }
        }

        throw $_
    }
}

# 验证安装
function Test-Installation {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SoftwareName,

        [Parameter(Mandatory=$true)]
        [string]$InstallDir,

        [PSCustomObject]$SoftwareConfig = $null
    )

    Write-InfoLog "验证安装: $SoftwareName"

    $validation = @{
        IsValid = $false
        Errors = @()
        Warnings = @()
        Details = @{}
    }

    try {
        # 检查安装目录是否存在
        if (!(Test-Path $InstallDir)) {
            $validation.Errors += "安装目录不存在: $InstallDir"
            return $validation
        }

        # 检查目录是否为空
        $files = Get-ChildItem -Path $InstallDir -Recurse -File -ErrorAction SilentlyContinue
        if ($files.Count -eq 0) {
            $validation.Errors += "安装目录为空: $InstallDir"
            return $validation
        }

        $validation.Details.FileCount = $files.Count
        $validation.Details.InstallDir = $InstallDir

        # 如果有软件配置，进行更详细的检查
        if ($SoftwareConfig) {
            # 检查是否有可执行文件
            $exeFiles = $files | Where-Object { $_.Extension -eq '.exe' }
            if ($exeFiles.Count -eq 0) {
                $validation.Warnings += "未找到可执行文件 (.exe)"
            } else {
                $validation.Details.ExeFiles = $exeFiles.Count

                # 尝试检查主可执行文件
                $mainExe = $exeFiles | Where-Object { $_.Name -like "*$SoftwareName*" } | Select-Object -First 1
                if ($mainExe) {
                    try {
                        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($mainExe.FullName)
                        if ($versionInfo.ProductVersion -or $versionInfo.FileVersion) {
                            $validation.Details.Version = if ($versionInfo.ProductVersion) { $versionInfo.ProductVersion } else { $versionInfo.FileVersion }
                        }
                    }
                    catch {
                        $validation.Warnings += "无法获取文件版本信息: $($mainExe.Name)"
                    }
                }
            }
        }

        $validation.IsValid = $true
        Write-InfoLog "安装验证通过: $SoftwareName"
    }
    catch {
        $validation.Errors += "验证过程中出错: $($_.Exception.Message)"
    }

    return $validation
}

# 导出模块函数
Export-ModuleMember -Function @(
    'Install-Software',
    'Extract-Archive',
    'Try-SilentInstall',
    'Backup-ExistingFiles',
    'Copy-ToInstallDir',
    'Test-Installation'
)