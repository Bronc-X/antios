# Agent Platform Research Kickoff

Updated: 2026-03-26
Workspace: `main`
Method: agent-harness workflow

## 1. Goal

把 `antios10` 从“带 AI 聊天的健康 App”推进到“可被人和 agent 共用的健康运行时”。

这次 kickoff 不重新发明方向，而是基于仓库现状确认三件事：

1. 已经有什么
2. 还缺什么
3. 下一批最合理的工程切入点是什么

## 2. 已有基础

从现有仓库可确认，基础并不是从零开始：

- `ANTIOS_AGENT_PLATFORM_V1.md` 已经把目标定义成 agent-first runtime
- `ANTIOS10_AGENT_EXECUTION_PLAN.md` 已经写出了 sensor -> memory -> coach 的主链路
- `MaxChatViewModel` 已经承担主要 agent surface
- `MaxMemoryService` 已经具备 memory kind、pending queue、flush 与 retrieval 机制
- `Dashboard` / `Home` / `Max` 三条主用户路径已经存在
- `SupabaseManager` 已经承担状态、认证、远端 API 与部分工具层责任

结论：
方向文档已经够了，当前问题不是“没想法”，而是“平台合同还没真正拆成可复用的 typed capabilities”。

## 3. 当前缺口

### 3.1 还没有清晰的 agent tool contract

当前大部分能力仍以 ViewModel 或 Manager 方法形式存在，例如：

- dashboard 获取
- inquiry 获取
- proactive brief 生成
- 计划保存
- 用户信号写入

这些能力能被 app 调，但还不是稳定的 agent tool surface。

### 3.2 状态层仍偏页面导向

文档里强调：

- summarized state snapshot
- active plan state
- uncertainty flags
- evidence summary
- action outcome summary

但代码里这些状态更多分散在页面模型、请求结果和缓存之间，还没有收束成统一 agent state contract。

### 3.3 Home -> Max handoff 仍然偏产品流程，不够平台化

现有 handoff 能跑，但“为什么切过去、带什么意图、拿什么上下文、写回什么结果”还没有形成统一协议。

### 3.4 外部 agent 可调用性仍缺位

当前系统更像：

- App 内部有一个 Max

而不是：

- App 内部和未来外部 agent 都可以调用同一批 health runtime tools

## 4. 现在最值得先做的三层抽象

### 4.1 Agent State Layer

先抽出一个稳定状态快照：

- `body_state`
- `plan_state`
- `inquiry_state`
- `evidence_state`
- `safety_state`

要求：

1. 对 UI 可读
2. 对 agent 可调用
3. 对缓存和本地回退可序列化

### 4.2 Agent Tool Layer

把现有能力收口成明确工具：

- `get_health_state_snapshot`
- `get_active_plan`
- `get_pending_inquiry`
- `capture_user_signal`
- `generate_micro_action`
- `review_action_outcome`
- `get_ranked_evidence`

要求：

1. 输入输出 typed
2. 不直接绑某个页面
3. 允许 Max 和未来外部 agent 复用

### 4.3 Agent Outcome Layer

把 agent 的产出收口成固定结构，而不是散在 message text：

- next action
- reason
- evidence
- follow-up question
- review hooks

## 5. 推荐的第一批工程线程

### Thread A: Runtime Contract 抽取

优先级最高。

目标：

- 建立 health runtime snapshot
- 建立 tool input/output model
- 从 `SupabaseManager` / `MaxChatViewModel` 拆出可复用 contract

### Thread B: Home / Max Handoff 协议化

目标：

- 把 handoff 从“页面跳转”变成“意图 + 上下文 + 预期结果”

### Thread C: Agent Card Surface

目标：

- 把 Max 线程中的关键输出逐步固定为结构化 card
- 减少纯文本临时生成物

### Thread D: Validation Harness

目标：

- 为关键 runtime contract 建单测
- 为 handoff 建回归测试
- 为 memory / inquiry / plan 主链路建立检查基线

## 6. 为什么现在适合开始

因为这次已经顺手修掉了一部分平台级基础问题：

- 认证 token 不再落在 `UserDefaults`
- 离线状态不再伪装成完整登录态
- widget 共享链路开始回到真实数据而不是模板壳

这些都不是 agent platform 本身，但它们是在把系统从 demo 习惯拉回正式产品边界。

## 7. 下一步建议

下一轮直接做：

1. 定义 `HealthRuntimeSnapshot`
2. 定义第一批 `AgentTool` 输入输出模型
3. 让 Home 和 Max 都消费同一份 runtime snapshot
4. 把当前最常用的 2 到 3 个能力改造成真正的 tool contract

## 8. 这轮 kickoff 的结论

`antios10` 已经具备 agent-first 产品的雏形，但还没有完成平台化。  
最缺的不是更多 prompt，而是：

- 稳定状态
- 稳定工具
- 稳定产出
- 稳定验证
