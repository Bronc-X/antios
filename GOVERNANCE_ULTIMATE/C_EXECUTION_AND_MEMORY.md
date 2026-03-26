# C_EXECUTION_AND_MEMORY

> AntiAnxiety iOS 执行计划与会话记忆（合并版）
> 版本: v3.1.0
> 更新: 2026-03-26

---

## 1. IMPLEMENTATION_PLAN（实施计划）

### 阶段 1: 初始化（完成）
- 工程结构与模块目录建立
- iOS 26 / Swift 5.0 编译基线确定
- 基础脚本（QPI/性能探针）建立

### 阶段 2: 核心框架（完成）
- 路由门禁骨架（Launch/Auth/Onboarding/Main）
- 设计 token 与组件骨架（Liquid Glass）
- Supabase + AI + HealthKit 服务骨架

### 阶段 3: 功能模块（主线完成）
- Dashboard / Report / Max / Plans / Settings
- Clinical Onboarding / Onboarding / Assessment
- 聊天、计划、画像、设备数据链路

### 阶段 4: 联调与稳定性（进行中）
- API 通道稳定性
- 空/错/加载状态收敛
- 轻量交互改弹窗（减少无必要跳转）

### 阶段 R1: antios10 重构启动（完成）
- 蓝图与治理同步
- `codex/antios10` 分支建立，后续改名为 `main`
- SwiftData local-first 主壳层搭建
- 3 Tab Shell（Home / Max / Me）启动

### 阶段 R2: sensor-first + agent-first 基线（进行中）
- 将 Apple Watch / HealthKit 身体指标升级为最高优先级记忆输入
- 将 Max 定义为主要执行表面
- 将校准 / 计划 / 证据 / 跟进迁移到 agent-led 结构化交互

### 阶段 H0-H7: harness-agent 主线（进行中）
- 以 `HARNESS_AGENT_DEVELOPMENT_PROCESS.md` 作为唯一阶段追踪文件
- 主代理负责关键路径与阶段切换
- explorer / worker / validation 子代理按边界介入
- 每个 task 结束必须更新阶段状态并做验证

### 阶段 5: 发布（待完成）
- 密钥治理与轮换
- 签名与打包链路
- TestFlight 回归与发布记录

当前步骤: 阶段 H6（验证、清理、回归）

---

## 2. AGENT_RULES（执行规则）

### 2.1 必须遵守
- 只做当前最小步骤，不跳步。
- 不新增未批准依赖。
- 不做硬编码妥协。
- 每次任务结束更新本文件状态块或 D 文件发布块。
- 每次任务结束同步 `HARNESS_AGENT_DEVELOPMENT_PROCESS.md` 的状态块。

### 2.2 会话启动必读
- 先读 A 的红线与风险
- 再读 B 当前要改的板块
- 最后读 C 的“当前步骤”
- 若在 `main` 分支上工作，补读 `ANTIOS10_BLUEPRINT.md`

### 2.3 交付必做
- 给出改动文件与原因
- 给出剩余风险与下一步
- 执行 `say "master job done"`

---

## 3. INTERROGATION（审问清单）

### 用户与价值
1. 目标用户是谁？
2. 用户最重要动作是什么？
3. 完成动作后系统可交付结果是什么？

### 数据与流程
4. 存哪些数据？
5. 展示哪些数据？
6. 失败/空/慢网怎么处理？
7. 需要登录/权限/角色吗？

### 平台与约束
8. 是否必须移动端？
9. 依赖哪些第三方服务？
10. 合规边界是什么？

### 范围
11. 本期必须做什么？
12. 本期不做什么？
13. 什么条件才算可发布？

---

## 4. PROGRESS（当前状态）

Last Updated: 2026-03-26 06:26

