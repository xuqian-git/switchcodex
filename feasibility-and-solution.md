# swichcodex 可行性分析与方案

## 1. 目标

参照当前 `cockpit-tools` 项目，单独做一个 macOS SwiftUI 原生项目 `swichcodex`，只保留以下能力：

1. Codex 账号总览
2. Codex 多开实例
3. Codex 会话管理

不复制当前项目里与其他平台账号、公告、悬浮窗、唤醒任务、双因素验证等无关能力。

---

## 2. 结论

结论：**可行，建议做。**

但需要明确一点：这不是“照着现有页面改成 SwiftUI”这么简单，而是要在 macOS 原生项目里**重建一层本地服务层**，因为这三个功能都直接依赖本地文件、SQLite、进程管理和 `CODEX_HOME` 隔离启动机制。

建议方案：

- UI 层：`SwiftUI + AppKit bridge`
- 本地服务层：`Swift`
- 数据持久化：`JSON + UserDefaults + 文件系统`
- 会话读取：`SQLite.swift` 或系统 `sqlite3`
- 配置读写：`TOML` 解析库或轻量文本改写
- 进程控制：`Process`, `NSWorkspace`, AppleScript

---

## 3. 当前项目里对应能力的真实实现

结合现有仓库代码，三个目标功能的核心依赖如下。

### 3.1 Codex 账号总览

当前项目不是只维护一份应用内账号列表，而是直接操作 Codex 本地目录：

- 默认目录：`~/.codex`
- 账号切换：写入 `auth.json`
- 配置读取：读写 `config.toml`
- 刷新账号资料/配额：调用远端接口并回写本地
- 分组管理：应用自己维护一份分组 JSON

已确认的关键事实：

- `CODEX_HOME` 默认指向 `~/.codex`
- 当前项目通过 `auth.json` 完成账号注入和切换
- 当前项目通过 `config.toml` 读取/保存 quick config
- 账号分组单独存储，不属于 Codex 官方数据

### 3.2 Codex 多开实例

当前项目的多开并不是“窗口复制”，而是**多个独立的 Codex 用户目录**：

- 默认实例目录：`~/.codex`
- 扩展实例目录：例如 `~/.antigravity_cockpit/instances/codex/...`
- 每个实例依赖独立 `CODEX_HOME`
- 启动时按实例目录注入账号
- macOS 上多开依赖 `open -n -a` 或直接执行 App 路径
- 当需要传入 `CODEX_HOME` 时，不能只靠 `open -a`，必须直接执行应用

此外，当前项目还会给实例目录共享以下内容：

- `skills/`
- `rules/`
- `vendor_imports/skills/`
- `AGENTS.md`

共享方式不是复制，而是符号链接。

### 3.3 Codex 会话管理

当前项目的会话管理不是调公开 API，而是直接扫描每个实例目录：

- `state_5.sqlite`
- `session_index.jsonl`
- rollout JSONL 文件

现有能力包括：

- 聚合所有实例会话
- 按工作目录分组
- 读取 token 统计
- 将会话移入“废纸篓”
- 从废纸篓恢复
- 跨实例补齐线程数据

这说明会话管理是本地文件/数据库操作型功能，SwiftUI 原生版可以做，但需要足够小心的数据一致性和备份策略。

---

## 4. 三项功能的可行性判断

### 4.1 功能 1：Codex 账号总览

目标能力：

- 添加 Codex 账号
- 刷新全部
- 隐藏邮箱
- 分组管理
- 卡片信息展示
- 账号切换
- 单卡片刷新

可行性：**高**

原因：

- 本地账号源和切换机制都清晰
- 分组、隐藏邮箱、本地展示都属于应用侧能力
- 单账号刷新、全量刷新可以沿用相同思路

主要难点：

- “添加账号”如果包含完整 OAuth 登录流程，复杂度较高
- 如果一期接受“从本地导入 / 手动粘贴 token / API Key 添加”，复杂度会明显下降

建议：

- 一期支持：
  - 从本地 `~/.codex/auth.json` 导入
  - 手动粘贴 token 添加
  - API Key 方式添加
  - 切换账号
  - 刷新单账号/全部账号
  - 邮箱脱敏
  - 分组
