//
//  SettingsViewModel.swift
//  EssayPublisher
//

import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {

    @Published var token = ""
    @Published var owner = ""
    @Published var repo = ""
    @Published var branch = ""
    @Published var imageRepo = ""
    @Published var imageBranch = ""
    @Published var cdnType = ""

    @Published var isVerifying = false
    @Published var verifiedUser: String?
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var showSaved = false

    func load() {
        token = AppConfig.githubToken
        owner = AppConfig.githubOwner
        repo = AppConfig.githubRepo
        branch = AppConfig.githubBranch
        imageRepo = AppConfig.imageRepo
        imageBranch = AppConfig.imageBranch
        cdnType = AppConfig.cdnType
    }

    func verifyToken() {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            errorMessage = "Token 不能为空"
            showError = true
            return
        }

        isVerifying = true
        verifiedUser = nil

        Task {
            do {
                let user = try await GitHubService.shared.verifyToken(clean)
                verifiedUser = user
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isVerifying = false
        }
    }

    func save() {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanToken.isEmpty {
            AppConfig.saveGitHubToken(cleanToken)
        } else {
            _ = AppConfig.deleteGitHubToken()
        }
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

    func resetDefaults() {
        AppConfig.resetToDefaults()
        _ = AppConfig.deleteGitHubToken()
        load()
    }
}
