import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const remotionRoot = path.resolve(scriptDir, "..");
const appRoot = path.resolve(remotionRoot, "../antios10");
const outputFile = path.join(remotionRoot, "src/generated/appSnapshot.ts");
const watchMode = process.argv.includes("--watch");

const sourceFiles = {
  theme: path.join(appRoot, "Shared/Theme/LiquidGlassTheme.swift"),
  onboarding: path.join(appRoot, "Features/Onboarding/OnboardingView.swift"),
  dashboard: path.join(appRoot, "Features/Dashboard/DashboardView.swift"),
  maxSurface: path.join(appRoot, "Features/Max/MaxChatAgentSurface.swift"),
  maxSupport: path.join(appRoot, "Features/Max/MaxChatSupportViews.swift"),
  shell: path.join(appRoot, "Models/A10ShellModels.swift"),
  breathing: path.join(appRoot, "Features/Breathing/BreathingSessionView.swift"),
  breathingAnimations: path.join(appRoot, "Shared/Animations/BreathingAnimations.swift"),
};

const read = (file) => fs.readFileSync(file, "utf8");

const extract = (content, regex, fallback) => content.match(regex)?.[1] ?? fallback;

const extractDarkHex = (content, token, fallback) =>
  extract(
    content,
    new RegExp(
      String.raw`static let ${token} = Color\(uiColor: UIColor \{ trait in[\s\S]*?trait\.userInterfaceStyle == \.dark \? UIColor\(hex: "([^"]+)"\)`,
    ),
    fallback,
  );

