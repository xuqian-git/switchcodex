# swichcodex 技术设计文档

## 1. 设计目标

在 `macOS + SwiftUI` 下实现 `Codex 账号总览 / 多开实例 / 会话管理` 三大能力，并确保：

- 不依赖 Tauri
- 不依赖 Web 前端
- 尽量复用 Codex 既有本地数据结构
- 对用户现有数据改动最小
- 危险写操作可恢复

---

## 2. 技术选型

## 2.1 基础栈

- 语言：`Swift 5.10+`
- UI：`SwiftUI`
- 原生桥接：`AppKit`
- 并发：`async/await`
- 状态：`ObservableObject + @MainActor`

## 2.2 存储与系统能力

- JSON：`Codable`
- SQLite：`SQLite.swift` 或直接 `sqlite3`
- 文件监听：`DispatchSourceFileSystemObject` 或轮询
- 进程启动：`Process`
- 打开 App / 聚焦窗口：`NSWorkspace + AppleScript`
- 设置项：`UserDefaults`

## 2.3 三方库建议

建议尽量少依赖。

推荐可选：

- `SQLite.swift`
- `TomlDecoder/TomlEncoder` 类库，如果稳定可用

如果 TOML 库不稳定，建议对 `config.toml` 采用：

- 轻量解析
- 定点改写
- 写前备份

---

## 3. 总体架构

推荐分层：

```text
UI (SwiftUI Views)
  -> ViewModel
    -> Domain Service
      -> File / Process / SQLite / System Adapter
```

模块建议：

- `AccountsFeature`
- `InstancesFeature`
- `SessionsFeature`
- `CoreServices`
- `Infrastructure`

---

## 4. 目录建议

```text
swichcodex/
  SwichCodexApp/
    App/
      SwichCodexApp.swift
      AppRouter.swift
    Features/
      Accounts/
        AccountsView.swift
        AccountsViewModel.swift
        AccountCardView.swift
        AddAccountSheet.swift
      Instances/
        InstancesView.swift
        InstancesViewModel.swift
        CreateInstanceSheet.swift
      Sessions/
        SessionsView.swift
        SessionsViewModel.swift
        SessionTrashSheet.swift
    Models/
      CodexAccount.swift
      CodexInstance.swift
      CodexSession.swift
      AccountGroup.swift
    Services/
      CodexAccountService.swift
      CodexGroupService.swift
      CodexInstanceService.swift
      CodexSessionService.swift
      CodexProcessService.swift
      BackupService.swift
    Infrastructure/
      FileStore.swift
      SQLiteStore.swift
      ShellLauncher.swift
      AppleScriptBridge.swift
      TomlConfigStore.swift
    Utilities/
      Paths.swift
      Masking.swift
      AtomicWriter.swift
      Logger.swift
```

---

## 5. 核心路径设计

## 5.1 Codex 默认目录

默认读取：

- `~/.codex/auth.json`
- `~/.codex/config.toml`

实例目录下同样按以下结构读取：

- `<instance>/auth.json`
- `<instance>/config.toml`
- `<instance>/state_5.sqlite`
- `<instance>/session_index.jsonl`

## 5.2 应用自有目录

统一放：

- `~/Library/Application Support/swichcodex/`

建议结构：

```text
Application Support/swichcodex/
  accounts.json
  account-groups.json
  instances.json
  backups/
  session-trash/
  logs/
```

职责：

- `accounts.json`：应用维护的账号缓存与 UI 元数据
- `account-groups.json`：分组
- `instances.json`：实例配置
- `backups/`：写前备份
- `session-trash/`：软删除会话

---

## 6. 数据模型

## 6.1 CodexAccount

建议字段：

```swift
struct CodexAccount: Codable, Identifiable {
    let id: String
    var email: String
    var displayName: String?
    var authMode: AuthMode
    var planType: String?
    var teamName: String?
    var tags: [String]
    var lastRefreshedAt: Date?
    var isCurrent: Bool
    var apiBaseURL: String?
}
```

## 6.2 AccountGroup

```swift
struct AccountGroup: Codable, Identifiable {
    let id: String
    var name: String
    var sortOrder: Int
    var accountIds: [String]
    var createdAt: Date
}
```

## 6.3 CodexInstance

