# B_PRODUCT_AND_TECH_SPECS

> antios 产品与技术规格（合并版）
> 版本: v3.1.0
> 更新: 2026-03-23

---

## 1. PRD（产品需求）

### 1.1 产品概述
- 产品名称: `antios`
- 全称: `AntiAnxiety`
- 命名原则: 对外主品牌使用 `antios`，需要正式解释时再展开为 `AntiAnxiety`
- 版本目标: TestFlight v1.0（iOS 26.0+）
- 一句话价值: 用“问询 -> 校准 -> 解释 -> 行动”闭环降低焦虑波动。

### 1.2 核心成功标准
- 7 日闭环完成率作为北极星指标
- 核心路径端到端可跑通
- 关键状态（加载/空/错）全覆盖

### 1.2.1 当前阶段最重要的核心功能

阶段一先只聚焦三件事：

- `风险预防`
- `agent platform`
- `核融合回复`

说明：

- 第二阶段的专业医疗暂不进入当前产品主线
- 当前版本目标不是做医疗产品，而是做强 general wellness / recovery / safety runtime
- 核心竞争力不是页面复杂度，而是后端状态、规则、工具和 agent runtime 的深度

### 1.2.2 核融合回复的正式定义

`核融合回复` 定义为：

- 把身体信号
- 风险状态
- 证据
- 行动建议
- follow-up

融合成一条极简主回复。

产品约束：

- 前端默认只展示一个主结果卡
- 复杂拼装、规则判断、优先级排序、证据整合都在后端完成
- 前端只负责展示、确认、进入 follow-up 或 agent 调用

这意味着：

- 风险预防不是独立飘在外面的模块
- agent platform 也不是单独藏在架构层的概念
- 两者都要通过 `核融合回复` 进入用户主路径

### 1.2.3 三者融合关系

本阶段必须把以下三者合成一个产品主轴：

- `风险预防`
- `agent platform`
- `核融合回复`

统一解释：

- 风险预防负责判断“今天适不适合做、要不要降级、是否需要升级处理”
- agent platform 负责把状态、工具、规则和 follow-up 做成 runtime
- 核融合回复负责把结果压缩成用户能立刻理解和执行的一张主卡

一句话：

`后端做复杂融合，前端做极简承载。`

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
- F11 运动强度风险预防
- F12 agent platform runtime
- F13 核融合回复能力

### 1.4 非目标（Out of Scope）
- 社交社区
- 支付订阅闭环
- Android/Web 同步发布
- 非 Apple 可穿戴接入

### 1.5 新增方向：运动强度风险预防（真实帮助用户）

目标不是做“运动激励”或“跑步打卡”，而是做：

- 运动前风险预检
- 中高强度运动降级建议
- 运动中红旗症状拦截
- 运动后恢复复盘

一句话价值：

`在用户准备进行跑步或中高强度运动时，帮助其判断今天是否适合上强度；一旦出现危险信号，优先阻止风险而不是鼓励继续。`

### 1.6 该方向为什么适合 AntiAnxiety

当前产品已经具备：

- Apple Watch / HealthKit 信号
- 压力、焦虑、能量、睡眠、恢复相关状态
- Max 对话式低摩擦交互
- 闭环 follow-up 机制

因此最合理的定位不是“通用跑步工具”，而是：

`恢复与安全优先的运动决策助手`

### 1.7 运动强度风险预防的 v1 范围（In Scope）

- R1 运动前 30 秒预检
- R2 红旗症状强提醒与拦截
- R3 中高强度自动降级为轻/中强度建议
- R4 运动后 30 分钟复盘
- R5 次日晨起恢复复盘
- R6 Max 中的风险词命中后切换到安全流程

### 1.8 明确不做（Out of Scope）

- 不做疾病诊断
- 不做运动处方
- 不做心血管疾病筛查结论
- 不做替代医生的“允许你运动/禁止你运动”判定
- 不做未经验证的医疗级测量宣称

### 1.8.1 前端不做的事

- 不做多层复杂判断面板
- 不把风险评分解释拆成过多页面
- 不让用户自己在前端拼凑结论
- 不让前端承载 agent runtime 的复杂推理链

### 1.9 运动风险预检的最小输入

- 今日计划强度：轻 / 中 / 高
- 今日主观疲劳
- 昨夜睡眠
- 当前是否发热或感染后未恢复
- 当前是否存在胸痛 / 胸闷 / 头晕 / 晕厥感 / 明显气短 / 持续心悸
- Talk Test：可完整说话 / 只能短句 / 难以说话

系统补充输入：

- HRV 相对基线偏移
- 静息心率相对基线偏移
- 最近 7 天活动与恢复情况
- 最近一次运动后的恢复反馈

