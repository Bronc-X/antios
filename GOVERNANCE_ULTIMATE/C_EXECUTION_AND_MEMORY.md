# C_EXECUTION_AND_MEMORY

> AntiAnxiety iOS 执行计划与会话记忆（合并版）
> 版本: v3.1.0
> 更新: 2026-03-23

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
- 3 Tab Shell（Home / Coach / Me）启动

### 阶段 R2: sensor-first + agent-first 基线（进行中）
- 将 Apple Watch / HealthKit 身体指标升级为最高优先级记忆输入
- 将 Max/Coach 定义为主要执行表面
- 将校准 / 计划 / 证据 / 跟进迁移到 agent-led 结构化交互

### 阶段 5: 发布（待完成）
- 密钥治理与轮换
- 签名与打包链路
- TestFlight 回归与发布记录

当前步骤: 阶段 R2（sensor-first + agent-first 基线）

---

## 2. AGENT_RULES（执行规则）

### 2.1 必须遵守
- 只做当前最小步骤，不跳步。
- 不新增未批准依赖。
- 不做硬编码妥协。
- 每次任务结束更新本文件状态块或 D 文件发布块。

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

Last Updated: 2026-03-23 11:35

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

In Progress:
- 将 wearable sync 接入 sensor-derived memory
- 将 `ai_memory` 从单池写入改为 memory-kind 分层
- 为 RAG 增加 body memory 优先级

Next:
- 让 Coach 承载 check-in / action / review 的结构化卡片
- 将 Calibration / Plans / Inquiry 迁移为 thread-first
- 继续拆分 `SupabaseManager`

Known Issues:
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
