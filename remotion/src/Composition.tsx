import { type CSSProperties, type FC, type ReactNode } from "react";
import {
  AbsoluteFill,
  Easing,
  Sequence,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { appSnapshot } from "./generated/appSnapshot";

const fontStack =
  '"SF Pro Display","SF Pro Text","PingFang SC","Helvetica Neue",Helvetica,Arial,sans-serif';

const scenes = {
  onboarding: 150,
  dashboard: 225,
  max: 210,
  action: 135,
};

const stylizedScenes = {
  onboarding: 120,
  max: 150,
  dashboard: 180,
};

type CameraStop = {
  frame: number;
  scale: number;
  x: number;
  y: number;
};

type ValueStop = {
  frame: number;
  value: number;
};

type StageKey = "inquiry" | "calibration" | "evidence" | "action";

const palette = appSnapshot.palette;
const onboardingTexts = appSnapshot.onboarding;
const dashboardTexts = appSnapshot.dashboard;
const maxTexts = appSnapshot.max;
const breathingTexts = appSnapshot.breathing;
const taglinePills = dashboardTexts.tagline.split("·").map((value) => value.trim()).filter(Boolean);
const loopStageByKey = appSnapshot.loopStages.reduce(
  (accumulator, stage) => {
    accumulator[stage.key as StageKey] = stage;
    return accumulator;
  },
  {} as Record<StageKey, (typeof appSnapshot.loopStages)[number]>,
);

const stageTitle = (key: StageKey) => loopStageByKey[key]?.title ?? key;
const stageSummary = (key: StageKey) => loopStageByKey[key]?.summary ?? "";

const clamp = (value: number, min = 0, max = 1) =>
  Math.min(max, Math.max(min, value));

const hexToRgb = (hex: string) => {
  const normalized = hex.replace("#", "");
  const full =
    normalized.length === 3
      ? normalized
          .split("")
          .map((value) => `${value}${value}`)
          .join("")
      : normalized;
  const parsed = Number.parseInt(full, 16);
  return {
    r: (parsed >> 16) & 255,
    g: (parsed >> 8) & 255,
    b: parsed & 255,
  };
};

const withAlpha = (hex: string, alpha: number) => {
  const { r, g, b } = hexToRgb(hex);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
};

const fadeInOut = (frame: number, duration: number) =>
  interpolate(frame, [0, 16, duration - 22, duration], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

const riseIn = (frame: number, fps: number, delay: number) =>
  spring({
    fps,
    frame: frame - delay,
    config: {
      damping: 18,
      stiffness: 120,
      mass: 0.82,
    },
  });

const trackValue = (frame: number, stops: ValueStop[]) => {
  if (stops.length === 0) {
    return 0;
  }

  if (frame <= stops[0].frame) {
    return stops[0].value;
  }

  for (let index = 0; index < stops.length - 1; index += 1) {
    const start = stops[index];
    const end = stops[index + 1];

    if (frame <= end.frame) {
      return interpolate(frame, [start.frame, end.frame], [start.value, end.value], {
        easing: Easing.bezier(0.22, 1, 0.36, 1),
        extrapolateLeft: "clamp",
        extrapolateRight: "clamp",
      });
    }
  }

  return stops[stops.length - 1].value;
};

const resolveCamera = (frame: number, stops: CameraStop[]): CameraStop => ({
  frame,
  scale: trackValue(
    frame,
    stops.map((stop) => ({ frame: stop.frame, value: stop.scale })),
  ),
  x: trackValue(
    frame,
    stops.map((stop) => ({ frame: stop.frame, value: stop.x })),
  ),
  y: trackValue(
    frame,
    stops.map((stop) => ({ frame: stop.frame, value: stop.y })),
  ),
});

const screenShellStyle: CSSProperties = {
  position: "absolute",
  inset: 52,
  borderRadius: 74,
  overflow: "hidden",
  background: `linear-gradient(180deg, ${palette.baseRaised}, ${palette.abyss} 64%, ${palette.abyss})`,
  border: `1px solid ${withAlpha("#FFFFFF", 0.1)}`,
  boxShadow:
    "0 42px 160px rgba(0,0,0,0.54), inset 0 1px 0 rgba(255,255,255,0.05)",
};

const titleStyle: CSSProperties = {
  color: palette.textPrimary,
  fontFamily: fontStack,
  fontWeight: 700,
  letterSpacing: -1.8,
};

const bodyStyle: CSSProperties = {
  color: palette.textSecondary,
  fontFamily: fontStack,
};

const glassCardStyle = (
  radius = 26,
  padding = 18,
  style?: CSSProperties,
): CSSProperties => ({
  position: "relative",
  padding,
  borderRadius: radius,
  overflow: "hidden",
  background: `linear-gradient(180deg, ${withAlpha(
    "#FFFFFF",
    0.09,
  )}, ${withAlpha("#FFFFFF", 0.025)}), ${withAlpha(palette.surfaceHex, 0.82)}`,
  border: `1px solid ${withAlpha("#FFFFFF", 0.12)}`,
  boxShadow:
    "0 18px 52px rgba(0,0,0,0.28), inset 0 1px 0 rgba(255,255,255,0.06)",
  backdropFilter: "blur(30px) saturate(135%)",
  ...style,
});

const GlassCard: FC<{
  children: ReactNode;
  radius?: number;
  padding?: number;
  style?: CSSProperties;
}> = ({ children, radius = 26, padding = 18, style }) => {
  return (
    <div style={glassCardStyle(radius, padding, style)}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "linear-gradient(180deg, rgba(255,255,255,0.06), rgba(255,255,255,0) 42%)",
          pointerEvents: "none",
        }}
      />
      <div style={{ position: "relative", zIndex: 1 }}>{children}</div>
    </div>
  );
};

const GlassPill: FC<{
  label: string;
  tint?: string;
  style?: CSSProperties;
}> = ({ label, tint = palette.accent, style }) => {
  return (
    <div
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 8,
        borderRadius: 999,
        padding: "10px 16px",
        background: withAlpha(tint, 0.12),
        border: `1px solid ${withAlpha("#FFFFFF", 0.08)}`,
        color: tint,
        fontFamily: fontStack,
        fontSize: 22,
        fontWeight: 600,
        ...style,
      }}
    >
      <div
        style={{
          width: 10,
          height: 10,
          borderRadius: "50%",
          background: tint,
          boxShadow: `0 0 18px ${withAlpha(tint, 0.42)}`,
        }}
      />
      {label}
    </div>
  );
};

const PrimaryButton: FC<{
  label: string;
  style?: CSSProperties;
}> = ({ label, style }) => {
  return (
    <div
      style={{
        borderRadius: 24,
        padding: "18px 24px",
        background: `linear-gradient(135deg, ${palette.userStart}, ${palette.userEnd})`,
        border: `1px solid ${withAlpha("#FFFFFF", 0.08)}`,
        boxShadow: "0 18px 40px rgba(0,0,0,0.26)",
        color: palette.textPrimary,
        fontFamily: fontStack,
        fontSize: 34,
        fontWeight: 600,
        textAlign: "center",
        ...style,
      }}
    >
      {label}
    </div>
  );
};

const SectionHeader: FC<{
  badge: string;
  title: string;
}> = ({ badge, title }) => {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: 12,
      }}
    >
      <div
        style={{
          width: 38,
          height: 38,
          borderRadius: 14,
          background: withAlpha(palette.surfaceHex, 0.74),
          border: `1px solid ${withAlpha("#FFFFFF", 0.08)}`,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          color: palette.accent,
          fontFamily: fontStack,
          fontWeight: 700,
          fontSize: 20,
        }}
      >
        {badge}
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
        <div
          style={{
            color: palette.textTertiary,
            fontFamily: fontStack,
            fontSize: 18,
            fontWeight: 600,
          }}
        >
          模块
        </div>
        <div
          style={{
            color: palette.textPrimary,
            fontFamily: fontStack,
            fontSize: 28,
            fontWeight: 650,
          }}
        >
          {title}
        </div>
      </div>
    </div>
  );
};

const MetricRow: FC<{
  title: string;
  value: string;
  tint: string;
}> = ({ title, value, tint }) => {
  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        gap: 2,
        borderRadius: 18,
        padding: "12px 14px",
        background: withAlpha("#FFFFFF", 0.04),
        border: `1px solid ${withAlpha("#FFFFFF", 0.06)}`,
      }}
    >
      <div
        style={{
          color: tint,
          fontFamily: fontStack,
          fontSize: 18,
          fontWeight: 600,
        }}
      >
        {title}
      </div>
      <div
        style={{
          color: palette.textPrimary,
          fontFamily: fontStack,
          fontSize: 24,
          fontWeight: 600,
        }}
      >
        {value}
      </div>
    </div>
  );
};

