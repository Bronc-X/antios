# AntiAnxiety iOS Design Baseline (iOS 26 / Liquid Glass)

Last updated: 2026-02-14  
Scope: `/Users/mac/Desktop/Antianxiety/antios5/antios5` (SwiftUI-first)

## 0. 角色协作结论（强制定调）

- 角色 A（顶级前端设计师）结论：先建立严格语义 Token 和组件约束，减少“视图层硬编码”。
- 角色 B（顶级时尚设计师）结论：品牌情绪必须保留紫粉霓光识别，不做“中性企业蓝”。
- 角色 C（前端设计师）结论：所有借鉴点必须拆到按钮/Input/Card/Tab/图表五类组件，不接受抽象描述。
- 角色 D（前端代码工程师）结论：优先可复用 SwiftUI 组件，确保可测试、可接入、可灰度替换。
- 联合裁决：`Calm-Tech / Purple-Pink Liquid Glass`。
  - 70% 信息效率（可读性、层级、可维护）
  - 30% 情绪表达（玻璃材质、流光、品牌记忆点）

---

## 1. 设计语言定位

### 1.1 品牌关键词

- Calm（镇静）
- Intelligent（理性）
- Premium（高级）
- Fluid（流动）

### 1.2 视觉原则

- 内容优先：玻璃用于承载交互，不抢占正文注意力。
- 语义优先：颜色由“状态语义”驱动，不由“页面偏好”驱动。
- 统一节律：仅使用 4pt 间距网格与固定圆角阶梯。
- 渐进增强：iOS 26 用 Liquid Glass，旧系统自动降级为 Material。

---

## 2. 色彩规范（Color System）

## 2.1 品牌色（Brand）

- `brand.primary`: `#A855F7`（主紫）
- `brand.secondary`: `#DB2777`（玫粉）
- `brand.tertiary`: `#C4B5FD`（雾紫）
- `brand.softBg`: `#F9F5FF`（浅薰衣草底）
- `brand.darkBg`: `#1A1026`（深梅黑底）

## 2.2 语义色（Semantic）

- `semantic.success`: `#34C759`（系统绿）
- `semantic.warning`: `#FF9F0A`（系统橙）
- `semantic.error`: `#FF453A`（系统红）
- `semantic.info`: `#0A84FF`（系统蓝）

> 规范：状态色优先使用系统语义色，品牌紫粉不替代错误/警告含义。

## 2.3 文本色（Text）

- `text.primary.light`: `#2B1538`
- `text.secondary.light`: `#6B4D85`
- `text.tertiary.light`: `#8A6AA8`
- `text.primary.dark`: `#F9F2FF`
- `text.secondary.dark`: `#D6CBE6`
- `text.tertiary.dark`: `#B49FCF`

## 2.4 玻璃层级（Glass Surfaces）

- `surface.glass.1`（最低）：背景浮层 / 低优先信息
- `surface.glass.2`（标准）：表单、普通卡片
- `surface.glass.3`（突出）：CTA、关键摘要、浮动工具条

规则：
- 同屏最多出现 2 个玻璃层级。
- 不允许叠 3 层以上 blur + tint + stroke。

---

## 3. 排版规范（Typography）

## 3.1 字体策略

- 主字体：`SF Pro`（系统）
- 展示/情绪标题（可选）：`New York`（仅 Display/Hero）

## 3.2 字号梯度（iOS）

- `display.l`: 34 / semibold
- `display.m`: 28 / semibold
- `title.1`: 22 / semibold
- `title.2`: 20 / semibold
- `body`: 17 / regular
- `body.small`: 15 / regular
- `caption`: 13 / medium
- `micro`: 11 / medium

规则：
- 页面内最多 4 种字号角色。
- 数字型指标优先使用 `tabular`（等宽数字）风格。
- 兼容 Dynamic Type，正文最小不小于 11pt。

---

## 4. 圆角、间距、阴影规范

## 4.1 圆角（Radius Scale）

- `r.xs = 8`
- `r.sm = 12`
- `r.md = 16`
- `r.lg = 20`
- `r.xl = 24`
- `r.pill = capsule`

## 4.2 间距（Spacing Scale, 4pt grid）

- `s.1 = 4`
- `s.2 = 8`
- `s.3 = 12`
- `s.4 = 16`
- `s.5 = 20`
- `s.6 = 24`
- `s.8 = 32`
- `s.10 = 40`

## 4.3 阴影与描边

- 玻璃描边使用 1px 渐变高光，避免硬白线。
- 卡片阴影仅两档：`soft`（信息层），`elevated`（浮层 CTA）。

---

## 5. 核心组件标准

## 5.1 Button

变体：
- `PrimaryGlassButton`
- `SecondaryGlassButton`
- `DangerButton`
- `GhostButton`

尺寸：
- `h.44`（默认）
- `h.36`（紧凑）
- `h.52`（强调）

交互：
- 按下缩放 `0.97`
- 120~180ms 动画
- 禁用态对比度 >= WCAG AA

## 5.2 Input

