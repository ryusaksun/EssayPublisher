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
        OAuthService.shared.signOut()
        AppConfig.resetToDefaults()
        githubUsername = ""
        owner = ""
        repo = ""
        branch = ""
        imageRepo = ""
        imageBranch = ""
        displayName = ""
    }

    func save() {
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