```swift
struct CodexInstance: Codable, Identifiable {
    let id: String
    var name: String
    var userDataDir: String
    var workingDir: String?
    var extraArgs: String
    var bindAccountId: String?
    var launchMode: LaunchMode
    var createdAt: Date
    var lastLaunchedAt: Date?
    var lastPID: Int32?
    var isDefault: Bool
    var followCurrentAccount: Bool
}
```

## 6.4 CodexSession

```swift
struct CodexSession: Identifiable {
    let id: String
    var title: String
    var cwd: String
    var updatedAt: Date?
    var locations: [SessionLocation]
    var tokenStats: TokenStats?
}
```

---

## 7. 服务层设计

## 7.1 CodexAccountService

职责：

- 列出账号
- 导入账号
- 切换账号
- 刷新账号
- 写入默认 `auth.json`
- 读写默认 `config.toml`

核心接口建议：

```swift
protocol CodexAccountServicing {
    func listAccounts() async throws -> [CodexAccount]
    func importFromLocalAuth() async throws -> CodexAccount
    func importFromTokens(idToken: String, accessToken: String, refreshToken: String?) async throws -> CodexAccount
    func importFromAPIKey(apiKey: String, baseURL: String?) async throws -> CodexAccount
    func switchAccount(id: String) async throws -> CodexAccount
    func refreshAccount(id: String) async throws -> CodexAccount
    func refreshAllAccounts() async throws -> [CodexAccount]
}
```

实现说明：

- 应用缓存和官方目录是两套概念
- 切换账号时必须同步写官方默认 `auth.json`
- 读写前先校验格式

## 7.2 CodexGroupService

职责：

- CRUD 分组
- 分组排序
- 账号分配/移除

## 7.3 CodexInstanceService

职责：

- 列出实例
- 创建实例
- 更新实例
- 删除实例
- 启动/停止实例
- 向实例目录注入账号

核心逻辑：

- 默认实例是 `~/.codex`
- 非默认实例是自定义目录
- 启动前根据绑定账号写目标实例的 `auth.json`
- 启动时传入 `CODEX_HOME`

核心接口建议：

```swift
protocol CodexInstanceServicing {
    func listInstances() async throws -> [CodexInstance]
    func createInstance(input: CreateInstanceInput) async throws -> CodexInstance
    func updateInstance(input: UpdateInstanceInput) async throws -> CodexInstance
    func deleteInstance(id: String, deleteDirectory: Bool) async throws
    func startInstance(id: String) async throws -> CodexInstance
    func stopInstance(id: String) async throws -> CodexInstance
    func focusInstance(id: String) async throws
}
```

## 7.4 CodexProcessService

职责：

- 解析 Codex App 路径
- 启动独立进程
- 查询 PID 是否存活
- 聚焦窗口

关键约束：

- 默认实例可用 `open -n -a`
- 带 `CODEX_HOME` 时优先直接执行 App 内真实二进制
- 启动后需要轮询匹配 PID

## 7.5 CodexSessionService

职责：

- 聚合所有实例会话
- 读取 token 统计
- 删除会话到 trash
- 从 trash 恢复

核心接口建议：

```swift
protocol CodexSessionServicing {
    func listSessionsAcrossInstances() async throws -> [CodexSession]
    func loadTokenStats(sessionIds: [String]) async throws -> [String: TokenStats]
    func moveToTrash(sessionIds: [String]) async throws -> TrashSummary
    func listTrashedSessions() async throws -> [TrashedSession]
    func restoreFromTrash(sessionIds: [String]) async throws -> RestoreSummary
}
```

---

## 8. 关键实现细节

## 8.1 账号切换

流程：

1. 从应用缓存找到目标账号
2. 校验 token/API Key 信息完整
3. 备份 `~/.codex/auth.json`
4. 写入目标账号到默认目录
5. 标记当前账号
6. 若默认实例跟随当前账号，则更新默认实例绑定

失败处理：

- 写入失败时回滚备份

## 8.2 实例启动

流程：

1. 读取实例配置
2. 确认实例目录存在
3. 如有绑定账号，先注入目标目录 `auth.json`
4. 生成启动参数
5. 启动 Codex 进程
6. 轮询匹配 PID
7. 更新实例状态