### 1.10 v1 输出分层

- 绿色：可按计划进行，但仍需注意自我感受
- 黄色：建议降级到轻到中等强度，缩短时长，避免冲刺/间歇/长距离
- 红色：不建议继续中高强度运动；如伴随红旗症状，提示尽快就医或急救

### 1.11 红旗症状（必须优先拦截）

- 胸痛或胸部压迫感
- 晕厥、濒晕、明显头晕
- 与平时不相称的呼吸困难
- 持续或异常的心悸 / 心律不齐感
- 冷汗、恶心、濒死感、上肢/肩背/颈部放射不适
- 热环境下的明显异常不适

产品要求：

- 一旦命中，不继续给“坚持一下”“再跑一点”之类建议
- 优先输出停止运动、降温、休息、联系他人、必要时急救/就医

### 1.11.1 核融合回复在风险场景下的输出结构

风险场景下的主结果卡按固定顺序输出：

1. `结论`
2. `原因`
3. `现在该做什么`
4. `今天不要做什么`
5. `下一次 follow-up`

示例方向：

- 结论：今天不建议继续中高强度运动
- 原因：恢复信号偏弱，且你报告了异常不适
- 现在该做什么：停止运动，补液，休息，必要时联系医生
- 今天不要做什么：不要继续跑步冲刺、间歇或加量
- 下一次 follow-up：30 分钟后确认是否恢复，明早复查

### 1.12 运动后真实帮助用户的闭环

- 运动后 30 分钟：
  - 是否恢复到平时水平
  - 是否有胸闷 / 心悸 / 异常疲劳 / 头晕
- 次日晨起：
  - HRV 是否明显下降
  - 静息心率是否明显升高
  - 睡眠是否明显变差
  - 主观疲劳是否异常

输出目的：

- 区分正常训练刺激
- 区分恢复不足
- 区分需要降级
- 区分需要求助

### 1.13 该功能的专业边界

必须始终保持以下定位：

- 本产品提供一般健康管理、恢复建议与风险提醒
- 本产品不提供医疗诊断
- 本产品不替代医生、急诊或专业运动医学评估
- 一旦出现急性危险信号，产品职责是升级，而不是继续解释

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

### 2.5 新增关键流程：运动强度风险预防

#### Flow A：运动前预检
`Home / Coach 快捷入口 -> 30 秒预检 -> 风险分层 -> 给出强度建议或拦截`

#### Flow B：运动中红旗
`用户主动报告 / Max 命中红旗词 -> 停止运动提示 -> 升级处理 -> 求助路径`

#### Flow C：运动后复盘
`运动结束 -> 30 分钟复盘 -> 次日晨起复盘 -> 更新恢复状态`

#### Flow D：风险升级
`命中红旗 -> 终止一般建议 -> 明确提示求医 / 急救 / 联系支持`

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

### 3.5 医疗专业边界与技术约束

- 不宣称用 iPhone 传感器直接测量未经验证的医疗指标
- 不输出“诊断为”“排除为”“治疗方案为”这类医疗结论
- 高风险建议必须优先走规则层，不只依赖 LLM
- 风险升级链路必须可审计、可回放、可测试
- 涉及 HealthKit 的使用必须仅限健康管理与直接用户收益，不得用于广告画像

---

## 4. FRONTEND_GUIDELINES（前端规范）

### 4.1 视觉基调
- 主风格: Calm Daylight Glass（浅色优先，低噪音、可读性优先）
- 语义反馈: 使用 success/warning/error，不用品牌色替代语义色
- 信息层级: 主任务 > 下一步动作 > 证据说明 > 次要配置

### 4.1.1 前端原则（本阶段必须遵守）

- 前端保持简洁、清晰、低认知负担
- 不把复杂判断堆进页面
- 不为了“显得专业”做复杂多层前端
- 能放到后端和 runtime 的复杂逻辑，尽量不放在前端
- 前端主要承担：展示、确认、触发、follow-up、agent 调用入口

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

### 5.1.1 后端原则（本阶段允许更复杂）

- 复杂度优先放在后端模块、规则层、runtime 和 agent orchestration
- 前端不承担核心医疗/风险逻辑
- 后端可以复杂，但必须模块化、可测试、可审计
- agent 平台能力优先做成后端可调用能力，而不是页面私有逻辑

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

### 5.5 新增领域模型：Exercise Safety Runtime

建议新增统一运行时状态，而不是分散在页面文案中：

- `exercise_readiness_state`
- `exercise_intensity_plan`
- `exercise_red_flag_state`
- `post_exercise_recovery_state`
- `escalation_required`

### 5.5.1 新增领域模型：Agent Platform Runtime

建议同步建立：

