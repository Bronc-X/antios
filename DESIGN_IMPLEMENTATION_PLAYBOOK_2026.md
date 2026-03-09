# AntiAnxiety UI 定型执行手册（四角色联审）

Last updated: 2026-02-14

## 0. 结论先行

- 主路线：`Purple-Pink Liquid Glass`（主风格），`Forest Green`（并行备选皮肤）。
- 设计原则：先稳定底座 Token/组件，再迁移页面，不再逐页 vibe coding。
- 本轮状态：规范文档 + 代码容器 + 帧级参考均已具备，可进入批量改版。

---

## 1. 四角色对抗与裁决

### 议题 A：品牌主色是紫粉还是绿色

- 角色 A（顶级前端设计师）：主色不应频繁切换，建议单一主品牌。
- 角色 B（顶级时尚设计师）：紫粉更有情绪识别和高级感，绿可做功能态。
- 角色 C（前端设计师）：两套都保留，但用同构布局做 A/B。
- 角色 D（前端代码工程师）：统一 API，`stylePreset` 切换，不复制页面代码。
- 裁决：主品牌走紫粉，绿色做可切换预设，不走双品牌分裂。

### 议题 B：动效要不要重

- 角色 A：动效只服务信息结构，不做炫技。
- 角色 B：关键节点必须有“记忆点”（逐字、流光、卡片浮起）。
- 角色 C：每屏最多 1 个主动态。
- 角色 D：统一时长曲线，便于调参与回归。
- 裁决：保留强识别动效，但总量受控。

### 议题 C：系统原生 vs 自定义

- 角色 A：优先系统（键盘、sheet、tab、授权弹窗）。
- 角色 B：自定义只在品牌 Hero 和 CTA 区域。
- 角色 C：页面过渡借系统节奏做“轻自定义”。
- 角色 D：减少手写复杂动画，避免维护成本。
- 裁决：系统优先，自定义增强。

---

## 2. 组件标准（可直接落地）

## 2.1 Button（主次 CTA）

- 高度：44（常规）/ 52（重点）
- 圆角：16
- 字重：Semibold 15
- 动效：按下 `scale 0.98`，抬起恢复，`140-180ms`
- 主按钮视觉：紫蓝渐变 + 外发光（阴影 8-12）
- 次按钮视觉：浅玻璃底 + 1px 边线
- 触感：
  - 主 CTA：`UIImpactFeedbackGenerator(style: .medium)`
  - 次 CTA：`style: .light`

## 2.2 Input（邮箱/验证码）

- 高度：44
- 内边距：H14 / V12
- 圆角：16
- 状态边框：
  - 默认：白 16%
  - 聚焦：主色 65%
  - 错误：语义红 70%
- 键盘联动：底部按钮与键盘共同抬升，不遮挡。

## 2.3 Card（问卷选项/信息卡）

- 卡片圆角：16
- 内边距：12~16
- 卡组间距：8~12
- 选中态：
  - 白底保持
  - 1px 粉边
  - icon 着色提升
  - 文本权重小幅提升

## 2.4 Tab Bar（微交互）

- 底容器：玻璃胶囊
- 选中态：单个胶囊高亮，图标和文案提亮
- 动画：`spring(response: 0.26, dampingFraction: 0.78)`
- 触感：`UISelectionFeedbackGenerator`

## 2.5 Bottom Sheet（尺寸规范）

- 标准 detents：`280 / 420 / large`
- `280`：轻提醒卡、单 CTA
- `420`：双按钮或轻表单
- `large`：复杂解释/多段内容

## 2.6 图表（Outsiders 参考）

- 背景：深蓝黑 + 中央冷色光区
- 网格：低对比 4~5 条
- 主线：2~2.5px，末端圆点高亮
- 辅助线：选中点下拉虚线
- Y 轴：低亮度，减少噪声

---

## 3. 动效与触感参数表（本轮建议真值）

- 逐字问题（Lovi）
  - 字符间隔：`55ms`（可在 45~65ms 微调）
  - 触感：每 3 字一次 light impact
  - 选项出现：文本到 70% 后，选项延迟 100~150ms fade-in
- 卡片按压：`0.98`，`120~160ms`
- 页面转场（自定义段）：优先横向推入 + 轻透明过渡
- 图表选点：`easeInOut 200ms`

---

## 4. 帧级映射（从视频到组件）

来源：
- `/Users/mac/Desktop/antios10/.analysis/video8026_all/frames.csv`
- `/Users/mac/Desktop/antios10/.analysis/video8027_all/frames.csv`
- 摘要：`/Users/mac/Desktop/antios10/UI_FRAME_BIBLE_8026_8027.md`

高价值映射：
- Lovi `f_03558~f_03588` -> 逐字问题动效 + 选项延迟出现
- Lovi `f_03768~f_03776` -> 选项选中态（细粉描边）
- Lovi `f_04800~f_04809` -> 轻量 loading（白底+淡环）
- Outsiders `f_02027` -> 图表形态基线
- Outsiders `f_02091~f_02171` -> 右侧细节面板横向揭示

---

## 5. 本轮已落地代码（容器）

- 文件：`/Users/mac/Desktop/antios10/antios10/Features/Settings/SettingsView.swift`
- 入口：设置 -> 支持与信息 -> 设计系统容器
- 包含：
  - `LabStylePreset`（紫粉/绿色）
  - 四角色协同结论区
  - Button/Input/Card 规范样机
  - `LoviTypewriterQuestionLabView`
  - `OutsidersChartLabView`
  - `TabMicroInteractionLabView`
  - `DesignBottomSheetDemoView`

---

## 6. 本轮质量闸门

- 使用技能：`ios-i18n-sync-audit-workflow`
- 报告：
  - `check_report=/tmp/ios_i18n_check_20260214_074632.json`
  - `apply_report=/tmp/ios_i18n_apply_20260214_074632.json`
  - `strict_report=/tmp/ios_i18n_strict_20260214_074632.json`
- 严格结果：
  - `missing_in_en = 0`
  - `missing_in_zh_hans = 0`
  - `missing_in_zh_hant = 0`
  - `unresolved_en_values = 0`

---

## 7. 下一批迁移顺序（建议）

1. `Dashboard`：先换 Token 与卡片样式，不改业务逻辑。
2. `Report`：统一图表背景、指标卡、按钮状态。
3. `Onboarding`：接入逐字问题、主按钮光晕、sheet 尺寸规范。
4. `CoreHub/Max`：统一 tab/输入/卡片风格，消除硬编码色值。

---

## 8. 本轮新增（2026-02-14）

- 淡紫化：将主紫粉调到浅色系统友好的淡紫梯度，保留深色模式对比。
- 字体策略：新增 `GlassTypography.cnLovi`（`PingFangSC-*`）与 `loviTitle`（rounded sans）。
- 启动页：新增 Lovi 风格启动屏（流光背景 + 玻璃图标牌 + 进度胶囊）。

---

## 9. 全量改造进度（执行中）

- 已完成：
  - `ContentView` 启动页改造（Lovi 风格）
  - `AuthView`（品牌区/表单/按钮/字体）
  - `OnboardingView`（标题层级/交互卡片/字体与浅色背景）
  - `DashboardView`（语义 surface + 中文字体层级）
  - `ReportView`（语义 surface + 中文字体层级）
- 下一批：
  - `PlansView`
  - `MaxChatView`
  - `ProfileView`
