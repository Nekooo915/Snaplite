# Snaplite

A lightweight macOS screenshot tool. Swift + AppKit. ~45 MB RSS, ~380 KB binary.

<p align="center">
  <img src="assets/AppIcon.iconset/icon_128x128.png" width="96" alt="Snaplite icon">
</p>

## 功能

- 区域截图、窗口截图，调用系统 `screencapture` 内核
- 自动保存 PNG 到 `~/Pictures/Snaplite/` 并复制到剪贴板（均可在面板中开关）
- 全局快捷键，默认 `⌥A` 区域 / `⌥S` 窗口，可在面板内即时录入新组合
- 中英文界面，跟随系统或手动切换
- 菜单栏图标可隐藏；Dock 图标仅在设置窗口打开时出现
- 单实例：再次双击 .app 时把已运行的窗口拉回前台
- 零网络、零遥测、零后台轮询

## 安装

到 [Releases](https://github.com/Nekooo915/snaplite/releases) 下载最新构建：

```bash
unzip Snaplite-v0.1.0-macos-arm64.zip
mv Snaplite.app /Applications/
xattr -dr com.apple.quarantine /Applications/Snaplite.app
open /Applications/Snaplite.app
```

> 第三步用 `xattr` 解除 Gatekeeper 隔离属性，否则会提示"已损坏"。

首次运行需要在 **系统设置 → 隐私与安全性 → 屏幕录制** 中授权 Snaplite，授权后重启程序。

## 自行构建

需要 macOS 13+ 与 Xcode 命令行工具：

```bash
xcode-select --install     # 一次性，安装 Swift / clang / iconutil
git clone https://github.com/Nekooo915/snaplite.git
cd snaplite
bash scripts/bundle.sh
open dist/Snaplite.app
```

## 项目结构

```
.
├── Package.swift
├── Resources/Info.plist
├── scripts/bundle.sh                 -- swift build → 装配 .app → 自签
├── assets/                           -- 应用图标（多分辨率 iconset）
└── Sources/Snaplite/
    ├── main.swift                    -- 入口、单实例闸门
    ├── AppDelegate.swift             -- 菜单栏、生命周期、状态联动
    ├── AppState.swift                -- ObservableObject 包装 Config
    ├── Config.swift                  -- Codable JSON 持久化
    ├── Localization.swift            -- en / zh 字符串表 + 系统语言探测
    ├── Capture.swift                 -- 调度 /usr/sbin/screencapture
    ├── Clipboard.swift               -- PNG → NSPasteboard
    ├── DockIcon.swift                -- .accessory ↔ .regular
    ├── HotkeyManager.swift           -- Carbon RegisterEventHotKey
    ├── HotkeyParser.swift            -- 'Alt+KeyA' ↔ keyCode/mods
    ├── SingleInstance.swift          -- Unix domain socket
    ├── SettingsView.swift            -- SwiftUI 设置面板
    ├── SettingsWindowController.swift-- NSWindow + NSHostingView
    └── TrayIcon.swift                -- 程序生成的菜单栏 template 图标
```

## 许可

MIT