const ExplanationRow: FC<{
  title: string;
  value: string;
}> = ({ title, value }) => {
  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        gap: 6,
        padding: "12px 14px",
        borderRadius: 16,
        background: withAlpha("#FFFFFF", 0.045),
        border: `1px solid ${withAlpha("#FFFFFF", 0.06)}`,
      }}
    >
      <div
        style={{
          color: palette.textTertiary,
          fontFamily: fontStack,
          fontSize: 18,
          fontWeight: 600,
        }}
      >
        {title}
      </div>
      <div
        style={{
          color: palette.textPrimary,
          fontFamily: fontStack,
          fontSize: 22,
          lineHeight: 1.38,
        }}
      >
        {value}
      </div>
    </div>
  );
};

const ActionBullet: FC<{
  title: string;
  detail?: string;
}> = ({ title, detail }) => {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "flex-start",
        gap: 10,
      }}
    >
      <div
        style={{
          width: 18,
          height: 18,
          marginTop: 6,
          borderRadius: "50%",
          background: withAlpha(palette.accent, 0.18),
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <div
          style={{
            width: 8,
            height: 8,
            borderRadius: "50%",
            background: palette.accent,
          }}
        />
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
        <div
          style={{
            color: palette.textPrimary,
            fontFamily: fontStack,
            fontSize: 22,
            fontWeight: 600,
          }}
        >
          {title}
        </div>
        {detail ? (
          <div
            style={{
              color: palette.textSecondary,
              fontFamily: fontStack,
              fontSize: 18,
              lineHeight: 1.35,
            }}
          >
            {detail}
          </div>
        ) : null}
      </div>
    </div>
  );
};

const ScoreRing: FC<{
  score: number;
  size?: number;
  stroke?: number;
}> = ({ score, size = 220, stroke = 14 }) => {
  const normalized = clamp(score / 100);
  const radius = (size - stroke) / 2;
  const circumference = 2 * Math.PI * radius;
  const arcLength = circumference * 0.7;
  const dashOffset = arcLength * (1 - normalized);

  return (
    <div
      style={{
        position: "relative",
        width: size,
        height: size,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <svg width={size} height={size}>
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke={withAlpha(palette.textSecondary, 0.12)}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={`${arcLength} ${circumference}`}
          transform={`rotate(90 ${size / 2} ${size / 2})`}
        />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke={palette.accent}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={`${arcLength} ${circumference}`}
          strokeDashoffset={dashOffset}
          transform={`rotate(90 ${size / 2} ${size / 2})`}
          style={{
            filter: `drop-shadow(0 0 12px ${withAlpha(palette.fresh, 0.3)})`,
          }}
        />
      </svg>
      <div
        style={{
          position: "absolute",
          inset: 46,
          borderRadius: "50%",
          background: `radial-gradient(circle at 30% 30%, ${withAlpha(
            "#FFFFFF",
            0.14,
          )}, ${withAlpha(palette.accent, 0.1)} 34%, transparent 76%)`,
          border: `1px solid ${withAlpha("#FFFFFF", 0.08)}`,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          boxShadow: `inset 0 1px 0 ${withAlpha("#FFFFFF", 0.05)}`,
        }}
      >
        <div
          style={{
            color: palette.textPrimary,
            fontFamily: fontStack,
            fontSize: 54,
            fontWeight: 700,
            letterSpacing: -1,
          }}
        >
          {score}
        </div>
        <div
          style={{
            color: palette.textTertiary,
            fontFamily: fontStack,
            fontSize: 18,
            fontWeight: 600,
          }}
        >
          稳定度 /100
        </div>
      </div>
    </div>
  );
};

const StagePill: FC<{
  title: string;
  active: boolean;
}> = ({ title, active }) => {
  return (
    <div
      style={{
        flex: 1,
        minWidth: 0,
        borderRadius: 16,
        padding: "12px 14px",
        textAlign: "center",
        background: active
          ? withAlpha(palette.accent, 0.16)
          : withAlpha("#FFFFFF", 0.045),
        border: `1px solid ${
          active ? withAlpha(palette.accent, 0.24) : withAlpha("#FFFFFF", 0.06)
        }`,
        color: active ? palette.textPrimary : palette.textSecondary,
        fontFamily: fontStack,
        fontSize: 20,
        fontWeight: active ? 650 : 550,
        boxShadow: active
          ? `0 8px 20px ${withAlpha(palette.accent, 0.08)}`
          : "none",
      }}
    >
      {title}
    </div>
  );
};

const OptionButton: FC<{
  label: string;
}> = ({ label }) => {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        gap: 12,
        padding: "14px 16px",
        borderRadius: 16,
        background: withAlpha("#FFFFFF", 0.045),
        border: `1px solid ${withAlpha("#FFFFFF", 0.06)}`,
      }}
    >
      <div
        style={{
          color: palette.textPrimary,
          fontFamily: fontStack,
          fontSize: 22,
          lineHeight: 1.35,
        }}
      >
        {label}
      </div>
      <div
        style={{
          color: palette.textTertiary,
          fontFamily: fontStack,
          fontSize: 20,
          fontWeight: 700,
        }}
      >
        →
      </div>
    </div>
  );
};

const ChatBubble: FC<{
  role: "assistant" | "user";
  text: string;
  time: string;
}> = ({ role, text, time }) => {
  const isUser = role === "user";
  return (
    <div
      style={{
        display: "flex",
        justifyContent: isUser ? "flex-end" : "flex-start",
      }}
    >
      <div
        style={{
          display: "flex",
          flexDirection: isUser ? "row-reverse" : "row",
          alignItems: "flex-start",
          gap: 10,
          maxWidth: "100%",
        }}
      >
        <div
          style={{
            width: isUser ? 34 : 30,
            height: isUser ? 34 : 30,
            borderRadius: "50%",
            background: isUser
              ? withAlpha(palette.secondary, 0.18)
              : withAlpha(palette.surfaceHex, 0.9),
            border: `1px solid ${withAlpha("#FFFFFF", 0.08)}`,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            color: isUser ? palette.secondary : palette.accent,
            fontFamily: fontStack,
            fontSize: 18,
            fontWeight: 700,
          }}
        >
          {isUser ? "人" : "✦"}
        </div>
        <div
          style={{
            maxWidth: isUser ? 410 : 470,
            display: "flex",
            flexDirection: "column",
            alignItems: isUser ? "flex-end" : "flex-start",
            gap: 6,
          }}
        >
          <div
            style={{
              borderRadius: 18,
              padding: "14px 16px",
              background: isUser
                ? `linear-gradient(135deg, ${palette.userStart}, ${palette.userEnd})`
                : withAlpha(palette.surfaceHex, 0.9),
              border: `1px solid ${withAlpha("#FFFFFF", isUser ? 0.08 : 0.06)}`,
              color: isUser ? palette.textPrimary : palette.textPrimary,
              fontFamily: fontStack,
              fontSize: 21,
              lineHeight: 1.42,
              boxShadow: "0 12px 28px rgba(0,0,0,0.18)",
            }}
          >
            {text}
          </div>
          <div
            style={{
              color: palette.textTertiary,
              fontFamily: fontStack,
              fontSize: 16,
            }}
          >
            {time}
          </div>
        </div>
      </div>
    </div>
  );
};

const TypingIndicatorCard: FC<{
  frame: number;
  text: string;
}> = ({ frame, text }) => {
  const { fps } = useVideoConfig();
  const pulse = 1 + Math.sin((frame / fps) * Math.PI * 1.2) * 0.08;

  return (
    <div
      style={{
        display: "flex",
        alignItems: "flex-start",
        gap: 10,
      }}
    >
      <div
        style={{
          width: 36,
          height: 36,
          borderRadius: "50%",
          background: withAlpha(palette.accent, 0.14),
          border: `1px solid ${withAlpha(palette.accent, 0.22)}`,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          color: palette.accent,
          transform: `scale(${pulse})`,
          boxShadow: `0 0 18px ${withAlpha(palette.accent, 0.12)}`,
        }}
      >
        ✦
      </div>
      <GlassCard
        padding={16}
        radius={18}
        style={{
          width: 470,
          background: `linear-gradient(180deg, ${withAlpha(
            "#FFFFFF",
            0.08,
          )}, ${withAlpha("#FFFFFF", 0.02)}), ${withAlpha(palette.surfaceHex, 0.9)}`,
        }}
      >
        <div
          style={{
            color: palette.textPrimary,
            fontFamily: fontStack,
            fontSize: 20,
            marginBottom: 10,
          }}
        >
          {text}
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          {Array.from({ length: 3 }).map((_, index) => {
            const offset = Math.sin(frame / 5 + index * 0.9) * 5;
            return (
              <div
                key={index}
                style={{
                  width: 10,
                  height: 10,
                  borderRadius: "50%",
                  background: palette.accent,
                  transform: `translateY(${offset}px)`,
                  opacity: 0.6 + index * 0.08,
                }}
              />
            );
          })}
        </div>
      </GlassCard>
    </div>
  );
};

