# GitHub通用更新脚本

一个基于配置文件的通用GitHub Release更新脚本，可以自动检测和更新本地软件到最新版本。

## 功能特性

- 📋 **配置驱动**: 使用JSONC格式配置文件，支持注释和环境变量
- 🔄 **多软件支持**: 单脚本可更新多个配置的软件
- 🚀 **智能更新**: 自动检测本地版本，仅在新版本时更新
- 📥 **多种下载方式**: 支持IDM、curl、BITS、Invoke-WebRequest，自动选择最优方式
- 🔧 **灵活的安装处理**: 支持EXE、MSI、ZIP、TAR.GZ、7Z等多种格式
- ⚙️ **后处理脚本**: 支持安装前后的自定义脚本执行
- 📊 **详细日志**: 多级日志输出，支持控制台颜色和文件日志
- 🔒 **管理员权限**: 自动检测和请求管理员权限
- 🔄 **备份恢复**: 安装前自动备份，失败时自动恢复
- 🛡️ **错误处理**: 完善的错误处理和重试机制

## 快速开始

### 1. 基本使用

```powershell
# 更新所有配置的软件
.\github-update.bat

# 更新指定软件
.\github-update.bat -Software ddns-go

# 显示帮助信息
.\github-update.bat -Help

# 列出所有可更新的软件
.\github-update.bat -List

# 强制更新（即使版本相同）
.\github-update.bat -Force

# 显示详细日志
.\github-update.bat -Verbose
```

### 2. 配置文件

默认配置文件位置：
- `~/.auto-update/config.json` (用户目录)
- 项目中的 `配置/github/release/update.jsonc`

支持JSONC格式（支持注释）：
```jsonc
{
    "config": {
        "useGithubToken": false,
        "githubTokenEnv": "GITHUB_TOKEN",
        "installIfNotFound": false
    },
    "softwares": [
        {
            "ddns-go": {
                "repoUrl": "https://github.com/jeessy2/ddns-go",
                "suffix": "windows_amd64.zip",
                "installIfNotFound": true,
                "installHome": {
                    "type": "command",
                    "command": "where ddns-go",
                    "default": "C:\\Program Files\\ddns-go"
                },
                "extra": {
                    "scripts": {
                        "after": [
                            "cd \"%installHome%\"",
                            "ddns-go.exe -s install"
                        ]
                    }
                }
            }
        }
    ]
}
```

### 3. 命令行参数

```
用法: .\Main.ps1 [-ConfigPath <路径>] [-Software <软件名>] [-Force] [-Verbose] [-Help] [-List] [-Version]

参数:
  -ConfigPath <路径>   配置文件的路径（默认: ~/.auto-update/config.json）
  -Software <软件名>   指定要更新的软件名称（默认: 更新所有配置的软件）
  -Force               强制更新，即使版本相同也重新安装
  -Verbose             显示详细日志信息
  -Help                显示此帮助信息
  -List                列出配置中的所有软件
  -Version             显示脚本版本信息
```

## 配置详解

### 全局配置 (config)

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| useGithubToken | boolean | false | 是否使用GitHub Token提高API速率限制 |
| githubTokenEnv | string | GITHUB_TOKEN | GitHub Token的环境变量名称 |
| installIfNotFound | boolean | false | 软件未安装时是否自动安装 |
| logLevel | string | INFO | 日志级别: DEBUG, INFO, WARN, ERROR |
| enableCache | boolean | true | 是否启用API请求缓存 |
| cacheExpiry | number | 300 | 缓存过期时间（秒） |
| defaultDownloadMethod | string | auto | 默认下载方式: auto, idm, curl, bits, webrequest |
| downloadRetries | number | 3 | 下载重试次数 |
| downloadRetryDelay | number | 5 | 下载重试延迟（秒） |

### 软件配置

每个软件配置包含以下字段：

#### 必需字段
- **repoUrl**: GitHub仓库URL
- **suffix**: 下载文件的后缀匹配模式（支持通配符*和正则表达式）

#### 可选字段
- **installIfNotFound**: 未安装时是否自动安装（默认继承全局配置）
- **installHome**: 安装目录配置
  - type: "command"（通过命令获取）或 "path"（直接指定路径）
  - command: 当type为command时使用的命令
  - path: 当type为path时使用的路径
  - default: 当无法确定路径时使用的默认路径
- **versionCheck**: 版本检测配置
  - type: "command"（命令输出）、"fileVersion"（文件版本）、"regex"（正则表达式）
  - command/filePath/pattern: 根据type使用相应的字段
- **download**: 下载配置
  - method: 下载方式
  - timeout: 超时时间
  - headers: 自定义请求头
- **install**: 安装配置
  - type: "archive"（解压）、"installer"（安装程序）、"copy"（复制）
  - archiveType: 压缩包类型（zip/targz/7z）
  - installerArgs: 静默安装参数
  - targetDir: 目标安装目录（覆盖installHome）
- **extra**: 额外配置
  - requiresAdmin: 是否需要管理员权限
  - restartService: 需要重启的服务名称
  - scripts: 前后处理脚本
  - environment: 环境变量设置
  - firewall: 防火墙规则配置

### 脚本变量替换

在后处理脚本中支持以下变量替换：

