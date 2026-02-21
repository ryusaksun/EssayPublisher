//
//  EssayPublisherApp.swift
//  EssayPublisher
//

import SwiftUI

@main
struct EssayPublisherApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

/// 根据配置状态切换主界面 / 引导页
struct RootView: View {
    @AppStorage("onboarding_completed") private var onboardingCompleted = false

    var body: some View {
        if onboardingCompleted && AppConfig.isGitHubConfigured {
            MainView()
        } else {
            OnboardingView()
        }
    }
}