- 二期再做：
  - 完整 OAuth 登录引导
  - Keychain 集成

### 4.2 功能 2：Codex 多开实例

可行性：**高**

原因：

- 当前项目已证明机制成立
- 核心就是实例目录隔离 + `CODEX_HOME` 注入 + 进程管理
- macOS 原生做 `Process`、`NSWorkspace`、AppleScript 反而比 Tauri 更直接

主要难点：

- 要正确找到 Codex App 路径
- 要识别和管理不同实例 PID
- CLI 模式与 GUI 模式要分开处理
- 启动前要确保实例目录已初始化并已注入绑定账号

建议：

- 一期支持：
  - 创建实例
  - 删除实例
  - 指定实例目录
  - 绑定账号
  - 启动/停止实例
  - 打开实例窗口
  - 单实例刷新状态
- 二期支持：
  - 复制来源实例
  - 共享 `skills/rules/AGENTS.md` 符号链接
  - CLI 启动命令生成与一键投递终端

### 4.3 功能 3：Codex 会话管理

可行性：**中高**

原因：

- 数据位置已知
- 聚合与展示本身不复杂
- 删除/恢复也能通过本地文件搬迁实现

主要难点：

- `state_5.sqlite` 和 `session_index.jsonl` 必须同步修改
- 运行中的实例可能持有数据库/缓存，界面结果会有延迟
- 不同 Codex 版本后续可能改数据库结构

建议：

- 一期支持：
  - 聚合列出所有实例会话
  - 按项目目录分组
  - 查看会话位置
  - 读取 token 统计
  - 软删除到应用自己的 Trash 目录
  - 从 Trash 恢复
- 二期支持：
  - 跨实例线程同步
  - 会话可见性修复
  - 更细粒度的诊断工具

---

## 5. 风险与约束

### 5.1 对 Codex 本地文件结构有依赖

你的应用会依赖这些文件结构不发生大改：

- `auth.json`
- `config.toml`
- `state_5.sqlite`
- `session_index.jsonl`

如果 Codex 官方未来升级格式，`swichcodex` 需要跟进。

### 5.2 多开本质依赖 macOS 行为

要稳定多开，必须满足：

- 能定位 Codex App
- 能按 `CODEX_HOME` 启动独立进程
- 能识别各实例真实 PID

这决定了该项目应当明确限定为 **macOS only**。

### 5.3 会话删除恢复必须做保护

建议默认策略：

- 所有删除都先进入 `swichcodex` 自己的 trash 目录
- 每次改写前做备份
- 对运行中实例给出风险提示

### 5.4 OAuth 登录不是一期最优先

如果你坚持一期就做“账号网页登录添加”，开发量和不稳定性会明显上升。  
如果目标是先把产品跑起来，建议先做：

- 本地导入
- token 导入
- API Key 导入

---

## 6. 推荐产品范围

### 6.1 一期 MVP

建议只做下面这些，足够构成一个可用版本：

#### A. 账号总览

- 账号列表卡片
- 邮箱脱敏开关
- 添加账号
- 切换账号
- 刷新单账号
- 刷新全部账号
- 分组管理

#### B. 多开实例

- 实例列表
- 新建实例
- 绑定账号
- 启动/停止
- 窗口定位
- 展示实例目录、运行状态、最后启动时间

#### C. 会话管理

- 聚合所有实例会话
- 按 cwd 分组
- 查看会话所在实例
- 读取 token 使用量
- 删除到废纸篓
- 从废纸篓恢复

### 6.2 二期增强

- OAuth 登录接入
- 跨实例线程同步
- 会话可见性修复
- CLI 启动模式
- 菜单栏模式
- Keychain 安全存储

---

## 7. SwiftUI 原生架构建议

推荐目录结构：

```text
swichcodex/
  SwichCodexApp/
    App/
    Features/
      Accounts/
      Instances/
      Sessions/
    Services/
      Codex/
      Instance/
      Session/
      Storage/
      Process/
    Models/
    Utilities/
    Resources/
  Docs/
```

推荐模块划分：

- `CodexAccountService`
  - 读取/写入 `auth.json`
  - 读取/写入 `config.toml`
  - 账号导入、切换、刷新