标准字段：
- 高度：`44`
- 内边距：`12/14`
- 圆角：`r.md`
- 边框：语义化（默认/聚焦/错误）

禁止项：
- 输入框里直接写死 `.white.opacity(...)`
- 多处手写不同 cornerRadius

## 5.3 Card

变体：
- `Card.standard`
- `Card.elevated`
- `Card.concave`

规则：
- 卡片内垂直节奏：`12 or 16`
- 卡片组间距：`16 or 24`
- 卡片标题固定角色（`title.2`）

---

## 6. iOS 26 Liquid Glass 专项规范

- 优先系统组件自动获得玻璃效果（Tab/Toolbar/Sheet）。
- 自定义视图使用：`glassEffect`, `GlassEffectContainer`, `glassEffectID`。
- 强调视图才允许 tint。
- 搜索、底栏、工具栏避免自绘重背景，减少与系统玻璃冲突。

---

## 7. 项目硬编码体检（当前仓库）

扫描结果（Swift 文件 75 个）：
- `font(.system(size: ...))`：82 处
- `cornerRadius` 字面量：124 处
- `padding` 字面量：204 处
- `Color(hex: ...)`：69 处

高风险热点：
- `/Users/mac/Desktop/Antianxiety/antios5/antios5/Features/Onboarding/ClinicalOnboardingView.swift`
- `/Users/mac/Desktop/Antianxiety/antios5/antios5/Features/Max/MaxChatView.swift`
- `/Users/mac/Desktop/Antianxiety/antios5/antios5/Features/CoreHub/CoreHubView.swift`
- `/Users/mac/Desktop/Antianxiety/antios5/antios5/Features/ScienceFeed/ScienceFeedView.swift`

典型问题：
- 频繁 `.foregroundColor(.white/.black)` 绕过语义文本色。
- `Color.surfaceGlass(for: .dark)` 被硬编码为 dark，破坏浅色适配。
- 大量局部圆角/间距数值无法统一演进。

---

## 8. 标准化改造路线（建议 3 周）

### Phase 1（基础底座，3-4 天）

- 建立 `DesignTokens.swift`（Color/Type/Spacing/Radius/Elevation）
- 建立 `DesignComponentKit.swift`（Button/Input/Card）
- 禁止新增裸字面量颜色和圆角（Lint 规则）

### Phase 2（高频页面迁移，5-7 天）

- 先迁移：Dashboard / Report / MaxChat / Onboarding
- 清理 `.surfaceGlass(for: .dark)` 强制暗色调用
- 统一标题层级和按钮高度

### Phase 3（全局一致性，4-6 天）

- 清理剩余硬编码
- 补全深浅色对比与可访问性检查
- 输出最终组件目录与 Figma/代码映射

---

## 9. 验收标准（DoD）

- 新增页面不得出现裸 `Color(hex:)`（除 Token 文件）。
- 关键组件全部走 DesignComponentKit。
- 所有文本角色来自 Type Token，不允许页面自定义系统字号。
- 深浅色 + 动态字体 + 对比度通过抽样验收。

---

## 10. 本轮已落地到项目（代码）

- 新增入口：`/Users/mac/Desktop/antios5/antios5/Features/Settings/SettingsView.swift`  
  路径：设置 -> 支持与信息 -> 设计系统容器。
- 容器内容：A/B 色调、排版标尺、Button/Input/Card 样机、Lovi 逐字问句、Outsiders 图表、Tab 微交互、BottomSheet 尺寸。
- 目标：先把规范“跑起来”，再迁移业务页面。

---

## 11. 外部调研依据（2026）

官方（优先）
- iOS 26 What’s New: https://developer.apple.com/ios/whats-new/
- Liquid Glass 技术总览: https://developer.apple.com/documentation/technologyoverviews/liquid-glass
- WWDC25 - Build a SwiftUI app with the new design: https://developer.apple.com/videos/play/wwdc2025/323/
- Landmarks Liquid Glass Sample: https://developer.apple.com/documentation/SwiftUI/Landmarks-Refining-the-system-provided-glass-effect-in-toolbars
- Apple Design Resources（iOS 26 UI Kit / SF Symbols 7 / Icon Composer）: https://developer.apple.com/design/resources/
- Accessibility HIG（对比度与 Dynamic Type）: https://developer.apple.com/design/human-interface-guidelines/accessibility

开源（2025-2026）
- LiquidGlassSwiftUI: https://github.com/mertozseven/LiquidGlassSwiftUI
- LiquidGlassExamples: https://github.com/mizadi/LiquidGlassExamples
- SwiftyCrop（含 iOS 26 Liquid Glass 开关）: https://github.com/benedom/SwiftyCrop

Mobbin（你指定）
- 目标链接：
  https://mobbin.com/discover/apps/ios/latest?redirect_to=%2Fapps%2Fthe-outsiders-ios-d5773f84-1087-4bcf-91ec-38a2298bdb40%2Fcda7fe53-bc70-47c9-bfa5-c08a22ab71b9%2Fscreens
- 当前访问限制：未登录状态下仅返回登录/注册入口，无法抓取具体 screens 内容。
