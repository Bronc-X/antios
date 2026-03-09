# D_RELEASE_AND_HANDOFF

> AntiAnxiety iOS 发布门禁与交接（合并版）
> 版本: v3.1.0
> 更新: 2026-03-07

---

## 1. RELEASE_CHECKLIST（发布清单）

### 1.1 功能
- [x] 核心路径已具备实现
- [x] 空状态可见
- [x] 错误状态可见
- [x] 加载状态可见

### 1.2 质量
- [x] 模拟器 Debug 编译通过
- [ ] 测试通过（当前需复核 `xcodebuild test` 收尾稳定性）
- [ ] 无 P0/P1 阻断问题（当前存在）
- [ ] `codex/antios10` 重构壳层已完成全量范围对齐

### 1.3 兼容
- [ ] 真机回归完成
- [ ] 双环境验证完成（真机 + 模拟器/备用机）

### 1.4 安全
- [x] 仓库内密钥模板化完成
- [x] 输入校验具备基础覆盖

### 1.5 部署
- [ ] 生产环境变量注入完成
- [ ] 生产日志与监控确认
- [ ] 回滚方案演练

---

## 2. GO/NO-GO 规则

任一条不满足即 NO-GO：
1. 真实密钥仍在仓库
2. App 或 Widget release 签名 profile 缺失
3. 核心路径无法端到端跑通
4. P0/P1 未关闭
5. 主线文档与实际工程状态不一致

---

## 3. 交接清单

发布前必须交付：
- 四文件治理包（A/B/C/D）
- 审核附录（`GOVERNANCE_AUDIT_APPENDIX.md`）
- 构建与测试日志路径
- 当前风险与 owner

---

## 4. 当前阻断与责任归属

- 阻断 A（P1）: Release 签名 profile
  - 处理人: iOS 发布负责人
  - 动作: 补齐 `com.youngtony.antios10` 与 widget profile，用于 archive / TestFlight

- 阻断 B（P1）: 测试环境
  - 处理人: 开发环境 owner
  - 动作: 复核 UI 自动化会话稳定性并重跑 test gate