| 变量 | 说明 | 示例 |
|------|------|------|
| %installHome% | 安装目录 | C:\Program Files\ddns-go |
| %version% | 版本号 | 1.0.0 |
| %assetPath% | 下载文件路径 | C:\Temp\file.zip |
| %softwareName% | 软件名称 | ddns-go |
| %tempDir% | 临时目录 | C:\Users\User\AppData\Local\Temp |
| 环境变量 | 所有系统环境变量 | %APPDATA%, %PROGRAMFILES% |

## 模块架构

脚本采用模块化设计，各模块职责分离：

### 核心模块
- **Config.psm1**: 配置文件管理，JSONC解析，环境变量替换
- **GitHub.psm1**: GitHub API交互，release信息获取，缓存管理
- **Version.psm1**: 版本管理，本地版本检测，版本比较
- **Download.psm1**: 下载处理，多种下载方式，重试机制
- **Install.psm1**: 安装处理，文件解压，静默安装
- **PostProcess.psm1**: 后处理脚本执行，变量替换，服务重启
- **Logging.psm1**: 日志记录，多级输出，彩色控制台

### 目录结构
```
github-update/
├── Modules/                      # PowerShell模块目录
│   ├── Config.psm1              # 配置文件管理模块
│   ├── GitHub.psm1              # GitHub API交互模块
│   ├── Download.psm1            # 下载处理模块
│   ├── Install.psm1             # 安装处理模块
│   ├── Version.psm1             # 版本管理模块
│   ├── PostProcess.psm1         # 后处理模块
│   └── Logging.psm1             # 日志模块
├── Examples/                    # 示例目录
│   └── config.example.jsonc     # 配置文件示例
├── Main.ps1                     # 主入口脚本
├── github-update.bat            # 批处理包装脚本
└── README.md                    # 本文档
```

## 工作流程

1. **初始化**: 加载模块，读取配置，设置日志级别
2. **版本检测**: 检测本地版本，获取远程最新版本
3. **更新决策**: 比较版本，判断是否需要更新
4. **文件下载**: 匹配suffix，下载对应asset文件
5. **软件安装**: 根据文件类型执行相应安装逻辑
6. **后处理**: 执行配置的后处理脚本
7. **验证清理**: 验证安装结果，清理临时文件

## 错误处理

脚本包含完善的错误处理机制：

### 重试机制
- 下载失败时自动重试（默认3次）
- API请求失败时自动重试
- 网络中断时自动恢复

### 备份恢复
- 安装前自动备份现有文件
- 安装失败时自动从备份恢复
- 备份目录按时间戳命名

### 错误日志
- 多级错误日志（DEBUG, INFO, WARN, ERROR）
- 详细错误信息和堆栈跟踪
- 文件日志支持（可选）

## 兼容性

### 系统要求
- **操作系统**: Windows 10 / Windows 11
- **PowerShell**: 版本 5.1 或更高
- **权限**: 部分操作需要管理员权限

### 下载方式支持
1. **IDM** (Internet Download Manager) - 优先级最高
2. **curl** - 支持断点续传
3. **BITS** (Background Intelligent Transfer Service) - Windows内置
4. **Invoke-WebRequest** - PowerShell内置（保底方案）

### 文件格式支持
- **安装程序**: .exe, .msi
- **压缩包**: .zip, .tar.gz, .7z
- **其他文件**: 直接复制

## 扩展开发

### 添加新的安装类型
1. 在 `Install.psm1` 的 `Install-Software` 函数中添加新的文件类型处理
2. 实现相应的解压或安装逻辑
3. 更新配置文件schema支持新类型

### 添加新的下载方式
1. 在 `Download.psm1` 中添加新的下载函数
2. 更新 `Get-DownloadMethod` 函数检测新方式
3. 更新 `Download-File` 函数调用新方式

### 自定义后处理脚本
支持多种脚本类型：
- PowerShell命令
- 批处理命令
- 可执行文件
- Shell命令

## 故障排除

### 常见问题

#### 1. 配置文件无法读取
- 检查文件路径是否正确
- 确保JSON格式正确（可使用JSON验证工具）
- 检查文件编码是否为UTF-8

#### 2. GitHub API速率限制
- 启用GitHub Token认证
- 设置环境变量 `GITHUB_TOKEN`
- 等待限制解除后重试

#### 3. 下载失败
- 检查网络连接
- 尝试不同的下载方式
- 检查防火墙设置

#### 4. 权限不足
- 以管理员身份运行脚本
- 检查文件/目录权限
- 检查服务操作权限

#### 5. 版本检测失败
- 检查versionCheck配置
- 确认软件已正确安装
- 检查命令或文件路径

### 调试模式
使用 `-Verbose` 参数启用详细日志：
```powershell
.\github-update.bat -Verbose
```

## 更新日志

### v1.0.0 (当前版本)
- 初始版本发布
- 完整的模块化架构
- 支持多软件批量更新
- 完善的错误处理和日志系统
- 示例配置和文档

## 贡献指南

1. Fork 项目
2. 创建功能分支
3. 提交更改
4. 推送到分支
5. 创建 Pull Request

## 许可证

本项目采用 MIT 许可证。详见 LICENSE 文件。

## 支持

如有问题或建议，请提交 Issue 或 Pull Request。