const TapCue: FC<{
  frame: number;
  start: number;
  x: number;
  y: number;
  label?: string;
  tint?: string;
}> = ({ frame, start, x, y, label, tint = palette.accent }) => {
  const { fps } = useVideoConfig();
  const pop = spring({
    fps,
    frame: frame - start,
    config: {
      damping: 16,
      stiffness: 170,
      mass: 0.7,
    },
  });
  const opacity = interpolate(frame, [start, start + 8, start + 40, start + 62], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  if (opacity <= 0.001) {
    return null;
  }

  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        transform: "translate(-50%, -50%)",
        opacity,
        zIndex: 50,
        pointerEvents: "none",
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: -58,
          borderRadius: "50%",
          border: `1px solid ${withAlpha(tint, 0.24)}`,
          transform: `scale(${1 + pop * 1.2})`,
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: -34,
          borderRadius: "50%",
          border: `1px solid ${withAlpha(tint, 0.42)}`,
          transform: `scale(${0.95 + pop * 0.62})`,
        }}
      />
      <div
        style={{
          width: 28,
          height: 28,
          borderRadius: "50%",
          background: tint,
          boxShadow: `0 0 32px ${withAlpha(tint, 0.44)}`,
        }}
      />
      {label ? (
        <div
          style={{
            position: "absolute",
            top: 46,
            left: "50%",
            transform: "translateX(-50%)",
            whiteSpace: "nowrap",
            padding: "10px 14px",
            borderRadius: 999,
            background: withAlpha(palette.surfaceHex, 0.92),
            border: `1px solid ${withAlpha("#FFFFFF", 0.08)}`,
            color: palette.textPrimary,
            fontFamily: fontStack,
            fontSize: 20,
            fontWeight: 600,
          }}
        >
          {label}
        </div>
      ) : null}
    </div>
  );
};

const PhoneScene: FC<{
  opacity: number;
  camera: CameraStop;
  children: ReactNode;
  overlays?: ReactNode;
}> = ({ opacity, camera, children, overlays }) => {
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        opacity,
      }}
    >
      <div
        style={{
          position: "relative",
          width: 920,
          height: 1840,
          borderRadius: 92,
          background: `linear-gradient(180deg, ${withAlpha(
            "#FFFFFF",
            0.14,
          )}, ${withAlpha("#FFFFFF", 0.03)})`,
          border: `1px solid ${withAlpha("#FFFFFF", 0.12)}`,
          boxShadow:
            "0 56px 190px rgba(0,0,0,0.48), inset 0 1px 0 rgba(255,255,255,0.12)",
        }}
      >
        <div style={screenShellStyle}>
          <StatusBar />
          <div
            style={{
              position: "absolute",
              inset: 0,
              transform: `translate3d(${camera.x}px, ${camera.y}px, 0) scale(${camera.scale})`,
              transformOrigin: "50% 50%",
            }}
          >
            {children}
          </div>
          {overlays}
          <div
            style={{
              position: "absolute",
              inset: 0,
              borderRadius: 74,
              boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.03)",
              pointerEvents: "none",
            }}
          />
        </div>
      </div>
    </div>
  );
};

const StatusBar: FC = () => {
  return (
    <div
      style={{
        position: "absolute",
        top: 18,
        left: 30,
        right: 30,
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        zIndex: 40,
      }}
    >
      <div
        style={{
          color: palette.textPrimary,
          fontFamily: fontStack,
          fontSize: 22,
          fontWeight: 650,
        }}
      >
        9:41
      </div>
      <div
        style={{
          position: "absolute",
          left: "50%",
          transform: "translateX(-50%)",
          width: 146,
          height: 36,
          borderRadius: 999,
          background: withAlpha("#000000", 0.44),
          border: `1px solid ${withAlpha("#FFFFFF", 0.04)}`,
        }}
      />
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <div
          style={{
            width: 32,
            height: 12,
            borderRadius: 999,
            background: withAlpha(palette.textPrimary, 0.86),
          }}
        />
        <div
          style={{
            width: 16,
            height: 16,
            borderRadius: "50%",
            border: `2px solid ${withAlpha(palette.textPrimary, 0.86)}`,
          }}
        />
      </div>
    </div>
  );
};

const AmbientBackdrop: FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const beat = frame / fps;

  return (
    <AbsoluteFill
      style={{
        background: `linear-gradient(180deg, ${palette.base} 0%, ${palette.baseRaised} 42%, ${palette.abyss} 100%)`,
        fontFamily: fontStack,
        overflow: "hidden",
      }}
    >
      <AbsoluteFill
        style={{
          background: `radial-gradient(circle at 20% 18%, ${withAlpha(
            palette.accent,
            0.07,
          )}, transparent 28%), radial-gradient(circle at 80% 30%, ${withAlpha(
            palette.warm,
            0.08,
          )}, transparent 26%), radial-gradient(circle at 50% 84%, ${withAlpha(
            palette.fresh,
            0.09,
          )}, transparent 30%)`,
        }}
      />
      <BackgroundGlow
        size={760}
        color={withAlpha(palette.accent, 0.12)}
        left={-180 + Math.sin(beat * 0.9) * 36}
        top={-120}
      />
      <BackgroundGlow
        size={640}
        color={withAlpha(palette.warm, 0.12)}
        right={-160}
        top={260 + Math.sin(beat * 1.2) * 24}
      />
      <BackgroundGlow
        size={580}
        color={withAlpha(palette.fresh, 0.1)}
        left={80 + Math.cos(beat * 1.1) * 18}
        bottom={130}
      />
      <BackgroundGlow
        size={520}
        color={withAlpha(palette.purple, 0.08)}
        right={60 + Math.cos(beat * 0.8) * 18}
        bottom={240}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          backgroundImage:
            "linear-gradient(rgba(255,255,255,0.025) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.025) 1px, transparent 1px)",
          backgroundSize: "130px 130px",
          opacity: 0.16,
          maskImage:
            "linear-gradient(180deg, transparent, rgba(0,0,0,0.75) 20%, rgba(0,0,0,0.75) 82%, transparent)",
        }}
      />
    </AbsoluteFill>
  );
};

const BackgroundGlow: FC<{
  size: number;
  color: string;
  top?: number;
  right?: number;
  bottom?: number;
  left?: number;
}> = ({ size, color, ...rest }) => {
  return (
    <div
      style={{
        position: "absolute",
        width: size,
        height: size,
        borderRadius: "50%",
        background: color,
        filter: "blur(70px)",
        ...rest,
      }}
    />
  );
};

