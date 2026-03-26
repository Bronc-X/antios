# HARNESS_AGENT_DEVELOPMENT_PROCESS

> Status: active
> Mode: harness-agent
> Updated: 2026-03-26 07:33
> Product Surface: `Max`
> Current Phase: `H6 验证、清理、回归`
> Last Completed Phase: `H5 自动触发与 follow-up orchestration`
> Next Gate: `CoreSimulator service recovery or alternate UI smoke path`

---

## 1. 目的

这份文档是 `antios` 当前唯一的 harness-agent 开发进程主文件。

它解决三个问题：

1. 每次开发都知道现在处于哪个阶段。
2. 主代理、子代理、验证链路各自做什么，边界清楚。
3. 每一轮开发结束后，都能把“做到了哪、还差哪、下一步是什么”收口成固定格式。

说明：
- 当前产品名是 `antios`
- 主执行表面永远叫 `Max`
- 历史文档里残留的 `Coach` 仅视为旧命名，不再作为新开发口径

---

## 2. Harness Agent 工作模式

### 2.1 主代理

主代理负责：
- 锁定当前 phase
- 决定关键路径
- 亲自完成阻塞主线的实现
- 集成子代理结果
- 最终 build / simulator /测试验证
- 更新阶段状态

原则：
- 阻塞主线的工作不外包
- 子代理只处理平行侧查、局部实现、非阻塞验证

### 2.2 Explorer 子代理

Explorer 负责只读审计：
- UI 插点
- agent 接口兼容面
- 文件级影响范围
- 风险预警

Explorer 不直接决定产品，不直接代替主代理做主线判断。

### 2.3 Worker 子代理

Worker 负责：
- 清晰边界内的代码实现
- 与其他 worker 不重叠的写集
- 提交“改了什么文件 + 为什么”

Worker 必须知道：
- 自己不是唯一开发者
- 不得回滚别人的修改
- 有冲突时先适配，再集成

### 2.4 Validation 子代理

Validation 负责：
- build
- simulator 启动
- 目标测试
- 回归风险提示

如果验证阻塞主线，主代理自己接手，不等待子代理。

---

## 3. 阶段板

### H0 治理与命名对齐
状态：`completed`

目标：
- `antios` / `Max` 命名锁定
- 风险预防 + agent platform + 核融合回复 成为当前主线
- 前端轻、后端重原则锁定

退出条件：
- 治理和产品规格已同步

### H1 产品合同锁定
状态：`completed`

目标：
- Home 主入口锁定为 `先问身体`
- 核融合回复定义锁定
- 强度阈值锁定
- 自动采集优先原则锁定

退出条件：
- 公式、主路径、交互边界已拍板

### H2 共享 runtime 基线
状态：`completed`

目标：
- 建立结构化 runtime，而不是把判断散在页面里

当前已落地：
- `HealthRuntimeSnapshot`
- `RiskPreventionState`
- `FollowUpRuntime`
- `FusionReplyRuntime`
- risk / readiness / fusion / follow-up engine

退出条件：
- Home 和 Max 可以共用同一份主结论对象

### H3 Home 主路径接入
状态：`completed`

目标：
- 保留现有 UI 风格
- 把旧并列信息块收成：
  - Hero 主卡
  - guidance 卡
  - signal 卡

退出条件：
- Home 首屏已经能承载 `先问身体 + 主结论 + follow-up`

### H4 Max 首屏接入与 agent API 兼容
状态：`completed`

目标：
- Max 首屏先展示核融合主卡
- 保留原通知、shortcut、router 外部协议
- 不推翻现有 chat/sheet 结构

当前已落地：
- `fusionRuntime`
- `followUpRuntime`
- Max 首屏融合卡
- 新 intent 兼容映射

退出条件：
- `openMaxChat / askMax / router / MaxChatViewModel` 均可继续工作

### H5 自动触发与 follow-up orchestration
状态：`completed`

目标：
- workout 结束后自动构造复盘基础包
- 次日晨起自动重算恢复状态
- 尽量不让用户重复输入已有数据

当前已落地：
- `HealthKitService` 已补最近 workout 查询
- `A10AppShell` 已接 scene-active 自动检测
- 运动结束后会主动切到 Max 并发起 post-workout follow-up
- 次日晨起会基于恢复信号主动发起 next-day follow-up
- 触发已做本地去重，避免重复打扰

退出条件：
- Max 不只会“等用户问”，而会在正确时点主动接管

### H6 验证、清理、回归
状态：`in_progress`

目标：
- Home / Max 路径回归
- simulator 检查
- 旧逻辑与旧文案清理
- 关键测试补齐

