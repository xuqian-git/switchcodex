# SwichCodex

`SwichCodex` 是一个 macOS 原生桌面工具，用来批量管理 Codex 账号、实例和本地会话。

当前项目聚焦三个核心场景：

- 账号管理：导入、切换、刷新配额、批量导入导出、批量删除
- 实例管理：创建和管理多个独立 Codex 实例
- 会话管理：查看、归档、恢复本地会话

## 特性

- SwiftUI 原生 macOS 应用
- 支持从本地 `~/.codex/auth.json`、Token、API Key 导入账号
- 支持账号卡片视图和列表视图
- 支持单账号删除和批量导入、导出、删除
- 支持自动刷新缺失的配额信息
- 支持打包为 DMG 分发

## 环境要求

- macOS 14+
- Xcode 15+ 或可用的 `xcodebuild`

## 本地开发

打开工程：

```bash
open /Users/qian/project/cockpit-tools/swichcodex/swichcodex.xcodeproj
```

命令行构建：

```bash
cd /Users/qian/project/cockpit-tools/swichcodex
xcodebuild -project swichcodex.xcodeproj -scheme SwichCodex -sdk macosx build
```

## 打 DMG

项目内置了 DMG 打包脚本：

```bash
cd /Users/qian/project/cockpit-tools/swichcodex
./scripts/build_dmg.sh
```

默认输出：

```text
dist/swichcodex-macos-arm64.dmg
dist/swichcodex-macos-x86_64.dmg
```

脚本会完成以下步骤：

1. 分别构建 `arm64` 和 `x86_64` 的 Release 版 `SwichCodex.app`
2. 为每个架构生成包含应用本体和 `Applications` 快捷方式的 DMG
3. 输出到 `dist/`

如需只打单一架构：

```bash
ARCHS_TO_BUILD=arm64 ./scripts/build_dmg.sh
ARCHS_TO_BUILD=x86_64 ./scripts/build_dmg.sh
```

## 项目结构

```text
SwichCodexApp/
  App/             应用入口
  Features/        Accounts / Instances / Sessions 三大功能
  Services/        账号、实例、会话服务
  Infrastructure/  文件、SQLite、备份等底层能力
  Resources/       图标和资源目录
scripts/
  build_dmg.sh     DMG 打包脚本
```

## 当前版本

- 版本号：`0.1.5`
- Release 资产：
  - `swichcodex-macos-arm64.dmg`
  - `swichcodex-macos-x86_64.dmg`

## License

当前仓库尚未单独声明 License。如需开源发布，建议补充许可证文件。