const OnboardingScene: FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const opacity = fadeInOut(frame, scenes.onboarding);
  const intro = riseIn(frame, fps, 0);
  const orbPulse = 1 + Math.sin((frame / fps) * Math.PI * 1.05) * 0.04;
  const camera = resolveCamera(frame, [
    { frame: 0, scale: 1, x: 0, y: 0 },
    { frame: 54, scale: 1.08, x: 0, y: -28 },
    { frame: 110, scale: 1.19, x: 0, y: -210 },
    { frame: scenes.onboarding, scale: 1.19, x: 0, y: -210 },
  ]);

  return (
    <PhoneScene
      opacity={opacity}
      camera={camera}
      overlays={<TapCue frame={frame} start={106} x={408} y={1542} label="开始设置" />}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          padding: "100px 46px 42px",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          textAlign: "center",
        }}
      >
        <div style={{ display: "flex", gap: 12, marginBottom: 34 }}>
          {Array.from({ length: 5 }).map((_, index) => {
            const progress = riseIn(frame, fps, index * 5);
            const active = index === 0;
            return (
              <div
                key={index}
                style={{
                  width: active ? 96 : 54,
                  height: active ? 12 : 10,
                  borderRadius: 999,
                  background: active
                    ? `linear-gradient(90deg, ${palette.accent}, ${palette.secondary})`
                    : withAlpha("#FFFFFF", 0.14),
                  opacity: 0.35 + progress * 0.65,
                  transform: `scaleX(${0.92 + progress * 0.08})`,
                }}
              />
            );
          })}
        </div>

        <div
          style={{
            position: "relative",
            width: 500,
            height: 500,
            marginTop: 10,
            marginBottom: 46,
            transform: `scale(${0.95 + intro * 0.05})`,
          }}
        >
          {[460, 378, 296].map((size, index) => {
            const rotation = frame * (index % 2 === 0 ? 0.55 : -0.7);
            const tint = [palette.accent, palette.warm, palette.fresh][index];
            return (
              <div
                key={size}
                style={{
                  position: "absolute",
                  inset: (500 - size) / 2,
                  borderRadius: "50%",
                  border: `1px solid ${withAlpha(tint, 0.24)}`,
                  transform: `rotate(${rotation}deg) scale(${orbPulse})`,
                }}
              >
                <div
                  style={{
                    position: "absolute",
                    width: 18,
                    height: 18,
                    borderRadius: "50%",
                    background: withAlpha("#FFFFFF", 0.82),
                    top: -8,
                    left: "50%",
                    marginLeft: -9,
                    boxShadow: `0 0 24px ${withAlpha(tint, 0.26)}`,
                  }}
                />
              </div>
            );
          })}

          <div
            style={{
              position: "absolute",
              inset: 106,
              borderRadius: "50%",
              background: `radial-gradient(circle at 30% 30%, ${withAlpha(
                "#FFFFFF",
                0.18,
              )}, ${withAlpha(palette.accent, 0.12)} 30%, ${withAlpha(
                palette.surfaceHex,
                0.32,
              )} 72%, transparent)`,
              border: `1px solid ${withAlpha("#FFFFFF", 0.12)}`,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              boxShadow:
                "0 24px 60px rgba(0,0,0,0.22), inset 0 1px 0 rgba(255,255,255,0.06)",
              transform: `scale(${orbPulse})`,
            }}
          >
            <div
              style={{
                width: 150,
                height: 150,
                borderRadius: 52,
                background: `linear-gradient(180deg, ${withAlpha(
                  "#FFFFFF",
                  0.12,
                )}, ${withAlpha("#FFFFFF", 0.02)}), ${withAlpha(
                  palette.surfaceHex,
                  0.84,
                )}`,
                border: `1px solid ${withAlpha("#FFFFFF", 0.12)}`,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: palette.accent,
                fontFamily: fontStack,
                fontSize: 74,
                boxShadow:
                  "0 18px 44px rgba(0,0,0,0.24), inset 0 1px 0 rgba(255,255,255,0.06)",
              }}
            >
              ✦
            </div>
          </div>

          <GlassPill
            label={stageTitle("inquiry")}
            tint={palette.accent}
            style={{ position: "absolute", top: 86, left: -12 }}
          />
          <GlassPill
            label={stageTitle("calibration")}
            tint={palette.warm}
            style={{ position: "absolute", top: 70, right: -4 }}
          />
          <GlassPill
            label={stageTitle("evidence")}
            tint={palette.secondary}
            style={{ position: "absolute", bottom: 90, right: 18 }}
          />
          <GlassPill
            label={stageTitle("action")}
            tint={palette.fresh}
            style={{ position: "absolute", bottom: 52, left: 8 }}
          />
        </div>

        <div
          style={{
            ...titleStyle,
            fontSize: 82,
            lineHeight: 1.06,
            maxWidth: 760,
          }}
        >
          {onboardingTexts.title}
        </div>
        <div
          style={{
            ...bodyStyle,
            fontSize: 34,
            lineHeight: 1.45,
            marginTop: 22,
            maxWidth: 770,
          }}
        >
          {dashboardTexts.tagline}
        </div>

        <div
          style={{
            display: "flex",
            gap: 12,
            marginTop: 34,
            flexWrap: "wrap",
            justifyContent: "center",
          }}
        >
          {taglinePills.slice(0, 3).map((pill, index) => (
            <GlassPill
              key={pill}
              label={pill}
              tint={[palette.accent, palette.secondary, palette.fresh][index] ?? palette.accent}
            />
          ))}
        </div>

        <div
          style={{
            width: "100%",
            marginTop: 54,
            display: "flex",
            flexDirection: "column",
            gap: 16,
          }}
        >
          <PrimaryButton label={onboardingTexts.startButton} />
          <div
            style={{
              color: palette.textTertiary,
              fontFamily: fontStack,
              fontSize: 26,
              fontWeight: 600,
            }}
          >
            跳过
          </div>
        </div>
      </div>
    </PhoneScene>
  );
};