const syncSnapshot = () => {
  const theme = read(sourceFiles.theme);
  const onboarding = read(sourceFiles.onboarding);
  const dashboard = read(sourceFiles.dashboard);
  const maxSurface = read(sourceFiles.maxSurface);
  const maxSupport = read(sourceFiles.maxSupport);
  const shell = read(sourceFiles.shell);
  const breathing = read(sourceFiles.breathing);
  const breathingAnimations = read(sourceFiles.breathingAnimations);

  const summarySection = shell.split("func summary")[1] ?? shell;

  const stageFor = (key, fallbackTitle, fallbackSummary) => ({
    key,
    title: extract(
      shell,
      new RegExp(String.raw`case \.${key}:\s*return L10n\.text\("([^"]+)"`, "s"),
      fallbackTitle,
    ),
    summary: extract(
      summarySection,
      new RegExp(String.raw`case \.${key}:\s*return L10n\.text\("([^"]+)"`, "s"),
      fallbackSummary,
    ),
  });

  const thinkingTexts = Array.from(
    maxSupport.matchAll(/L10n\.text\("([^"]+)",\s*"[^"]+", language: language\)/g),
  )
    .map((match) => match[1])
    .slice(0, 5);

  const snapshot = {
    generatedAt: new Date().toISOString(),
    palette: {
      abyss: "#121111",
      base: "#171513",
      baseRaised: "#1E1A17",
      surfaceHex: extract(theme, /return Color\(hex: "([^"]+)"\)\.opacity\(0\.62\)/, "#202224"),
      accent: extractDarkHex(theme, "liquidGlassAccent", "#DCE5D9"),
      secondary: extractDarkHex(theme, "liquidGlassSecondary", "#A7B1A8"),
      warm: extractDarkHex(theme, "liquidGlassWarm", "#B59983"),
      fresh: extractDarkHex(theme, "liquidGlassFreshGreen", "#89A28B"),
      purple: extractDarkHex(theme, "liquidGlassPurple", "#B7B1C0"),
      textPrimary: extractDarkHex(theme, "textPrimary", "#F2F1EC"),
      textSecondary: extractDarkHex(theme, "textSecondary", "#C7CCC2"),
      textTertiary: extractDarkHex(theme, "textTertiary", "#9DA398"),
      userStart: "#2B323A",
      userEnd: "#1E222A",
    },
    onboarding: {
      title: extract(onboarding, /Text\("([^"]*AntiAnxiety[^"]*)"\)/, "欢迎来到 AntiAnxiety"),
      startButton: extract(onboarding, /Text\("([^"]+)"\)\s*\n\s*}\s*\n\s*\.buttonStyle/s, "开始设置"),
    },
    dashboard: {
      title: extract(dashboard, /Text\(t\("([^"]+)",\s*"Progress"\)\)/, "进展"),
      tagline: extract(
        dashboard,
        /Text\(t\("([^"]+)",\s*"Weak constraint rhythm · Personalized explanation · Action follow-up"\)\)/,
        "弱约束节奏 · 个性化解释 · 行动跟进",
      ),
      helpLabel: "帮助",
      heroTitle: extract(dashboard, /Text\(t\("([^"]+)",\s*"Today's control panel"\)\)/, "今日主控"),
      heroHeadline: "先从一个最低阻力动作开始",
      heroSupport: "允许中断，再继续也算完成",
      insightLabel: extract(dashboard, /Text\(t\("([^"]+)",\s*"Insights"\)\)/, "今日洞察"),
      metricLabels: {
        streak: extract(dashboard, /title: t\("([^"]+)",\s*"Current streak"\)/, "连续记录"),
        completion: extract(dashboard, /title: t\("([^"]+)",\s*"Loop completion"\)/, "闭环完成"),
        priority: extract(dashboard, /title: t\("([^"]+)",\s*"Current priority"\)/, "当前优先级"),
      },
      badges: [
        extract(dashboard, /title: t\("([^"]+)",\s*"Minimum action first"\)/, "最小动作优先"),
        extract(dashboard, /title: t\("([^"]+)",\s*"Pause and resume"\)/, "允许中断再继续"),
      ],
      nextStepLabel: extract(dashboard, /Text\(t\("([^"]+)",\s*"Next step"\)\)/, "下一步动作"),
      sectionTitles: {
        maxFocus: extract(dashboard, /sectionHeader\(title: t\("([^"]+)",\s*"Max focus"\)/, "Max 关注点"),
        calibration: extract(
          dashboard,
          /Text\(t\("([^"]+)",\s*"Calibrate today \(optional\)"\)\)/,
          "今日校准（可选）",
        ),
        science: extract(
          dashboard,
          /sectionHeader\(title: t\("([^"]+)",\s*"Scientific explanation"\)/,
          "科学解释",
        ),
        action: extract(
          dashboard,
          /sectionHeader\(title: t\("([^"]+)",\s*"Action suggestions"\)/,
          "行动建议",
        ),
      },
      maxQuestion: stageFor(
        "inquiry",
        "问询",
        "用一句话说出今天最明显的触发点。",
      ).summary,
      evidenceLabel: extract(dashboard, /Text\(t\("([^"]+)",\s*"Related evidence"\)\)/, "相关证据"),
      evidenceSource: "个性化科学证据库",
      calibrationBody: extract(
        dashboard,
        /\? t\("([^"]+)",\s*"If you like, record today's status, recommendations will be more relevant\."\)/,
        "如果愿意，记录今天状态，建议会更贴合你。",
      ),
      science: {
        conclusionTitle: extract(dashboard, /title: t\("([^"]+)",\s*"Conclusion"\)/, "理解结论"),
        mechanismTitle: extract(
          dashboard,
          /title: t\("([^"]+)",\s*"Mechanistic explanation"\)/,
          "机制解释",
        ),
        evidenceTitle: extract(
          dashboard,
          /title: t\("([^"]+)",\s*"Source of evidence"\)/,
          "证据来源",
        ),
        actionTitle: extract(dashboard, /title: t\("([^"]+)",\s*"Action"\)/, "可执行动作"),
        followupTitle: extract(
          dashboard,
          /title: t\("([^"]+)",\s*"Follow-up question"\)/,
          "跟进问题",
        ),
      },
      scienceJournalLabel: extract(
        dashboard,
        /Text\(t\("([^"]+)",\s*"Open personalized science journal"\)\)/,
        "进入个性化科学期刊",
      ),
      followUpButton: extract(
        dashboard,
        /Text\(t\("([^"]+)",\s*"Let Max follow up"\)\)/,
        "让 Max 继续跟进",
      ),
    },
    max: {
      title: "Max",
      continueTitle: extract(
        maxSurface,
        /Text\(L10n\.text\("([^"]+)",\s*"Continue the Home loop"/,
        "从首页闭环继续",
      ),
      continueDetail: extract(
        maxSurface,
        /Text\(L10n\.text\("([^"]+)",\s*"Max will take the next step so you do not have to choose a module\."/,
        "Max 会接手下一步，不需要你自己判断模块。",
      ),
      executionTitle: extract(
        maxSurface,
        /Text\(L10n\.text\("([^"]+)",\s*"Chat and execution center"/,
        "对话与执行中心",
      ),
      executionDetail: "当前问询、计划推进和证据状态都会保留，返回后继续。",
      sessionKept: extract(
        maxSurface,
        /Text\(L10n\.text\("([^"]+)",\s*"Session kept"/,
        "会话保留",
      ),
      overviewTitles: {
        inquiry: extract(
          maxSurface,
          /title: L10n\.text\("([^"]+)",\s*"Pending inquiry"/,
          "待处理问询",
        ),
        plan: extract(maxSurface, /title: L10n\.text\("([^"]+)",\s*"Plan progress"/, "计划推进"),
        evidence: extract(
          maxSurface,
          /title: L10n\.text\("([^"]+)",\s*"Evidence status"/,
          "证据状态",
        ),
      },
      thinkingTexts:
        thinkingTexts.length > 0
          ? thinkingTexts
          : [
              "正在理解你的焦虑场景...",
              "校准触发因素与身体信号...",
              "检索科学证据...",
              "生成机制解释与行动方案...",
              "准备下一轮跟进问题...",
            ],
    },
    breathing: {
      title: extract(breathing, /Text\("([^"]+)"\)\s*\n\s*\.font\(.title2\.bold\(\)\)/, "呼吸练习"),
      subtitle: extract(
        breathing,
        /Text\("([^"]+)"\)\s*\n\s*\.font\(.subheadline\)/,
        "跟随节奏，缓慢吸气与呼气",
      ),
      phases: [
        extract(breathingAnimations, /case \.inhale: return "([^"]+)"/, "吸气"),
        extract(breathingAnimations, /case \.hold: return "([^"]+)"/, "屏息"),
        extract(breathingAnimations, /case \.exhale: return "([^"]+)"/, "呼气"),
      ],
      endButton: extract(breathing, /Button\("([^"]+)"\)/, "结束练习"),
    },
    loopStages: [
      stageFor("inquiry", "问询", "用一句话说出今天最明显的触发点。"),
      stageFor("calibration", "校准", "补齐今日主观状态与身体信号。"),
      stageFor("evidence", "解释", "把建议和证据链解释清楚。"),
      stageFor("action", "行动", "执行一个最低阻力动作。"),
    ],
  };

  const nextContent =
    `// Auto-generated by scripts/sync-app-snapshot.mjs\n` +
    `export const appSnapshot = ${JSON.stringify(snapshot, null, 2)} as const;\n`;

  fs.mkdirSync(path.dirname(outputFile), { recursive: true });
  const previousContent = fs.existsSync(outputFile) ? read(outputFile) : "";

  if (previousContent !== nextContent) {
    fs.writeFileSync(outputFile, nextContent);
    console.log(`[sync] wrote ${path.relative(remotionRoot, outputFile)}`);
  } else {
    console.log("[sync] snapshot unchanged");
  }
};

syncSnapshot();

if (watchMode) {
  console.log("[sync] watching app source files for changes");
  let timer = null;
  const rerun = () => {
    if (timer) {
      clearTimeout(timer);
    }
    timer = setTimeout(() => {
      try {
        syncSnapshot();
      } catch (error) {
        console.error("[sync] failed:", error);
      }
    }, 100);
  };

  Object.values(sourceFiles).forEach((file) => {
    fs.watch(file, rerun);
  });
}