- `CodexGroupService`
  - 分组 JSON 持久化
- `CodexInstanceService`
  - 实例配置管理
  - 启动/停止/定位窗口
  - 账号注入
- `CodexSessionService`
  - 扫描实例目录
  - 查询 SQLite
  - 读写 `session_index.jsonl`
  - trash/restore
- `CodexProcessService`
  - 进程启动、PID 匹配、窗口聚焦

状态管理建议：

- 简单场景可直接 `ObservableObject + @MainActor`
- 如果后面规模变大，再引入 `The Composable Architecture`

我的建议：**一期不要上 TCA，先用朴素 MVVM。**

---

## 8. 数据设计建议

### 8.1 应用侧数据

建议单独维护：

- `~/Library/Application Support/swichcodex/accounts.json`
- `~/Library/Application Support/swichcodex/account-groups.json`
- `~/Library/Application Support/swichcodex/instances.json`
- `~/Library/Application Support/swichcodex/session-trash/`
- `~/Library/Application Support/swichcodex/backups/`

### 8.2 不直接托管官方默认数据以外的敏感写入

建议原则：

- Codex 官方目录只做必要读写
- 应用自己的元数据放在 `Application Support`
- 所有 destructive 操作先做备份

---

## 9. 页面建议

### 9.1 账号总览

布局建议：

- 左侧：分组筛选
- 右侧：账号卡片网格/列表
- 顶部工具栏：
  - 添加账号
  - 刷新全部
  - 隐藏邮箱
  - 搜索

卡片字段建议：

- 显示名
- 邮箱/脱敏邮箱
- plan
- 配额摘要
- 最后刷新时间
- 标签
- 操作按钮：切换、刷新、编辑、删除

### 9.2 多开实例

布局建议：

- 实例列表表格
- 详情抽屉或右侧面板

字段建议：

- 实例名
- 绑定账号
- 实例目录
- 运行状态
- 启动模式
- 最后启动时间

### 9.3 会话管理

布局建议：

- 按项目目录分组的 sidebar/tree
- 主区域展示会话列表
- 顶部工具栏：刷新、删除、恢复入口

字段建议：

- 会话标题
- cwd
- 更新时间
- 所在实例数
- token 统计

---

## 10. 分阶段实施计划

### 阶段 0：验证

目标：

- 验证 macOS 原生项目可稳定读取 `~/.codex`
- 验证能成功启动带 `CODEX_HOME` 的独立 Codex 实例
- 验证能读取 `state_5.sqlite`

产出：

- 一个最小原型

### 阶段 1：账号

目标：

- 完成账号导入、展示、切换、刷新、分组

### 阶段 2：实例

目标：

- 完成实例创建、绑定、启动、停止、窗口定位

### 阶段 3：会话

目标：

- 完成会话聚合、分组、token 统计、trash/restore

### 阶段 4：稳定性

目标：

- 备份恢复
- 异常处理
- 并发读写保护
- 版本兼容性测试

---

## 11. 研发工作量预估

按一个熟悉 macOS 原生开发的人估算：

- 阶段 0：2 到 4 天
- 阶段 1：5 到 7 天
- 阶段 2：5 到 8 天
- 阶段 3：6 到 10 天
- 阶段 4：4 到 7 天

合计：

- MVP：约 3 到 4 周
- 含二期增强：约 5 到 7 周

---

## 12. 最终建议

建议正式立项，路线如下：

1. 先做 `macOS only`
2. 先做 `账号 + 多开 + 会话` 三件核心事
3. 一期避免把 OAuth 登录做得过重
4. 所有写操作都带备份和恢复
5. 会话能力先做“可读 + 可软删除 + 可恢复”，不要一开始就追求复杂同步

如果目标是尽快做出一个能用的 `swichcodex`，最佳路径是：

- 第一周做账号
- 第二周做实例
- 第三周做会话
- 第四周做稳定性和 UI 打磨

---

## 13. 建议的下一步

建议下一步直接在 `swichcodex` 下继续产出两份文档：

1. `product-requirements.md`
2. `technical-design.md`

其中：

- `product-requirements.md` 定义页面、交互、字段、按钮行为
- `technical-design.md` 定义数据模型、文件路径、服务接口、异常与备份策略

