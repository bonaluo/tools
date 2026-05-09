# RTK 全局配置与 CCSwitch 冲突问题

## 问题描述

使用 `rtk init -g` 设置的全局配置会被 ccswitch 覆盖。

## 解决方案

1. 打开 `~/.claude/settings.json`
2. 执行 `rtk init -g` 获取 rtk 配置的 hook
3. 将 rtk 配置的 hook 复制到 ccswitch 中
4. 在 cc-switch 中将复制的配置设置为通用配置

## 相关项目

- [rtk-ai/rtk](https://github.com/rtk-ai/rtk) - Claude Code 增强工具
- [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman)
- [farion1231/cc-switch](https://github.com/farion1231/cc-switch) - 配置切换工具

## 标签

#claude-code #配置 #rtk #ccswitch #hook