const DashboardScene: FC = () => {
  const frame = useCurrentFrame();
  const opacity = fadeInOut(frame, scenes.dashboard);
  const contentY = trackValue(frame, [
    { frame: 0, value: 0 },
    { frame: 60, value: 0 },
    { frame: 118, value: -130 },
    { frame: 174, value: -320 },
    { frame: scenes.dashboard, value: -360 },
  ]);
  const camera = resolveCamera(frame, [
    { frame: 0, scale: 1, x: 0, y: 0 },
    { frame: 56, scale: 1.14, x: 0, y: -26 },
    { frame: 118, scale: 1.22, x: 0, y: -96 },
    { frame: 180, scale: 1.3, x: 0, y: -240 },
    { frame: scenes.dashboard, scale: 1.22, x: 0, y: -180 },
  ]);

  return (
    <PhoneScene
      opacity={opacity}
      camera={camera}
      overlays={
        <>
          <TapCue frame={frame} start={44} x={284} y={542} label={dashboardTexts.heroTitle} />
          <TapCue
            frame={frame}
            start={108}
            x={330}
            y={982}
            label={dashboardTexts.sectionTitles.maxFocus}
          />
          <TapCue
            frame={frame}
            start={170}
            x={324}
            y={1468}
            label={dashboardTexts.sectionTitles.science}
          />
        </>
      }
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          padding: "94px 28px 40px",
          transform: `translateY(${contentY}px)`,
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "flex-start",
            justifyContent: "space-between",
            marginBottom: 18,
          }}
        >
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <div
              style={{
                color: palette.textPrimary,
                fontFamily: fontStack,
                fontSize: 48,
                fontWeight: 700,
              }}
            >
              {dashboardTexts.title}
            </div>
            <div
              style={{
                color: palette.textSecondary,
                fontFamily: fontStack,
                fontSize: 22,
              }}
            >
              {dashboardTexts.tagline}
            </div>
          </div>
          <GlassPill
            label={dashboardTexts.helpLabel}
            tint={palette.accent}
            style={{ padding: "10px 14px", fontSize: 18 }}
          />
        </div>

        <GlassCard radius={30} padding={18} style={{ marginBottom: 14 }}>
          <div
            style={{
              display: "flex",
              alignItems: "flex-start",
              justifyContent: "space-between",
              gap: 12,
              marginBottom: 14,
            }}
          >
            <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
              <div
                style={{
                  color: palette.accent,
                  fontFamily: fontStack,
                  fontSize: 18,
                  fontWeight: 700,
                }}
              >
                {dashboardTexts.heroTitle}
              </div>
              <div
                style={{
                  color: palette.textPrimary,
                  fontFamily: fontStack,
                  fontSize: 30,
                  fontWeight: 650,
                  lineHeight: 1.25,
                }}
              >
                {dashboardTexts.heroHeadline}
              </div>
              <div
                style={{
                  color: palette.textSecondary,
                  fontFamily: fontStack,
                  fontSize: 18,
                }}
              >
                {dashboardTexts.heroSupport}
              </div>
            </div>
            <GlassPill
              label={dashboardTexts.insightLabel}
              tint={palette.accent}
              style={{ padding: "10px 12px", fontSize: 18 }}
            />
          </div>

          <div style={{ display: "flex", gap: 14, alignItems: "center" }}>
            <ScoreRing score={78} />
            <div style={{ display: "flex", flexDirection: "column", gap: 10, flex: 1 }}>
              <MetricRow title={dashboardTexts.metricLabels.streak} value="6 天" tint={palette.fresh} />
              <MetricRow title={dashboardTexts.metricLabels.completion} value="75%" tint={palette.accent} />
              <MetricRow title={dashboardTexts.metricLabels.priority} value={stageTitle("calibration")} tint={palette.warm} />
            </div>
          </div>

          <div style={{ display: "flex", gap: 8, marginTop: 14 }}>
            <GlassPill
              label={dashboardTexts.badges[0] ?? "最小动作优先"}
              tint={palette.accent}
              style={{ padding: "10px 12px", fontSize: 18 }}
            />
            <GlassPill
              label={dashboardTexts.badges[1] ?? "允许中断再继续"}
              tint={palette.secondary}
              style={{ padding: "10px 12px", fontSize: 18 }}
            />
          </div>

          <div style={{ marginTop: 14 }}>
            <div
              style={{
                color: palette.textTertiary,
                fontFamily: fontStack,
                fontSize: 18,
                fontWeight: 600,
                marginBottom: 8,
              }}
              >
              {dashboardTexts.nextStepLabel}
            </div>
            <div
              style={{
                padding: "14px 16px",
                borderRadius: 18,
                background: withAlpha("#FFFFFF", 0.045),
                border: `1px solid ${withAlpha("#FFFFFF", 0.06)}`,
              }}
            >
              <div
                style={{
                  color: palette.textPrimary,
                  fontFamily: fontStack,
                  fontSize: 24,
                  fontWeight: 650,
                  marginBottom: 4,
                }}
              >
                {stageTitle("calibration")}
              </div>
              <div
                style={{
                  color: palette.textSecondary,
                  fontFamily: fontStack,
                  fontSize: 20,
                  lineHeight: 1.4,
                }}
              >
                {stageSummary("calibration")}
              </div>
            </div>
          </div>
        </GlassCard>

        <GlassCard radius={26} padding={16} style={{ marginBottom: 14 }}>
          <SectionHeader badge="✦" title={dashboardTexts.sectionTitles.maxFocus} />
          <div
            style={{
              color: palette.textPrimary,
              fontFamily: fontStack,
              fontSize: 24,
              lineHeight: 1.42,
              marginTop: 14,
              marginBottom: 12,
            }}
          >
            {dashboardTexts.maxQuestion}
          </div>
          <div
            style={{
              padding: "12px 14px",
              borderRadius: 16,
              background: withAlpha("#FFFFFF", 0.045),
              border: `1px solid ${withAlpha("#FFFFFF", 0.06)}`,
              marginBottom: 10,
            }}
          >
            <div
              style={{
                color: palette.textTertiary,
                fontFamily: fontStack,
                fontSize: 17,
                fontWeight: 600,
                marginBottom: 4,
              }}
            >
              {dashboardTexts.evidenceLabel}
            </div>
            <div
              style={{
                color: palette.textPrimary,
                fontFamily: fontStack,
                fontSize: 22,
                fontWeight: 600,
                marginBottom: 2,
              }}
            >
              {dashboardTexts.evidenceSource}
            </div>
            <div
              style={{
                color: palette.textSecondary,
                fontFamily: fontStack,
                fontSize: 18,
              }}
            >
              匹配完成后会进入科学解释
            </div>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            <OptionButton label={stageSummary("calibration")} />
            <OptionButton label={stageSummary("evidence")} />
          </div>
        </GlassCard>

        <GlassCard radius={26} padding={16} style={{ marginBottom: 14 }}>
          <SectionHeader badge="∿" title={dashboardTexts.sectionTitles.calibration} />
          <div
            style={{
              color: palette.textSecondary,
              fontFamily: fontStack,
              fontSize: 21,
              lineHeight: 1.42,
              marginTop: 14,
            }}
          >
            {dashboardTexts.calibrationBody}
          </div>
        </GlassCard>

        <GlassCard radius={26} padding={16} style={{ marginBottom: 14 }}>
          <SectionHeader badge="≣" title={dashboardTexts.sectionTitles.science} />
          <div style={{ display: "flex", flexDirection: "column", gap: 8, marginTop: 14 }}>
            <ExplanationRow title={dashboardTexts.science.conclusionTitle} value="今天更像是触发后的紧绷被放大，不是必须马上硬扛。" />
            <ExplanationRow title={dashboardTexts.science.mechanismTitle} value="触发和身体信号会互相放大，所以先降身体负荷，再做下一步。" />
            <ExplanationRow title={dashboardTexts.science.actionTitle} value="先做 1 分钟缓慢呼气，然后回到当前任务。" />
            <ExplanationRow title={dashboardTexts.science.followupTitle} value="执行后你的体感变化有多大（0-10）？" />
          </div>
          <div style={{ marginTop: 12 }}>
            <GlassPill
              label={dashboardTexts.scienceJournalLabel}
              tint={palette.accent}
              style={{ padding: "10px 14px", fontSize: 18 }}
            />
          </div>
        </GlassCard>

        <GlassCard radius={26} padding={16}>
          <SectionHeader badge="✓" title={dashboardTexts.sectionTitles.action} />
          <div style={{ display: "flex", flexDirection: "column", gap: 12, marginTop: 14 }}>
            <ActionBullet title="先做 1 分钟缓慢呼气" />
            <ActionBullet title="完成后记录 0-10 的体感变化" />
            <ActionBullet title={`需要时点“${dashboardTexts.followUpButton}”`} />
          </div>
          <PrimaryButton
            label={dashboardTexts.followUpButton}
            style={{ marginTop: 14, fontSize: 26, padding: "16px 18px" }}
          />
        </GlassCard>
      </div>
    </PhoneScene>
  );
};

