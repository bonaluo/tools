# PowerShell 执行 Windows 批处理

## 命令

在 PowerShell 或 Windows CMD 中执行：

```powershell
powershell.exe -NoProfile -Command "& 'H:\note\tools\scripts\windows\adb pull ddd.bat'"
```

在 Git Bash 中执行：

```bash
powershell.exe -NoProfile -Command "& 'H:/note/tools/scripts/windows/adb pull ddd.bat'"
```

## 作用

这条命令启动一个不加载用户配置文件的 PowerShell，并通过 `-Command` 执行指定的 Windows 批处理文件：

```text
H:\note\tools\scripts\windows\adb pull ddd.bat
```

其中：

- `powershell.exe`：启动 PowerShell
- `-NoProfile`：不加载 PowerShell 配置文件
- `-Command`：将后面的内容作为命令执行
- `&`：PowerShell 调用运算符，用于执行脚本或命令
- 单引号：将带空格的文件路径作为完整参数传递

该批处理会拉取 Android 设备中的 `/sdcard/Pictures/gallery/owner/ddd1/` 目录，保存到：

```text
O:\video\owner\当前日期\
```

脚本执行完成后还会删除设备上的源目录。执行前请确认目标路径正确，并确认允许删除设备源数据。