- `health_runtime_snapshot`
- `risk_prevention_state`
- `agent_handoff_intent`
- `fusion_response_context`
- `agent_action_contract`

目标：

- Max 可调用
- Home 可消费
- 未来外部 agent 可复用
- 前端只取结果，不持有复杂推理过程

### 5.5.2 新增领域模型：Fusion Reply Runtime

建议后端建立统一融合回复对象：

- `primary_conclusion`
- `risk_level`
- `body_signal_summary`
- `evidence_summary`
- `recommended_action`
- `blocked_actions`
- `follow_up_task`
- `escalation_path`

要求：

- 所有关键模块都汇入这一对象
- Home / Coach / 快捷入口都消费同一份结果
- 前端不再分别拼接身体、证据、动作、风险文案

### 5.5.3 运行时优先级

后端融合时的优先级必须固定：

1. 急性风险 / 红旗
2. 今日是否适合上强度
3. 身体信号与恢复状态
4. 可执行动作
5. follow-up
6. 证据解释

原因：

- 防止证据说明盖过安全结论
- 防止行动建议先于风险拦截
- 防止前端出现信息太多、主结论不清

---

## 7. 品牌与文案方向

### 7.1 当前 slogan 候选

建议保留你这两句作为主方向，做轻微语言校正：

- `这个运动，今天不一定非得做`
- `要跑步？先问身体`

说明：

- 第一条适合风险预防总口号
- 第二条适合跑步 / 中高强度运动入口

### 7.2 文案气质要求

- 不说教
- 不吓唬
- 不热血硬推
- 不默认鼓励加量
- 优先给用户“今天可以少做一点，也算对身体负责”的许可感

### 5.6 Exercise Safety Runtime 的输入

- HealthKit：HRV、静息心率、步数、睡眠
- 日志：运动时长、疲劳、焦虑、能量
- 用户即时输入：症状、计划强度、talk test
- Max follow-up：运动后与次日恢复结果

### 5.7 Exercise Safety Runtime 的输出

- 今日建议强度
- 是否降级
- 是否不建议继续
- 红旗原因
- 后续复盘任务
- 是否建议联系医生 / 急救

### 5.8 医疗专业与上架合规策略

#### 定位策略

- 对外定位为 general wellness / health management / recovery support
- 不把产品主叙事写成 diagnosis / treatment / clinical decision

#### 交互策略

- 所有高风险输出使用保守语言
- 所有医疗相关建议附带“请结合医生意见，不要仅依据 app 做医疗决策”
- 急性危险信号不继续聊天式劝说，直接切换危机/就医流程

#### 规则策略

- 运动安全与急性红旗优先用规则引擎
- LLM 只负责解释、重述、陪伴、后续整理
- 不让 LLM 单独决定是否继续高强度运动

#### 数据策略

- 健康数据仅用于健康管理与用户直接收益
- 不用于广告、营销或画像挖掘
- 第三方 AI 使用前必须显式告知并获得同意

#### 审核策略

- App Review 资料里清楚说明：
  - 数据来源
  - 方法边界
  - 不是医疗诊断工具
  - 高风险情景会建议联系医生或急救
- 如未来某项能力要宣称医疗准确性或医疗用途，再进入额外监管评估

### 5.9 对外文案红线

允许：

- “恢复建议”
- “风险提醒”
- “一般健康管理”
- “运动前安全预检”
- “帮助你决定今天是否适合上强度”

禁止默认使用：

- “诊断”
- “治疗”
- “确定你患有”
- “替代医生”
- “本 app 可直接检测心脏疾病”

---

## 6. 合规依据（当前策略参考的官方方向）

- Apple App Review Guidelines 1.4 Physical Harm：
  - 医疗 app 若可能提供不准确数据或可用于诊断/治疗，会受到更高审查
  - 健康测量准确性如无法验证，可能被拒
  - 医疗类 app 应提醒用户在做医疗决策前咨询医生
- Apple App Review Guidelines 5.1.3 Health and Health Research：
  - HealthKit / 健康数据不得用于广告、营销或基于使用的数据挖掘
  - 不得向 HealthKit 写入虚假或不准确数据
- FDA General Wellness: Policy for Low Risk Devices（2026-01）：
  - 仅用于维持/鼓励健康生活方式、且与疾病诊断/治疗/预防无关的软件，可落在 general wellness 边界
- FDA Device Software Functions Including Mobile Medical Applications：
  - 软件监管按功能和风险划分，而不是按“是不是 app”粗暴划分

对本产品的直接含义：

- 当前最稳妥路线是先把 AntiAnxiety 定位在 general wellness / recovery / risk reminder
- 如未来要做明确医疗用途功能，必须单独走医疗监管与准确性验证路线
