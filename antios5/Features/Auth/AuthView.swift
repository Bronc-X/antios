import SwiftUI

// MARK: - ViewModel
@MainActor
class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var error: String?
    
    func authenticate(isLogin: Bool) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            if isLogin {
                try await SupabaseManager.shared.signIn(email: email, password: password)
            } else {
                try await SupabaseManager.shared.signUp(email: email, password: password)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct AuthView: View {
    @StateObject private var viewModel = AuthViewModel()
    @State private var isLogin = true
    @State private var showPassword = false
    @State private var showAuthInfoSheet = false
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            AuroraBackground()
            
            VStack(spacing: 30) {
                Spacer()
                
                // 品牌区域
                VStack(spacing: 14) {
                    AuthBrandMark()
                    
                    Text("AntiAnxiety")
                        .font(GlassTypography.loviTitle(34, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    
                    Text("更轻、更稳地回到你自己")
                        .font(GlassTypography.cnLovi(16, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                
                // 表单
                LiquidGlassCard(style: .elevated, padding: 24) {
                    VStack(spacing: 24) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(isLogin ? "欢迎回来" : "创建账户")
                                    .font(GlassTypography.cnLovi(24, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Text(isLogin ? "继续你的恢复节奏" : "30 秒开启个性化反焦虑计划")
                                    .font(GlassTypography.cnLovi(13, weight: .regular))
                                    .foregroundColor(.textSecondary)
                            }
                            Spacer()
                            Button {
                                let impact = UIImpactFeedbackGenerator(style: .soft)
                                impact.impactOccurred()
                                showAuthInfoSheet = true
                            } label: {
                                Image(systemName: "questionmark.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.liquidGlassAccent)
                                    .liquidGlassCircleBadge(padding: 6)
                            }
                            .buttonStyle(.plain)
                        }

                        // 登录/注册切换
                        HStack {
                            ForEach([true, false], id: \.self) { login in
                                Button {
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                        isLogin = login
                                    }
                                } label: {
                                    Text(login ? "登录" : "注册")
                                        .font(GlassTypography.cnLovi(15, weight: .semibold))
                                        .foregroundColor(isLogin == login ? .bgPrimary : .textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            Capsule()
                                                .fill(isLogin == login ? Color.liquidGlassAccent : Color.clear)
                                                .overlay(
                                                    Capsule().stroke(
                                                        isLogin == login ? Color.white.opacity(0.35) : Color.clear,
                                                        lineWidth: 1
                                                    )
                                                )
                                        )
                                }
                            }
                        }
                        .padding(6)
                        .background(Color.surfaceGlass(for: colorScheme))
                        .clipShape(Capsule())
                        
                        TextField("邮箱", text: $viewModel.email)
                            .textFieldStyle(.plain)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.surfaceGlass(for: colorScheme))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
                            )
                            .foregroundColor(.textPrimary)
                            .font(GlassTypography.cnLovi(17, weight: .regular))
                        
                        HStack(spacing: 10) {
                            Group {
                                if showPassword {
                                    TextField("密码", text: $viewModel.password)
                                } else {
                                    SecureField("密码", text: $viewModel.password)
                                }
                            }
                            .textFieldStyle(.plain)
                            .textContentType(isLogin ? .password : .newPassword)
                            .foregroundColor(.textPrimary)
                            .font(GlassTypography.cnLovi(17, weight: .regular))

                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.surfaceGlass(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.24), lineWidth: 1)
                        )
                        
                        if let error = viewModel.error {
                            Text(error)
                                .font(GlassTypography.cnLovi(13, weight: .medium))
                                .foregroundColor(.statusError)
                                .multilineTextAlignment(.center)
                        }
                        
                        Button {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            Task {
                                await viewModel.authenticate(isLogin: isLogin)
                            }
                        } label: {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(isLogin ? "立即登录" : "创建账号")
                                    .font(GlassTypography.cnLovi(16, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
                        .disabled(viewModel.isLoading || viewModel.email.isEmpty || viewModel.password.isEmpty)

                        Text(isLogin ? "登录后会同步你的恢复进展与个性化建议。" : "创建后即可开启完整数据分析与科学解释。")
                            .font(GlassTypography.cnLovi(12, weight: .regular))
                            .foregroundColor(.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 20)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, metrics.horizontalPadding)
        }
        .sheet(isPresented: $showAuthInfoSheet) {
            AuthInfoSheet()
                .presentationDetents([.fraction(0.4), .large])
                .liquidGlassSheetChrome(cornerRadius: 28)
        }
    }
}

private struct AuthBrandMark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: 108, height: 108)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                )
                .shadow(color: Color.liquidGlassAccent.opacity(0.28), radius: 20, y: 10)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.22))
                .frame(width: 80, height: 80)

            Text("lóvi")
                .font(GlassTypography.loviTitle(34, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white.opacity(0.95), Color(hex: "#D7C9FF")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .kerning(-1.1)
        }
    }
}

private struct AuthInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("账号与隐私")
                        .font(GlassTypography.cnLovi(22, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .padding(10)
                            .background(Color.surfaceGlass(for: colorScheme))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                authBullet("你可以先登录，再逐步补充资料，不会一次要求填完。")
                authBullet("核心建议在本地可用，登录主要用于同步进度与跨设备恢复。")
                authBullet("后续你也可在设置里管理 HealthKit 与通知授权。")

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    private func authBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.liquidGlassAccent)
                .frame(width: 6, height: 6)
                .padding(.top, 7)
            Text(text)
                .font(GlassTypography.cnLovi(15, weight: .regular))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.surfaceGlass(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct AuthView_Previews: PreviewProvider {
    static var previews: some View {
        AuthView()
    }
}
