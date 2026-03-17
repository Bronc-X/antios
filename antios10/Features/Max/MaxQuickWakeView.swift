// MaxQuickWakeView.swift
// Max 快速唤醒视图（用于 Spotlight 和锁屏快速访问）

import SwiftUI

struct MaxQuickWakeView: View {
    @State private var inputText = ""
    @State private var isProcessing = false
    @FocusState private var isFocused: Bool
    @EnvironmentObject private var appSettings: AppSettings

    private func t(_ zh: String, _ en: String) -> String {
        L10n.text(zh, en, language: appSettings.language)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // 头像和状态
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "brain.head.profile")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Max")
                        .font(.headline)
                    Text(isProcessing ? t("思考中...", "Thinking...") : t("有什么我能帮你的？", "What can I help with?"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isProcessing {
                    ProgressView()
                }
            }
            
            // 快速问题输入
            HStack(spacing: 12) {
                TextField(t("快速问 Max...", "Ask Max quickly..."), text: $inputText)
                    .focused($isFocused)
                    .textFieldStyle(.plain)
                    .submitLabel(.send)
                    .onSubmit(sendQuickQuestion)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                
                Button {
                    sendQuickQuestion()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.cyan)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
            }
            
            // 快捷操作
            HStack(spacing: 12) {
                QuickActionButton(icon: "waveform.path.ecg", title: t("查看 HRV", "View HRV")) {
                    handoffToCoach(intent: "sensor_follow_up")
                }
                
                QuickActionButton(icon: "brain.head.profile", title: t("记录状态", "Log my state")) {
                    handoffToCoach(intent: "check_in")
                }
                
                QuickActionButton(icon: "wind", title: t("呼吸练习", "Breathing")) {
                    handoffToCoach(intent: "breathing", userInfo: ["duration": 5])
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onAppear {
            isFocused = true
        }
    }
    
    private func sendQuickQuestion() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        isProcessing = true
        handoffToCoach(question: trimmed)
        
        // 延迟后重置
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isProcessing = false
            inputText = ""
        }
    }

    private func handoffToCoach(
        intent: String? = nil,
        question: String? = nil,
        userInfo: [String: Any] = [:]
    ) {
        NotificationCenter.default.post(name: .openMaxChat, object: nil)
        var payload = userInfo
        if let intent { payload["intent"] = intent }
        if let question { payload["question"] = question }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            NotificationCenter.default.post(name: .askMax, object: nil, userInfo: payload)
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .foregroundColor(.primary)
    }
}

struct MaxQuickWakeView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MaxQuickWakeView()
                .padding()
        }
        .environmentObject(AppSettings())
        .preferredColorScheme(.dark)
    }
}
