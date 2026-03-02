// antios5App.swift
// 应用入口

import SwiftUI
import UIKit
import UserNotifications

final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let route = (userInfo["route"] as? String)?.lowercased() ?? "dashboard"

        DispatchQueue.main.async {
            if route == "max" {
                NotificationCenter.default.post(name: .openMaxChat, object: nil)
                if let prompt = userInfo["prompt"] as? String,
                   !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    NotificationCenter.default.post(
                        name: .askMax,
                        object: nil,
                        userInfo: ["question": prompt]
                    )
                }
            } else {
                NotificationCenter.default.post(name: .openDashboard, object: nil)
            }
        }
        completionHandler()
    }
}

@main
struct antios5App: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var supabase = SupabaseManager.shared
    @StateObject private var appSettings = AppSettings()
    @StateObject private var themeManager = ThemeManager.shared
    
    init() {
        // 启动调试日志
        print("🚀 [App] AntiAnxiety iOS 启动")
        UNUserNotificationCenter.current().delegate = AppNotificationDelegate.shared

        configureTabBarAppearance()
        configureNavigationBarAppearance()
        
        if let apiBase = Bundle.main.infoDictionary?["APP_API_BASE_URL"] as? String {
            print("✅ [Config] APP_API_BASE_URL = \(apiBase)")
        } else {
            print("❌ [Config] APP_API_BASE_URL 未配置!")
        }

        if let aiBase = Bundle.main.infoDictionary?["OPENAI_API_BASE"] as? String {
            print("✅ [Config] OPENAI_API_BASE = \(aiBase)")
        } else {
            print("❌ [Config] OPENAI_API_BASE 未配置!")
        }

        if let aiModel = Bundle.main.infoDictionary?["OPENAI_MODEL"] as? String {
            print("✅ [Config] OPENAI_MODEL = \(aiModel)")
        } else {
            print("⚠️ [Config] OPENAI_MODEL 未配置，使用默认模型")
        }
        
        if let supabaseUrl = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String {
            print("✅ [Config] SUPABASE_URL = \(supabaseUrl)")
        } else {
            print("❌ [Config] SUPABASE_URL 未配置!")
        }
        
        if let accessToken = UserDefaults.standard.string(forKey: "supabase_access_token") {
            print("✅ [Auth] 已有 access_token: \(accessToken.prefix(20))...")
        } else {
            print("⚠️ [Auth] 未找到 access_token，需要登录")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.liquidGlassAccent)
                .environmentObject(supabase)
                .environmentObject(appSettings)
                .environmentObject(themeManager)
                .environment(\.locale, Locale(identifier: appSettings.language.localeIdentifier))
                .preferredColorScheme(themeManager.colorScheme)
                .task {
                    await supabase.refreshAppAPIBaseURL()
                    // 应用启动时检查会话
                    await supabase.checkSession()
                    await supabase.prewarmProactiveCare(language: appSettings.language.apiCode, force: false)
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await supabase.prewarmProactiveCare(language: appSettings.language.apiCode, force: false)
                    }
                }
        }
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = UIColor(Color.bgPrimary).withAlphaComponent(0.95)
        appearance.shadowColor = UIColor.black.withAlphaComponent(0.2)

        let normalAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(Color.textTertiary),
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold)
        ]
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(Color.liquidGlassAccent),
            .font: UIFont.systemFont(ofSize: 11, weight: .bold)
        ]

        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.iconColor = UIColor(Color.textTertiary)
        itemAppearance.normal.titleTextAttributes = normalAttributes
        itemAppearance.selected.iconColor = UIColor(Color.liquidGlassAccent)
        itemAppearance.selected.titleTextAttributes = selectedAttributes

        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.isTranslucent = true
        tabBar.tintColor = UIColor(Color.liquidGlassAccent)
        tabBar.unselectedItemTintColor = UIColor(Color.textTertiary)
        // Equalize spacing between all 5 items and keep left/right margins symmetric.
        tabBar.itemPositioning = .fill
        tabBar.itemSpacing = 0
        tabBar.itemWidth = 0
        // Hide system TabBar (we render a custom TabBar in ContentView).
        tabBar.isHidden = true
    }

    private func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.bgPrimary)
        appearance.shadowColor = UIColor.black.withAlphaComponent(0.2)
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(Color.textPrimary),
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(Color.textPrimary),
            .font: UIFont.systemFont(ofSize: 28, weight: .bold)
        ]

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = appearance
        navBar.scrollEdgeAppearance = appearance
        navBar.compactAppearance = appearance
        navBar.tintColor = UIColor(Color.liquidGlassAccent)
    }
}
