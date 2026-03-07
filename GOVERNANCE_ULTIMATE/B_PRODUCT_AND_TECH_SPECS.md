# B_PRODUCT_AND_TECH_SPECS

> AntiAnxiety iOS 产品与技术规格（合并版）
> 版本: v3.1.0
> 更新: 2026-03-07

---

## 1. PRD（产品需求）

### 1.1 产品概述
- 产品名称: AntiAnxiety iOS（旧版稳定线: `main`，最新 app 开发线: `codex/antios10`）
- 版本目标: TestFlight v1.0（iOS 26.0+）
- 一句话价值: 用“问询 -> 校准 -> 解释 -> 行动”闭环降低焦虑波动。

### 1.2 核心成功标准
- 7 日闭环完成率作为北极星指标
- 核心路径端到端可跑通
- 关键状态（加载/空/错）全覆盖

### 1.3 功能范围（In Scope）
- F1 登录与会话恢复（Supabase Auth）
- F2 临床量表引导（GAD-7/PHQ-9/ISI）
- F3 普通 Onboarding（5 步）
- F4 Dashboard 闭环主屏
- F5 Max 对话与计划生成
- F6 每日校准
- F7 科学解释与趋势报告
- F8 行动计划与目标管理
- F9 设置与权限管理
- F10 三语支持（zh-Hans/en/zh-Hant）

### 1.4 非目标（Out of Scope）
- 社交社区
- 支付订阅闭环
- Android/Web 同步发布
- 非 Apple 可穿戴接入

---

## 2. APP_FLOW（流程与页面）

### 2.1 入口门禁
`Launch -> Auth -> Clinical Onboarding -> Onboarding -> Main Shell`

### 2.2 主导航（3 Tab Shell）
- Home
- Coach
- Me

能力映射：
- Dashboard -> Home
- Report -> Home 内 Evidence
- Max -> Coach
- Plans -> Home / Coach 内行动闭环
- Settings -> Me

### 2.3 关键覆盖流程
- 冷启动与会话恢复
- 登录/注册
- 临床基线与普通引导
- Dashboard 到执行动作
- Max 对话到计划落地

### 2.4 关键异常分支
- 网络失败: 重试 + 错误提示
- 空数据: 显示下一步引导
- 未授权: 引导到权限页重试

---

## 3. TECH_STACK（技术栈）

### 3.1 锁版本
- Xcode: 26.2 (`17C52`)
- iOS Deployment Target: 26.0
- Swift: 5.0
- 架构: SwiftUI + SwiftData + URLSession + Supabase REST/Auth

### 3.2 主要系统框架
- SwiftUI, Foundation, UIKit
- HealthKit, ActivityKit, WidgetKit, AppIntents
- UserNotifications, Speech, LocalAuthentication, Charts

### 3.3 外部服务
- Supabase（认证与数据）
- App API（onboarding/assessment/chat/insight 等）
- OpenAI-compatible 模型网关
- 可选 Cohere Rerank

### 3.4 环境变量与安全约束
- 允许: URL、超时、重试、fallback chain 等配置参数
- 禁止: 真实密钥入库
- 必须: 上线前轮换已暴露密钥

---

## 4. FRONTEND_GUIDELINES（前端规范）

### 4.1 视觉基调
- 主风格: Calm Daylight Glass（浅色优先，低噪音、可读性优先）
- 语义反馈: 使用 success/warning/error，不用品牌色替代语义色
- 信息层级: 主任务 > 下一步动作 > 证据说明 > 次要配置

### 4.2 Token 与组件入口
- 过渡期允许在新壳层中先建立 V2 token，再逐步回迁共享主题层
- 目标组件:
  - `ShellScaffold`
  - `FocusHeroCard`
  - `LoopStepRow`
  - `ActionCard`
  - `CoachBubble`
  - `SettingsRow`

### 4.3 布局系统
- `ScreenMetrics` 统一安全区、列宽、紧凑布局
- `liquidGlassPageWidth()` 统一页面列宽与居中

### 4.4 当前硬编码基线（需持续收敛）
- Swift 文件: 75
- `Color(hex:)`: 84
- `cornerRadius` 字面量: 177
- `padding` 字面量: 317
- `font(.system(size: ...))`: 114

---

## 5. BACKEND_STRUCTURE（后端结构）

### 5.1 架构
- 三层:
  - SwiftData（本地 UI 状态、草稿、闭环快照、计划、会话）
  - Supabase REST/Auth（认证与同步主数据）
  - App API（业务编排与推断）

### 5.2 关键数据表（代码依赖）
- `profiles`
- `daily_wellness_logs`
- `daily_calibrations`
- `user_assessment_preferences`
- `user_scale_responses`
- `phase_goals`
- `user_plans`
- `user_plan_completions`
- `chat_sessions`
- `chat_conversations`
- `unified_user_profiles`
- `user_health_data`
- `analysis_history`
- `inquiry_history`
- `bayesian_beliefs`
- `ai_memory`

### 5.3 关键 API（App API）
- `/api/health`
- `/api/chat`
- `/api/onboarding/progress`
- `/api/onboarding/save-step`
- `/api/onboarding/skip`
- `/api/onboarding/reset`
- `/api/assessment/start`
- `/api/assessment/next`
- `/api/assessment/dismiss-emergency`
- `/api/curated-feed`
- `/api/understanding-score`
- `/api/ai/generate-inquiry`
- `/api/ai/analyze-voice-input`
- `/api/insight/generate`
- `/api/insight`
- `/api/ai/deep-inference`
- `/api/digital-twin/explain-recommendation`
- `/api/recommendations/daily`

### 5.4 认证与授权
- Email/Password + token refresh
- 会话失效强制回登录
- HealthKit/语音/通知权限由系统授权流程控制