Done:
- 治理模板 4 包已引入
- 旧治理文件已清理
- 产品/技术/执行/发布合并到四文件
- 全量审计已完成并输出附录
- `Secrets.xcconfig` 已收敛为可提交模板，真实值转入本地私有配置
- 模拟器 Debug build 已通过
- `EXECUTION_GOVERNANCE.md` 已补齐
- `ANTIOS10_BLUEPRINT.md` 已重写为 sensor-first + agent-first 蓝图
- `ANTIOS10_AGENT_EXECUTION_PLAN.md` 已新增并定义 agent 工作顺序
- `main` / `old10` 分支职责已重新对齐
- Home / Max 第一版核融合主卡已经接入
- 共享 runtime 已建立：risk / readiness / fusion / follow-up
- 模拟器 build 与启动验证已通过
- workout-end 与次日晨起自动触发链已接入 shell
- HealthKit 最近 workout 查询与晨起恢复信号检测已接入
- H5 变更已完成干净 build，并在模拟器重新安装拉起
- widget 同步链已升级为结构化 payload + 旧 key 兼容
- widget 文案已回收到 `antios`，并移除无效 deep link
- Max 首屏在有结构化主卡时已隐藏 legacy starter questions
- 自动 follow-up 已增加 draft / pending execution guard 与 source 语义
- 晨起恢复判定已加 HRV 时间边界，并在 morning window 优先 next-day follow-up
- 启动页、登录页、onboarding、widget 与 app display name 已继续向 `antios` 收口
- `ContentView` 中退出主路径的旧并列信息残留已清理
- `WidgetSharedPayloadV1` 已抽为 `Shared/Widget/WidgetSharedPayload.swift`，app 与 widget 共用单一定义
- `WidgetSharedStore` 已接管 payload + legacy key 写入，widget 改为共用同一读取路径
- 新增 widget sync 单元测试 2 条，已通过
- Home / Max 关键融合卡已补 automation accessibility id

In Progress:
- 将 wearable sync 接入 sensor-derived memory
- 将 `ai_memory` 从单池写入改为 memory-kind 分层
- 为 RAG 增加 body memory 优先级
- 清理 H5 后低风险旧文案和旧入口残留
- 复核主动触发的去重、时段、会话打断边界
- 继续做 Max / widget 的补充 smoke 与低风险残留清理
- 继续处理 simulator `install / launch / appearance` 命令链阻塞

Next:
- 让 Max 承载 check-in / action / review / follow-up 的结构化主卡
- 将 Calibration / Plans / Inquiry 迁移为 thread-first
- 继续拆分 `SupabaseManager`
- 补一轮 Max / widget 主路径 smoke 与定向回归
- 继续清理 shared widget schema 接入后的低风险残留与 smoke

Known Issues:
- simulator 当前可 `bootstatus`、可截图，但 `simctl install / launch / ui appearance` 命令链会超时
- 当前进一步确认：`simctl install / launch` 失败根因是 `CoreSimulatorService connection became invalid` / `Connection refused`
- `simdiskimaged` 系统级 kickstart 被系统拒绝，当前无法在本会话内直接修复
- Home 已拿到真实运行截图 `/tmp/antios_h6_smoke.png`，但 Max / widget 缺少新的运行期证据
- i18n 严格门禁已清零：`/tmp/ios_i18n_strict_20260326_070036.json`
- P1: `xcodebuild test` 在当前模拟器会话中存在收尾不稳定，需要单独复核 UI 自动化环境
- P1: 发布签名与 archive 链路仍需真机/TestFlight 环节补齐

---

## 5. LESSONS（防复发）

### [2026-03-04] 治理缺失导致规则漂移
- 错误模式: 长期依赖会话记忆推进开发
- 根因: 治理文档缺失
- 防复发: 先更新四文件，再动代码

### [2026-03-04] 密钥硬编码进仓库
- 错误模式: `Secrets.xcconfig` 写入真实 key
- 根因: 本地调试与仓库配置未隔离
- 防复发: 仓库只留模板，真实值由本地/CI 注入

### [2026-03-04] 发布门禁后置导致签名阻断
- 错误模式: 临近发布才发现 profile 缺失
- 根因: 未前置执行 archive 预检
- 防复发: 每周固定跑一次发布构建预检