const MaxScene: FC = () => {
  const frame = useCurrentFrame();
  const opacity = fadeInOut(frame, scenes.max);

  const activeStage: StageKey =
    frame < 50 ? "inquiry" : frame < 100 ? "calibration" : frame < 150 ? "evidence" : "action";

  const stageDetail =
    stageSummary(activeStage);

  const thinkingText =
    activeStage === "inquiry"
      ? maxTexts.thinkingTexts[0] ?? "正在理解你的焦虑场景..."
      : activeStage === "calibration"
        ? maxTexts.thinkingTexts[1] ?? "校准触发因素与身体信号..."
        : activeStage === "evidence"
          ? maxTexts.thinkingTexts[2] ?? "检索科学证据..."
          : maxTexts.thinkingTexts[3] ?? "生成机制解释与行动方案...";

  const camera = resolveCamera(frame, [
    { frame: 0, scale: 1, x: 0, y: 0 },
    { frame: 48, scale: 1.14, x: 0, y: -42 },
    { frame: 102, scale: 1.22, x: 0, y: -136 },
    { frame: 156, scale: 1.3, x: 0, y: -248 },
    { frame: scenes.max, scale: 1.24, x: 0, y: -220 },
  ]);

  const assistantCardEnter = riseIn(frame, 30, 132);

  return (
    <PhoneScene
      opacity={opacity}
      camera={camera}
      overlays={
        <>
          <TapCue frame={frame} start={24} x={446} y={368} label={maxTexts.continueTitle} />
          <TapCue
            frame={frame}
            start={88}
            x={288}
            y={822}
            label={maxTexts.overviewTitles.evidence}
          />
          <TapCue frame={frame} start={150} x={322} y={1360} label={dashboardTexts.followUpButton} />
        </>
      }
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          padding: "100px 30px 36px",
        }}
      >
        <div
          style={{
            position: "absolute",
            top: 120,
            right: 30,
            width: 320,
            height: 320,
            borderRadius: "50%",
            background: withAlpha(palette.accent, 0.08),
            filter: "blur(60px)",
          }}
        />
        <div
          style={{
            display: "flex",
            alignItems: "flex-start",
            justifyContent: "space-between",
            gap: 14,
            marginBottom: 16,
          }}
        >
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <div
              style={{
                color: palette.accent,
                fontFamily: fontStack,
                fontSize: 18,
                fontWeight: 700,
              }}
            >
              {maxTexts.title}
            </div>
            <div
              style={{
                color: palette.textPrimary,
                fontFamily: fontStack,
                fontSize: 42,
                fontWeight: 700,
              }}
            >
              {maxTexts.executionTitle}
            </div>
            <div
              style={{
                color: palette.textSecondary,
                fontFamily: fontStack,
                fontSize: 22,
              }}
            >
              {maxTexts.continueDetail}
            </div>
          </div>
          <GlassPill
            label={maxTexts.sessionKept}
            tint={palette.accent}
            style={{ padding: "10px 14px", fontSize: 18 }}
          />
        </div>

        <GlassCard radius={30} padding={18} style={{ marginBottom: 14 }}>
          <div
            style={{
              color: palette.accent,
              fontFamily: fontStack,
              fontSize: 18,
              fontWeight: 700,
              marginBottom: 8,
            }}
          >
            {maxTexts.continueTitle}
          </div>
          <div
            style={{
              color: palette.textPrimary,
              fontFamily: fontStack,
              fontSize: 28,
              fontWeight: 650,
              lineHeight: 1.32,
              marginBottom: 14,
            }}
          >
            {maxTexts.continueDetail}
          </div>
          <div style={{ display: "flex", gap: 8, marginBottom: 14 }}>
            <StagePill title={stageTitle("inquiry")} active={activeStage === "inquiry"} />
            <StagePill title={stageTitle("calibration")} active={activeStage === "calibration"} />
            <StagePill title={stageTitle("evidence")} active={activeStage === "evidence"} />
            <StagePill title={stageTitle("action")} active={activeStage === "action"} />
          </div>
          <div
            style={{
              padding: "14px 16px",
              borderRadius: 18,
              background: withAlpha("#FFFFFF", 0.045),
              border: `1px solid ${withAlpha("#FFFFFF", 0.06)}`,
              marginBottom: 12,
            }}
          >
            <div
              style={{
                color: palette.textPrimary,
                fontFamily: fontStack,
                fontSize: 26,
                fontWeight: 650,
                marginBottom: 4,
              }}
            >
              {activeStage === "inquiry"
                ? stageTitle("inquiry")
                : activeStage === "calibration"
                  ? stageTitle("calibration")
                  : activeStage === "evidence"
                    ? stageTitle("evidence")
                    : stageTitle("action")}
            </div>
            <div
              style={{
                color: palette.textSecondary,
                fontFamily: fontStack,
                fontSize: 21,
                lineHeight: 1.4,
              }}
            >
              {stageDetail}
            </div>
          </div>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 12 }}>
            <GlassPill
              label="理解场景"
              tint={palette.accent}
              style={{ padding: "10px 12px", fontSize: 18 }}
            />
            <GlassPill
              label="身体信号"
              tint={palette.warm}
              style={{ padding: "10px 12px", fontSize: 18 }}
            />
            <GlassPill
              label="科学证据"
              tint={palette.secondary}
              style={{ padding: "10px 12px", fontSize: 18 }}
            />
            <GlassPill
              label="行动方案"
              tint={palette.fresh}
              style={{ padding: "10px 12px", fontSize: 18 }}
            />
          </div>
          <PrimaryButton
            label={dashboardTexts.followUpButton}
            style={{ fontSize: 26, padding: "16px 18px" }}
          />
        </GlassCard>

        <GlassCard radius={28} padding={18} style={{ marginBottom: 14 }}>
          <div
            style={{
              display: "flex",
              alignItems: "flex-start",
              justifyContent: "space-between",
              gap: 12,
              marginBottom: 14,
            }}
          >
            <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
              <div
                style={{
                  color: palette.textPrimary,
                  fontFamily: fontStack,
                  fontSize: 28,
                  fontWeight: 650,
                }}
              >
                {maxTexts.executionTitle}
              </div>
              <div
                style={{
                  color: palette.textSecondary,
                  fontFamily: fontStack,
                  fontSize: 18,
                  lineHeight: 1.38,
                }}
              >
                {maxTexts.executionDetail}
              </div>
            </div>
            <GlassPill
              label={maxTexts.sessionKept}
              tint={palette.accent}
              style={{ padding: "8px 12px", fontSize: 16 }}
            />
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            <OverviewRow
              title={maxTexts.overviewTitles.inquiry}
              value={stageSummary("inquiry")}
              tint={palette.accent}
            />
            <OverviewRow
              title={maxTexts.overviewTitles.plan}
              value="先做 1 分钟缓慢呼气，再决定是否继续任务。"
              tint={palette.secondary}
            />
            <OverviewRow
              title={maxTexts.overviewTitles.evidence}
              value={`正在匹配${dashboardTexts.evidenceSource}`}
              tint={palette.warm}
            />
          </div>
        </GlassCard>

        <GlassCard radius={28} padding={16}>
          <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
            <ChatBubble
              role="user"
              text="今天最明显的不适，是任务开始前身体会突然发紧。"
              time="09:41"
            />
            <TypingIndicatorCard frame={frame} text={thinkingText} />
            <div
              style={{
                opacity: assistantCardEnter,
                transform: `translateY(${(1 - assistantCardEnter) * 26}px)`,
              }}
            >
              <ChatBubble
                role="assistant"
                text="先把身体负荷降下来，再决定下一步。执行后告诉我 0-10 的变化。"
                time="09:42"
              />
            </div>
          </div>
        </GlassCard>
      </div>
    </PhoneScene>
  );
};

const OverviewRow: FC<{
  title: string;
  value: string;
  tint: string;
}> = ({ title, value, tint }) => {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "flex-start",
        gap: 12,
        padding: "14px 14px",
        borderRadius: 18,
        background: withAlpha("#FFFFFF", 0.045),
        border: `1px solid ${withAlpha("#FFFFFF", 0.06)}`,
      }}
    >
      <div
        style={{
          width: 12,
          height: 12,
          marginTop: 8,
          borderRadius: "50%",
          background: tint,
          boxShadow: `0 0 16px ${withAlpha(tint, 0.22)}`,
        }}
      />
      <div style={{ display: "flex", flexDirection: "column", gap: 4, flex: 1 }}>
        <div
          style={{
            color: tint,
            fontFamily: fontStack,
            fontSize: 18,
            fontWeight: 700,
          }}
        >
          {title}
        </div>
        <div
          style={{
            color: palette.textPrimary,
            fontFamily: fontStack,
            fontSize: 22,
            lineHeight: 1.4,
          }}
        >
          {value}
        </div>
      </div>
    </div>
  );
};