当前已落地：
- H5 自动触发链已完成 build / simulator 验证
- widget 同步已从脆弱 key-value 扩成结构化 payload + 旧 key 兼容
- widget 对外文案已收回到 `antios`
- Max 在有融合主卡/ follow-up 卡时不再混入 starter questions
- 自动 follow-up 已补 draft / pending execution guard，并补上 source 语义
- 晨起恢复判定已改成带时间边界的 HRV 查询，晨间优先走 next-day follow-up
- 启动页 / 登录页 / onboarding / app display name 已继续向 `antios` 收口
- `ContentView` 中已退出 Home 主路径的旧并列信息残留已清理
- `WidgetSharedPayloadV1` 已抽到 `Shared/Widget/WidgetSharedPayload.swift`，app / widget 共用同一份 schema
- i18n 严格门禁已清零：`missing keys = 0`、`unresolved English = 0`
- Home 已取得一张真实 runtime 截图：`/tmp/antios_h6_smoke.png`
- simulator 可 boot / screenshot，但 `install`、`launch`、`ui appearance` 命令链仍会超时
- `WidgetSharedStore` 已统一 payload 写入与 legacy key fallback，新增 2 条 widget sync 单元测试
- Home / Max 融合卡已补 automation accessibility id，便于后续 UI smoke
- `xcodebuild` build 通过，`antios10Tests` 通过；`antios10UITests` 在当前 CoreSimulator 环境下未正常收束

退出条件：
- 构建、启动、主路径、风险提示、follow-up 路径均验证通过

### H7 发布门禁
状态：`pending`

目标：
- 发布前 build / signing / archive / smoke / release note 就绪

退出条件：
- 满足 TestFlight / 发布门禁

---

## 4. 当前阶段定义

当前阶段：`H6 验证、清理、回归`

### 4.1 当前阶段输入

- 已有共享 runtime
- 已有 Home 和 Max 第一版融合接入
- 已有通知、shortcut、router 外部协议
- 已有 workout-end / next-morning 自动触发链
- 已有 simulator build / launch 验证

### 4.2 当前阶段重点文件

- [HealthKitService.swift](/Users/mac/Desktop/antios10/antios10/Core/HealthKit/HealthKitService.swift)
- [MaxChatViewModel.swift](/Users/mac/Desktop/antios10/antios10/Features/Max/MaxChatViewModel.swift)
- [Notifications.swift](/Users/mac/Desktop/antios10/antios10/Shared/Notifications.swift)
- [AppShortcuts.swift](/Users/mac/Desktop/antios10/antios10/Core/Services/AppShortcuts.swift)
- [ContentView.swift](/Users/mac/Desktop/antios10/antios10/ContentView.swift)
- [A10ShellModels.swift](/Users/mac/Desktop/antios10/antios10/Models/A10ShellModels.swift)

### 4.3 当前阶段必须完成

1. 清理退出主路径但仍残留在文件里的旧逻辑。
2. 继续保持 Home / Max 视觉风格稳定，不因为 H5 回归为复杂前端。
3. 复核主动触发不会重复打扰，也不会打断现有对话主流程。
4. 补齐 H5 之后的 build / simulator / smoke 证据。

### 4.4 当前阶段不做

- 第二阶段专业医疗
- 复杂训练学模型
- 前端大改
- 新增独立 agent 页面
- 破坏现有 shortcut / notification 协议
- 在没有证据前扩大 H5 自动触发范围

---

## 5. 每轮开发循环

每个 task 都按下面的 harness-agent 流程走：

1. 主代理确认当前 phase，并更新计划。
2. 主代理先做关键路径判断。
3. 对非阻塞问题，启动 explorer / worker 子代理并行侧查。
4. 主代理完成主线实现与集成。
5. 运行 build / simulator / 必要测试。
6. 更新本文件顶部状态和阶段块。
7. 更新 [C_EXECUTION_AND_MEMORY.md](/Users/mac/Desktop/antios10/GOVERNANCE_ULTIMATE/C_EXECUTION_AND_MEMORY.md) 的当前步骤。
8. 执行 `say "master job done"`。

---

## 6. 阶段追踪格式

以后任何时刻，都必须能直接回答这 5 个字段：

- `当前阶段`
- `已完成阶段`
- `当前正在做的具体任务`
- `验证状态`
- `下一关口`

推荐输出格式：

```text
Current Phase: H6 验证、清理、回归
Completed: H0 / H1 / H2 / H3 / H4 / H5
In Progress: workout-end trigger, next-morning trigger
Validation: build pass, simulator launch pass
Next Gate: passive signal driven follow-up
```

---

## 7. 当前状态快照

Last Updated: 2026-03-26

Completed:
- H0 治理与命名对齐
- H1 产品合同锁定
- H2 共享 runtime 基线
- H3 Home 主路径接入
- H4 Max 首屏接入与 agent API 兼容

In Progress:
- H5 自动触发与 follow-up orchestration

Next:
- workout-end trigger
- next-morning trigger
- follow-up 被动数据拼装
- 主动弹出与缺口补问

Known Risks:
- 当前红旗仍主要基于已有恢复信号，显式症状捕获还未进入完整自动链
- workout 自动检测和次日复盘还未完全接通 HealthKit 触发链
