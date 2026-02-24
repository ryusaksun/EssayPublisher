//
//  SettingsViewModel.swift
//  EssayPublisher
//

import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {

    @Published var displayName = ""
    @Published var githubUsername = ""
    @Published var owner = ""
    @Published var repo = ""
    @Published var branch = ""
    @Published var imageRepo = ""
    @Published var imageBranch = ""
    @Published var cdnType = ""

    @Published var isAuthorizing = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var showSaved = false

    func load() {
        if DemoManager.shared.isDemoMode {
            displayName = DemoManager.demoDisplayName
            githubUsername = DemoManager.demoUsername
            owner = DemoManager.demoOwner
            repo = DemoManager.demoRepo
            branch = DemoManager.demoBranch
            imageRepo = DemoManager.demoImageRepo
            imageBranch = DemoManager.demoBranch
            cdnType = "jsdelivr"
            return
        }
        displayName = AppConfig.displayName
        githubUsername = AppConfig.githubUsername
        owner = AppConfig.githubOwner
        repo = AppConfig.githubRepo
        branch = AppConfig.githubBranch
        imageRepo = AppConfig.imageRepo
        imageBranch = AppConfig.imageBranch
        cdnType = AppConfig.cdnType
    }

    func authorizeGitHub() {
        guard !isAuthorizing else { return }
        isAuthorizing = true
        Task {
            do {
                let result = try await OAuthService.shared.authorize()
                githubUsername = result.username
            } catch let error as OAuthError where error == .userCancelled {
                // 用户取消，不做处理
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isAuthorizing = false
        }
    }

    func signOut() {
        if DemoManager.shared.isDemoMode {
            DemoManager.shared.exitDemo()
            return
        }
        OAuthService.shared.signOut()
        AppConfig.resetToDefaults()
        displayName = ""
        githubUsername = ""
        owner = ""
        repo = ""
        branch = ""
        imageRepo = ""
        imageBranch = ""
        cdnType = ""
    }

    func save() {
        // Demo 模式下不真正保存
        if DemoManager.shared.isDemoMode {
            showSaved = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        AppConfig.saveDisplayName(displayName)
        AppConfig.saveRepoConfig(
            owner: owner.trimmingCharacters(in: .whitespacesAndNewlines),
            repo: repo.trimmingCharacters(in: .whitespacesAndNewlines),
            branch: branch.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        AppConfig.saveImageConfig(
            imageRepo: imageRepo.trimmingCharacters(in: .whitespacesAndNewlines),
            cdnType: cdnType,
            imageBranch: imageBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        showSaved = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