const ActionScene: FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const opacity = fadeInOut(frame, scenes.action);
  const contentY = trackValue(frame, [
    { frame: 0, value: 0 },
    { frame: 56, value: 0 },
    { frame: 92, value: -120 },
    { frame: scenes.action, value: -170 },
  ]);
  const camera = resolveCamera(frame, [
    { frame: 0, scale: 1, x: 0, y: 0 },
    { frame: 52, scale: 1.14, x: 0, y: -34 },
    { frame: 92, scale: 1.26, x: 0, y: -156 },
    { frame: scenes.action, scale: 1.36, x: 0, y: -300 },
  ]);

  const cycle = frame % 114;
  const phaseLabel =
    cycle < 27
      ? breathingTexts.phases[0] ?? "吸气"
      : cycle < 66
        ? breathingTexts.phases[1] ?? "屏息"
        : breathingTexts.phases[2] ?? "呼气";
  const ringScale =
    phaseLabel === "吸气"
      ? 0.94 + Math.sin((cycle / 27) * Math.PI) * 0.1
      : phaseLabel === "屏息"
        ? 1.04
        : 1.04 - Math.sin(((cycle - 66) / 48) * Math.PI) * 0.14;
  const glowAlpha = 0.16 + Math.sin((frame / fps) * Math.PI * 0.8) * 0.04;

  return (
    <PhoneScene
      opacity={opacity}
      camera={camera}
      overlays={<TapCue frame={frame} start={72} x={458} y={1420} label={breathingTexts.title} />}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          padding: "100px 30px 40px",
          transform: `translateY(${contentY}px)`,
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "flex-start",
            justifyContent: "space-between",
            gap: 12,
            marginBottom: 14,
          }}
        >
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <div
              style={{
                color: palette.accent,
                fontFamily: fontStack,
                fontSize: 18,
                fontWeight: 700,
              }}
            >
              `${dashboardTexts.sectionTitles.science}与行动`
            </div>
            <div
              style={{
                color: palette.textPrimary,
                fontFamily: fontStack,
                fontSize: 40,
                fontWeight: 700,
              }}
            >
              真实证据与低阻力动作
            </div>
          </div>
          <GlassPill
            label="只展示真实匹配结果"
            tint={palette.accent}
            style={{ padding: "10px 12px", fontSize: 16 }}
          />
        </div>

        <GlassCard radius={28} padding={18} style={{ marginBottom: 14 }}>
          <SectionHeader badge="≣" title={dashboardTexts.sectionTitles.science} />
          <div style={{ display: "flex", flexDirection: "column", gap: 8, marginTop: 14 }}>
            <ExplanationRow title={dashboardTexts.science.conclusionTitle} value="今天更像是任务前紧绷被放大，不是必须马上顶住。" />
            <ExplanationRow title={dashboardTexts.science.mechanismTitle} value="触发后，身体信号会先变强；先降生理负荷，决策会更稳。" />
            <ExplanationRow title={dashboardTexts.science.evidenceTitle} value={dashboardTexts.evidenceSource} />
            <ExplanationRow title={dashboardTexts.science.followupTitle} value="执行后你的体感变化有多大（0-10）？" />
          </div>
        </GlassCard>

        <GlassCard radius={28} padding={18} style={{ marginBottom: 14 }}>
          <SectionHeader badge="✓" title={dashboardTexts.sectionTitles.action} />
          <div style={{ display: "flex", flexDirection: "column", gap: 12, marginTop: 14 }}>
            <ActionBullet title="先做 1 分钟缓慢呼气" detail="先把身体负荷降下来，再决定是否继续任务。" />
            <ActionBullet title="完成后记录体感变化" detail="用 0-10 的刻度反馈，方便下一轮优化。" />
            <ActionBullet title="需要时再让 Max 接手" detail="动作执行后再继续复盘，不必一次做完整套。" />
          </div>
        </GlassCard>

        <GlassCard radius={34} padding={22}>
          <div
            style={{
              position: "absolute",
              inset: 0,
              background: `radial-gradient(circle at 50% 28%, ${withAlpha(
                palette.accent,
                glowAlpha,
              )}, transparent 44%)`,
              pointerEvents: "none",
            }}
          />
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              textAlign: "center",
              position: "relative",
              zIndex: 1,
            }}
          >
            <div
              style={{
                color: palette.textPrimary,
                fontFamily: fontStack,
                fontSize: 34,
                fontWeight: 700,
                marginBottom: 6,
              }}
            >
              {breathingTexts.title}
            </div>
            <div
              style={{
                color: palette.textSecondary,
                fontFamily: fontStack,
                fontSize: 20,
                marginBottom: 22,
              }}
            >
              {breathingTexts.subtitle}
            </div>

            <div
              style={{
                position: "relative",
                width: 320,
                height: 320,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                marginBottom: 22,
              }}
            >
              {[280, 220, 164].map((size, index) => (
                <div
                  key={size}
                  style={{
                    position: "absolute",
                    inset: (320 - size) / 2,
                    borderRadius: "50%",
                    border: `1px solid ${withAlpha(
                      [palette.accent, palette.secondary, palette.fresh][index],
                      0.22,
                    )}`,
                    transform: `scale(${ringScale + index * 0.02})`,
                  }}
                />
              ))}
              <div
                style={{
                  width: 170,
                  height: 170,
                  borderRadius: "50%",
                  background: `radial-gradient(circle at 30% 30%, ${withAlpha(
                    "#FFFFFF",
                    0.16,
                  )}, ${withAlpha(palette.accent, 0.08)} 36%, ${withAlpha(
                    palette.surfaceHex,
                    0.3,
                  )} 76%, transparent)`,
                  border: `1px solid ${withAlpha("#FFFFFF", 0.1)}`,
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                  justifyContent: "center",
                  transform: `scale(${ringScale})`,
                }}
              >
                <div
                  style={{
                    color: palette.textPrimary,
                    fontFamily: fontStack,
                    fontSize: 44,
                    fontWeight: 700,
                    marginBottom: 4,
                  }}
                >
                  05:00
                </div>
                <div
                  style={{
                    color: palette.accent,
                    fontFamily: fontStack,
                    fontSize: 24,
                    fontWeight: 650,
                  }}
                >
                  {phaseLabel}
                </div>
              </div>
            </div>

            <div style={{ display: "flex", gap: 8, marginBottom: 18 }}>
              <GlassPill
                label={breathingTexts.phases[0] ?? "吸气"}
                tint={palette.accent}
                style={{ padding: "10px 12px", fontSize: 18 }}
              />
              <GlassPill
                label={breathingTexts.phases[1] ?? "屏息"}
                tint={palette.warm}
                style={{ padding: "10px 12px", fontSize: 18 }}
              />
              <GlassPill
                label={breathingTexts.phases[2] ?? "呼气"}
                tint={palette.fresh}
                style={{ padding: "10px 12px", fontSize: 18 }}
              />
            </div>

            <PrimaryButton label={breathingTexts.endButton} style={{ fontSize: 26, padding: "16px 18px", width: "100%" }} />
          </div>
        </GlassCard>
      </div>
    </PhoneScene>
  );
};

const PaletteOnlyOnboardingScene: FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const opacity = fadeInOut(frame, stylizedScenes.onboarding);
  const camera = resolveCamera(frame, [
    { frame: 0, scale: 1, x: 0, y: 0 },
    { frame: 46, scale: 1.08, x: 0, y: -20 },
    { frame: stylizedScenes.onboarding, scale: 1.14, x: 0, y: -120 },
  ]);
  const pulse = 1 + Math.sin((frame / fps) * Math.PI * 1.15) * 0.05;

  return (
    <PhoneScene
      opacity={opacity}
      camera={camera}
      overlays={<TapCue frame={frame} start={84} x={420} y={1528} label={onboardingTexts.startButton} />}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          padding: "102px 42px 42px",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          textAlign: "center",
        }}
      >
        <div
          style={{
            color: palette.textTertiary,
            fontFamily: fontStack,
            fontSize: 22,
            letterSpacing: 6,
            textTransform: "uppercase",
            marginBottom: 18,
          }}
        >
          Onboarding
        </div>
        <div
          style={{
            position: "relative",
            width: 520,
            height: 520,
            marginBottom: 42,
          }}
        >
          {[480, 392, 302].map((size, index) => (
            <div
              key={size}
              style={{
                position: "absolute",
                inset: (520 - size) / 2,
                borderRadius: "50%",
                border: `1px solid ${withAlpha(
                  [palette.accent, palette.secondary, palette.warm][index],
                  0.24,
                )}`,
                transform: `scale(${pulse + index * 0.02}) rotate(${frame * (0.4 + index * 0.1)}deg)`,
              }}
            />
          ))}
          <div
            style={{
              position: "absolute",
              inset: 118,
              borderRadius: "50%",
              background: `radial-gradient(circle at 30% 30%, ${withAlpha(
                "#FFFFFF",
                0.18,
              )}, ${withAlpha(palette.accent, 0.1)} 36%, transparent 76%)`,
              border: `1px solid ${withAlpha("#FFFFFF", 0.12)}`,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              transform: `scale(${pulse})`,
            }}
          >
            <div
              style={{
                width: 158,
                height: 158,
                borderRadius: 54,
                background: `linear-gradient(180deg, ${withAlpha("#FFFFFF", 0.12)}, ${withAlpha(
                  "#FFFFFF",
                  0.02,
                )}), ${withAlpha(palette.surfaceHex, 0.84)}`,
                border: `1px solid ${withAlpha("#FFFFFF", 0.12)}`,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: palette.accent,
                fontSize: 80,
              }}
            >
              ◎
            </div>
          </div>
          <GlassPill label={stageTitle("inquiry")} tint={palette.accent} style={{ position: "absolute", top: 88, left: 0 }} />
          <GlassPill label={stageTitle("calibration")} tint={palette.warm} style={{ position: "absolute", top: 56, right: 2 }} />
          <GlassPill label={stageTitle("action")} tint={palette.fresh} style={{ position: "absolute", bottom: 76, left: 20 }} />
        </div>
        <div style={{ ...titleStyle, fontSize: 78, lineHeight: 1.04, maxWidth: 760 }}>
          {onboardingTexts.title}
        </div>
        <div style={{ ...bodyStyle, fontSize: 30, lineHeight: 1.44, maxWidth: 740, marginTop: 22 }}>
          流动玻璃界面、层级引导与节奏化反馈
        </div>
        <div style={{ display: "flex", gap: 12, marginTop: 34, flexWrap: "wrap", justifyContent: "center" }}>
          <GlassPill label="Adaptive flow" tint={palette.secondary} />
          <GlassPill label="Ambient focus" tint={palette.accent} />
          <GlassPill label="Soft guidance" tint={palette.fresh} />
        </div>
        <div style={{ width: "100%", marginTop: 54 }}>
          <PrimaryButton label={onboardingTexts.startButton} />
        </div>
      </div>
    </PhoneScene>
  );
};

