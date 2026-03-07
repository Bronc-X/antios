// antios5App.swift
// 应用入口

import SwiftUI
import SwiftData
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
    @StateObject private var supabase = SupabaseManager.shared
    @StateObject private var appSettings = AppSettings()
    @StateObject private var themeManager = ThemeManager.shared
    
    init() {
        #if DEBUG
        print("🚀 [App] AntiAnxiety iOS 启动")
        #endif
        UNUserNotificationCenter.current().delegate = AppNotificationDelegate.shared

        configureTabBarAppearance()
        configureNavigationBarAppearance()

        #if DEBUG
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

        if let supabaseUrl = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
           let host = URL(string: supabaseUrl)?.host {
            print("✅ [Config] SUPABASE_HOST = \(host)")
        } else {
            print("❌ [Config] SUPABASE_URL 未配置!")
        }

        if UserDefaults.standard.string(forKey: "supabase_access_token") != nil {
            print("✅ [Auth] cached access_token present")
        } else {
            print("⚠️ [Auth] 未找到 access_token，需要登录")
        }
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Color(red: 0.184, green: 0.431, blue: 0.384))
                .environmentObject(supabase)
                .environmentObject(appSettings)
                .environmentObject(themeManager)
                .environment(\.locale, Locale(identifier: appSettings.language.localeIdentifier))
                .preferredColorScheme(themeManager.colorScheme)
                .task {
                    await supabase.refreshAppAPIBaseURL()
                    await supabase.checkSession()
                }
                .modelContainer(
                    for: [
                        A10LoopSnapshot.self,
                        A10ActionPlan.self,
                        A10CoachSession.self,
                        A10CoachMessage.self,
                        A10PreferenceRecord.self
                    ]
                )
        }
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        appearance.backgroundColor = UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 0.96)
        appearance.shadowColor = UIColor.black.withAlphaComponent(0.08)

        let normalAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(red: 0.34, green: 0.38, blue: 0.42, alpha: 1),
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold)
        ]
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(red: 0.18, green: 0.43, blue: 0.38, alpha: 1),
            .font: UIFont.systemFont(ofSize: 11, weight: .bold)
        ]

        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.iconColor = UIColor(red: 0.34, green: 0.38, blue: 0.42, alpha: 1)
        itemAppearance.normal.titleTextAttributes = normalAttributes
        itemAppearance.selected.iconColor = UIColor(red: 0.18, green: 0.43, blue: 0.38, alpha: 1)
        itemAppearance.selected.titleTextAttributes = selectedAttributes

        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.isTranslucent = true
        tabBar.tintColor = UIColor(red: 0.18, green: 0.43, blue: 0.38, alpha: 1)
        tabBar.unselectedItemTintColor = UIColor(red: 0.34, green: 0.38, blue: 0.42, alpha: 1)
        tabBar.itemPositioning = .fill
        tabBar.itemSpacing = 0
        tabBar.itemWidth = 0
        tabBar.isHidden = false
    }

    private func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)
        appearance.shadowColor = UIColor.black.withAlphaComponent(0.06)
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(red: 0.12, green: 0.14, blue: 0.16, alpha: 1),
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(red: 0.12, green: 0.14, blue: 0.16, alpha: 1),
            .font: UIFont.systemFont(ofSize: 28, weight: .bold)
        ]

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = appearance
        navBar.scrollEdgeAppearance = appearance
        navBar.compactAppearance = appearance
        navBar.tintColor = UIColor(red: 0.18, green: 0.43, blue: 0.38, alpha: 1)
    }
}