PID 匹配建议：

- 优先根据 `CODEX_HOME` 匹配
- 默认实例退化为按应用名匹配

## 8.3 会话扫描

聚合源：

- 默认实例目录
- `instances.json` 中登记的实例目录

读取逻辑：

1. 打开每个实例的 `state_5.sqlite`
2. 查询 `threads`
3. 读取 `session_index.jsonl`
4. 聚合成去重后的会话集合

## 8.4 token 统计

建议做法：

- 从 rollout JSONL 末尾逆向扫描
- 只提取 `token_count` 相关事件
- 做文件长度 + 修改时间缓存

这样能减少大文件解析开销。

## 8.5 会话软删除

删除流程：

1. 校验选中的 session
2. 将涉及的 rollout 文件与元数据搬到 `session-trash/`
3. 保存 manifest
4. 从 `state_5.sqlite` 删除线程记录
5. 从 `session_index.jsonl` 删除对应行

要求：

- 先备份，再写入
- 任一步失败可停止并提示

## 8.6 会话恢复

恢复流程：

1. 读取 trash manifest
2. 校验目标实例仍存在
3. 校验目标 session 未冲突
4. 恢复 rollout 文件
5. 回写 `state_5.sqlite`
6. 回写 `session_index.jsonl`

---

## 9. 备份与回滚设计

## 9.1 必须备份的写操作

- 写 `auth.json`
- 写 `config.toml`
- 改 `state_5.sqlite`
- 改 `session_index.jsonl`

## 9.2 备份策略

建议目录：

- `Application Support/swichcodex/backups/yyyyMMdd-HHmmss/`

每次 destructive 操作生成一个 operation id。

## 9.3 回滚策略

原则：

- 局部失败时尽量自动回滚
- 自动回滚失败时保留备份路径给用户

---

## 10. 并发与线程模型

规则：

- UI 更新只在主线程
- 文件系统和 SQLite 操作在后台 Task
- 同一实例目录写操作串行化

建议：

- 对实例目录建立 per-path actor 或串行队列

示例：

- `DirectoryMutationCoordinator`

这样能避免：

- 一边删会话一边读会话
- 一边切换账号一边启动实例

---

## 11. 错误模型

定义统一错误枚举：

```swift
enum AppError: LocalizedError {
    case fileNotFound(String)
    case invalidFormat(String)
    case sqliteError(String)
    case launchPathMissing
    case processLaunchFailed(String)
    case backupFailed(String)
    case restoreConflict(String)
    case networkFailed(String)
}
```

要求：

- 业务层返回结构化错误
- UI 层只展示用户可理解的信息

---

## 12. 一期不做的内容

为了控制复杂度，一期明确不做：

- 完整 OAuth 浏览器流程
- 会话跨实例同步
- 会话可见性修复
- CLI 启动投递终端
- 菜单栏模式
- 自动刷新调度

---

## 13. 测试策略

## 13.1 单元测试

覆盖：

- 邮箱脱敏
- 分组分配
- 实例配置读写
- auth/config 解析
- session trash manifest

## 13.2 集成测试

准备测试目录夹具：

- 模拟 `.codex`
- 模拟实例目录
- 模拟 `state_5.sqlite`
- 模拟 `session_index.jsonl`

验证：

- 导入账号
- 切换账号
- 创建实例
- 启动命令构造
- 会话删除恢复

## 13.3 手工验证

重点验证：

- 真机多开是否稳定
- 运行中实例删除/恢复会话后的表现
- 默认实例与受管实例切换账号后的行为

---

## 14. 实施顺序

建议按下面顺序开发：

1. `Paths / FileStore / AtomicWriter / BackupService`
2. `CodexAccountService`
3. `Accounts UI`
4. `CodexInstanceService + ProcessService`
5. `Instances UI`
6. `CodexSessionService`
7. `Sessions UI`
8. 稳定性与测试

---

## 15. 里程碑定义

### M1

- 能读默认 `.codex`
- 能展示账号
- 能切换账号

### M2

- 能创建实例
- 能启动和停止实例
- 能定位实例窗口

### M3

- 能展示聚合会话
- 能读取 token 统计
- 能完成 trash/restore

### M4

- 备份恢复稳定
- 错误提示完整
- 可交付测试包

