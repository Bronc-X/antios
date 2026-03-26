# antios10 新电脑配置 Xcode 26.3 精准备忘录

最后核对时间：2026-03-26  
本机已验证环境：`Xcode 26.3 (17C529)`

这份备忘录不是通用教程，而是按当前仓库真实工程信息整理的迁移说明。

## 1. 目标环境

当前项目实际要求：

- Xcode：`26.3`
- iOS Simulator Runtime：`iOS 26.3`
- Swift toolchain：随 Xcode 26.3
- 工程：`antios10.xcodeproj`
- 主 Scheme：`antios10`
- Widget Scheme：`antios10WidgetExtension`
- Deployment Target：`iOS 26.0`
- Development Team：`SNN7H3KC2R`

建议结论：

1. 新电脑优先直接装 `Xcode 26.3`
2. 不要先用更低版本 Xcode 打开工程
3. 先装好 iOS 26.3 runtime 再 build

## 2. 首次安装后必须执行

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
xcodebuild -version
swift --version
```

期望结果至少包含：

- `Xcode 26.3`
- `Build version 17C529`

如果命令行工具没装好：

```bash
xcode-select --install
```

## 3. Simulator 平台要装什么

打开 Xcode：

`Xcode > Settings > Platforms`

确认已经安装：

- `iOS 26.3`

当前这台机器可用设备包括：

- `iPhone 17 Pro`
- `iPhone 17 Pro Max`
- `iPhone Air`
- `iPhone 17`
- `iPhone 16e`

直接命令确认：

```bash
xcrun simctl list devices available
```

注意：
不要写死 `iPhone 16`。这台机器当前没有这个 simulator，之前那种命令会误导测试结论。

## 4. 拉代码后第一件事

这个工作区有强约束：

- 只能在 `main` 分支工作
- 不能切到 `old10`
- `antios10` 相关任务只能在这个工作区处理

先执行：

```bash
git branch --show-current
git status --short --branch
```

期望：

- 当前分支是 `main`

## 5. 项目关键工程参数

- 主 App Bundle ID：`com.youngtony.antios10`
- Widget Bundle ID：`com.youngtony.antios10.antios10Widget`
- 主 App entitlement：HealthKit + App Group
- 统一后的 App Group：`group.com.youngtony.antios10`

列工程信息：

```bash
xcodebuild -list -project antios10.xcodeproj
```

## 6. 配置文件与密钥

根目录关键配置文件：

- `Secrets.xcconfig`
- `Secrets.private.xcconfig`

项目真实启动依赖至少包括：

- `APP_API_BASE_URL`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `OPENAI_API_KEY`
- `OPENAI_API_BASE`
- `OPENAI_EMBEDDING_API_KEY`
- `OPENAI_EMBEDDING_API_BASE`

正确做法：

1. 保留仓库里的 `Secrets.xcconfig`
2. 在新电脑补齐 `Secrets.private.xcconfig`
3. 不把 `Secrets.private.xcconfig` 提交到 git

如果这些值缺失，通常会出现：

- App 可编译但登录失败
- Max 无法请求
- embedding 不工作
- App API 无法连通

## 7. Signing & Capabilities 要逐项核对

打开 target 的 `Signing & Capabilities`，检查：

### 主 App `antios10`

1. Team 选择 `SNN7H3KC2R` 对应账号
2. Bundle ID 是 `com.youngtony.antios10`
3. HealthKit 已启用
4. App Group 包含 `group.com.youngtony.antios10`

### Widget `antios10WidgetExtension`

1. Team 选择同一个账号
2. Bundle ID 是 `com.youngtony.antios10.antios10Widget`
3. App Group 包含 `group.com.youngtony.antios10`

### 为什么这里要严查

这个项目主 App 会把 Dashboard 数据写入共享容器，再触发 widget reload。  
如果 App Group 不一致，Widget 即使编过，也拿不到共享数据。

## 8. 推荐的首次打开顺序

1. 用 Xcode 打开 `antios10.xcodeproj`
2. 等索引完成
3. 选 `antios10` Scheme
4. 选择真实存在的 simulator，优先 `iPhone 17 Pro`
5. `Product > Clean Build Folder`
6. 先 `Build`
7. 再 `Run`
8. 最后单独验证 `antios10WidgetExtension`

## 9. 命令行标准验证

### 9.1 列工程

```bash
xcodebuild -list -project antios10.xcodeproj
```

### 9.2 查 simulator

```bash
xcrun simctl list devices available
```

### 9.3 先 build

```bash
xcodebuild build -project antios10.xcodeproj -scheme antios10 -destination 'platform=iOS Simulator,id=<DEVICE_ID>'
```

### 9.4 再 test

```bash
xcodebuild test -project antios10.xcodeproj -scheme antios10 -destination 'platform=iOS Simulator,id=<DEVICE_ID>'
```

### 9.5 如果只想先拉起 app

```bash
xcrun simctl boot <DEVICE_ID>
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/antios10-*/Build/Products/Debug-iphonesimulator/antios10.app
xcrun simctl launch booted com.youngtony.antios10
```

## 10. 我建议你在新电脑默认选这台模拟器

当前本机最稳妥基线设备：

- 设备名：`iPhone 17 Pro`
- 设备 ID：`16E0B2DC-2C4E-4F72-BDDE-36C9F834EBA9`

如果新电脑生成的是不同 ID，不要复用这里的 ID，只复用设备型号。

## 11. 常见故障排查

### 11.1 Build 失败

先清理 DerivedData：

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/antios10-*
```

然后重新：

```bash
xcodebuild -list -project antios10.xcodeproj
```

### 11.2 登录失败

优先排查：

1. `Secrets.private.xcconfig` 是否存在
2. `SUPABASE_URL` 是否正确
3. `SUPABASE_ANON_KEY` 是否正确
4. 系统时间是否正常
5. Keychain 是否被系统策略阻断

### 11.3 Max 不工作

优先排查：

1. `OPENAI_API_KEY`
2. `OPENAI_EMBEDDING_API_KEY`
3. `APP_API_BASE_URL`
4. simulator 网络连通性

### 11.4 Widget 不显示真实数据

优先排查：

1. 主 App 与 Widget 是否都签名成功
2. 两边 App Group 是否都是 `group.com.youngtony.antios10`
3. 先打开主 App 触发一次 Dashboard 同步
4. 再看 Widget 时间线是否刷新

### 11.5 HealthKit 权限不弹或不可用

优先排查：

1. 主 App target 的 HealthKit capability
2. entitlements 是否正确签入
3. 真机是否使用支持的 Apple ID / 权限环境

## 12. 新电脑迁移后的最小验收

1. `xcodebuild -version` 正确显示 `Xcode 26.3`
2. `xcodebuild -list -project antios10.xcodeproj` 成功
3. `antios10` scheme 能 build
4. App 能在 iOS 26.3 simulator 启动
5. 登录页与主流程能进入
6. Dashboard 能刷新
7. Max 能发起请求
8. Widget target 能编译
9. Widget 能显示共享数据而不是模板时间

## 13. 建议保留的固定命令

```bash
git branch --show-current
git status --short --branch
xcodebuild -version
xcodebuild -list -project antios10.xcodeproj
xcrun simctl list devices available
```