const PaletteOnlyMaxScene: FC = () => {
  const frame = useCurrentFrame();
  const opacity = fadeInOut(frame, stylizedScenes.max);
  const camera = resolveCamera(frame, [
    { frame: 0, scale: 1, x: 0, y: 0 },
    { frame: 56, scale: 1.1, x: 0, y: -40 },
    { frame: 112, scale: 1.18, x: 0, y: -130 },
    { frame: stylizedScenes.max, scale: 1.14, x: 0, y: -110 },
  ]);

  return (
    <PhoneScene
      opacity={opacity}
      camera={camera}
      overlays={
        <>
          <TapCue frame={frame} start={22} x={700} y={404} label="Aurora focus" />
          <TapCue frame={frame} start={84} x={312} y={944} label="Signal layer" />
        </>
      }
    >
      <div style={{ position: "absolute", inset: 0, padding: "100px 32px 36px" }}>
        <div
          style={{
            position: "absolute",
            top: 140,
            left: 120,
            width: 460,
            height: 460,
            borderRadius: "50%",
            background: withAlpha(palette.accent, 0.08),
            filter: "blur(70px)",
          }}
        />
        <div
          style={{
            display: "flex",
            alignItems: "flex-start",
            justifyContent: "space-between",
            gap: 12,
            marginBottom: 16,
          }}
        >
          <div>
            <div style={{ color: palette.accent, fontFamily: fontStack, fontSize: 18, fontWeight: 700 }}>
              Max
            </div>
            <div style={{ color: palette.textPrimary, fontFamily: fontStack, fontSize: 44, fontWeight: 700 }}>
              Cinematic guidance
            </div>
          </div>
          <GlassPill label="Live state" tint={palette.secondary} style={{ padding: "10px 14px", fontSize: 18 }} />
        </div>

        <GlassCard radius={32} padding={22} style={{ marginBottom: 14 }}>
          <div style={{ color: palette.textPrimary, fontFamily: fontStack, fontSize: 30, fontWeight: 650, marginBottom: 12 }}>
            Atmospheric agent surface
          </div>
          <div style={{ color: palette.textSecondary, fontFamily: fontStack, fontSize: 22, lineHeight: 1.42, marginBottom: 16 }}>
            保留上一版更概念化的玻璃层和漂浮面板，只把整体色温和 UI 色改成 antios10 的主题。
          </div>
          <div style={{ display: "flex", gap: 10, marginBottom: 16 }}>
            <StagePill title="Onboarding" active />
            <StagePill title="Signal" active={false} />
            <StagePill title="Evidence" active={false} />
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
            <GlassCard padding={16} radius={22}>
              <div style={{ color: palette.accent, fontSize: 18, fontFamily: fontStack, fontWeight: 700, marginBottom: 6 }}>
                Layer 01
              </div>
              <div style={{ color: palette.textPrimary, fontSize: 24, fontFamily: fontStack, lineHeight: 1.4 }}>
                Fluid transitions and softened focus cues.
              </div>
            </GlassCard>
            <GlassCard padding={16} radius={22}>
              <div style={{ color: palette.warm, fontSize: 18, fontFamily: fontStack, fontWeight: 700, marginBottom: 6 }}>
                Layer 02
              </div>
              <div style={{ color: palette.textPrimary, fontSize: 24, fontFamily: fontStack, lineHeight: 1.4 }}>
                Conceptual panels stay abstract in this preserved variant.
              </div>
            </GlassCard>
          </div>
        </GlassCard>

        <GlassCard radius={28} padding={18}>
          <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
            <TypingIndicatorCard frame={frame} text={maxTexts.thinkingTexts[0] ?? "正在理解你的焦虑场景..."} />
            <ChatBubble
              role="assistant"
              text="This preserved cut keeps the old abstract components and only regrades the palette into the app’s liquid glass colors."
              time="09:42"
            />
          </div>
        </GlassCard>
      </div>
    </PhoneScene>
  );
};

const PaletteOnlyDashboardScene: FC = () => {
  const frame = useCurrentFrame();
  const opacity = fadeInOut(frame, stylizedScenes.dashboard);
  const camera = resolveCamera(frame, [
    { frame: 0, scale: 1, x: 0, y: 0 },
    { frame: 58, scale: 1.12, x: 0, y: -50 },
    { frame: 124, scale: 1.2, x: 0, y: -180 },
    { frame: stylizedScenes.dashboard, scale: 1.15, x: 0, y: -140 },
  ]);

  return (
    <PhoneScene
      opacity={opacity}
      camera={camera}
      overlays={
        <>
          <TapCue frame={frame} start={42} x={318} y={510} label="Focus map" />
          <TapCue frame={frame} start={116} x={334} y={1248} label="Tone-matched dashboard" />
        </>
      }
    >
      <div style={{ position: "absolute", inset: 0, padding: "96px 30px 40px" }}>
        <div style={{ color: palette.textTertiary, fontFamily: fontStack, fontSize: 22, letterSpacing: 6, textTransform: "uppercase", marginBottom: 14 }}>
          Dashboard
        </div>
        <GlassCard radius={30} padding={20} style={{ marginBottom: 14 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
            <ScoreRing score={84} />
            <div style={{ display: "flex", flexDirection: "column", gap: 10, flex: 1 }}>
              <MetricRow title="Focus map" value="Adaptive" tint={palette.accent} />
              <MetricRow title="Signal bands" value="Reactive" tint={palette.secondary} />
              <MetricRow title="UI tone" value="Liquid Glass" tint={palette.warm} />
            </div>
          </div>
        </GlassCard>

        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, marginBottom: 14 }}>
          <GlassCard padding={18} radius={24}>
            <div style={{ color: palette.textPrimary, fontFamily: fontStack, fontSize: 28, fontWeight: 650, marginBottom: 8 }}>
              Floating cards
            </div>
            <div style={{ color: palette.textSecondary, fontFamily: fontStack, fontSize: 20, lineHeight: 1.42 }}>
              保留不贴 app 组件的旧版结构。
            </div>
          </GlassCard>
          <GlassCard padding={18} radius={24}>
            <div style={{ color: palette.textPrimary, fontFamily: fontStack, fontSize: 28, fontWeight: 650, marginBottom: 8 }}>
              Palette match
            </div>
            <div style={{ color: palette.textSecondary, fontFamily: fontStack, fontSize: 20, lineHeight: 1.42 }}>
              只同步真实主题色、文字明暗和玻璃层气氛。
            </div>
          </GlassCard>
        </div>

        <GlassCard radius={28} padding={18}>
          <div style={{ color: palette.textPrimary, fontFamily: fontStack, fontSize: 30, fontWeight: 650, marginBottom: 14 }}>
            Stylized retention cut
          </div>
          <div style={{ display: "flex", gap: 10, flexWrap: "wrap", marginBottom: 14 }}>
            <GlassPill label="Ambient gradients" tint={palette.accent} />
            <GlassPill label="Soft chrome" tint={palette.secondary} />
            <GlassPill label="Warm neutrals" tint={palette.warm} />
          </div>
          <PrimaryButton label="Palette-only version" style={{ fontSize: 26, padding: "16px 18px" }} />
        </GlassCard>
      </div>
    </PhoneScene>
  );
};

export const Antios10Preview: FC = () => {
  return (
    <AbsoluteFill style={{ background: palette.abyss }}>
      <AmbientBackdrop />
      <Sequence durationInFrames={scenes.onboarding}>
        <OnboardingScene />
      </Sequence>
      <Sequence from={scenes.onboarding} durationInFrames={scenes.dashboard}>
        <DashboardScene />
      </Sequence>
      <Sequence
        from={scenes.onboarding + scenes.dashboard}
        durationInFrames={scenes.max}
      >
        <MaxScene />
      </Sequence>
      <Sequence
        from={scenes.onboarding + scenes.dashboard + scenes.max}
        durationInFrames={scenes.action}
      >
        <ActionScene />
      </Sequence>
    </AbsoluteFill>
  );
};

export const Antios10PaletteOnlyPreview: FC = () => {
  return (
    <AbsoluteFill style={{ background: palette.abyss }}>
      <AmbientBackdrop />
      <Sequence durationInFrames={stylizedScenes.onboarding}>
        <PaletteOnlyOnboardingScene />
      </Sequence>
      <Sequence from={stylizedScenes.onboarding} durationInFrames={stylizedScenes.max}>
        <PaletteOnlyMaxScene />
      </Sequence>
      <Sequence
        from={stylizedScenes.onboarding + stylizedScenes.max}
        durationInFrames={stylizedScenes.dashboard}
      >
        <PaletteOnlyDashboardScene />
      </Sequence>
    </AbsoluteFill>
  );
};
