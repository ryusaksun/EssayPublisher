//
//  EssayPublisherApp.swift
//  EssayPublisher
//

import SwiftUI

@main
struct EssayPublisherApp: App {
    @StateObject private var languageManager = LanguageManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(languageManager)
                .preferredColorScheme(.dark)
        }
    }
}

/// 根据配置状态切换主界面 / 引导页
struct RootView: View {
    @AppStorage("onboarding_completed") private var onboardingCompleted = false
    @ObservedObject private var demoManager = DemoManager.shared

    var body: some View {
        if demoManager.isDemoMode {
            MainView()
        } else if onboardingCompleted && AppConfig.isGitHubConfigured {
            MainView()
        } else {
            OnboardingView()
                .onAppear {
                    // Token 丢失时自动重置引导状态
                    if onboardingCompleted && !AppConfig.isGitHubConfigured {
                        onboardingCompleted = false
                    }
                }
        }
    }
}
