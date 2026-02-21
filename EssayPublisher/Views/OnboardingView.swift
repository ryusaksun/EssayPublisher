//
//  OnboardingView.swift
//  EssayPublisher
//
//  首次启动引导：欢迎 → GitHub 登录 → 仓库配置

import SwiftUI

struct OnboardingView: View {
    @AppStorage("onboarding_completed") private var onboardingCompleted = false

    @State private var step = 0
    @State private var displayName = ""
    @State private var owner = ""
    @State private var repo = ""
    @State private var branch = "main"
    @State private var imageRepo = ""
    @State private var imageBranch = "main"

    @State private var isAuthorizing = false
    @State private var authorizedUser: String?
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                switch step {
                case 0: welcomeStep
                case 1: loginStep
                case 2: repoStep
                default: EmptyView()
                }

                Spacer()

                // 导航按钮
                HStack(spacing: 16) {
                    if step > 0 && step != 1 {
                        Button("common.back".localized) {
                            withAnimation { step -= 1 }
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer()

                    if step != 1 {
                        Button {
                            advanceStep()
                        } label: {
                            Text(step == 2 ? "onboarding.finish".localized : "onboarding.next".localized)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 12)
                                .background(canAdvance ? Theme.accent : Theme.surfaceLight)
                                .clipShape(Capsule())
                        }
                        .disabled(!canAdvance)
                    }
                }
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.bottom, 32)
            }
        }
        .alert("common.error".localized, isPresented: $showError) {
            Button("common.ok".localized) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "pencil.and.outline")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)

            Text("Essay Publisher")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("onboarding.subtitle".localized)
                .font(.system(size: 17))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var loginStep: some View {
        VStack(spacing: 24) {
            Text("onboarding.connectGitHub".localized)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("onboarding.connectGitHub.subtitle".localized)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.horizontalPadding)

            if let user = authorizedUser {
                // 授权成功
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)

                    Text(String(format: "onboarding.loggedIn".localized, user))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.green)
                }
                .padding(.top, 8)

                Button {
                    withAnimation { step = 2 }
                } label: {
                    Text("onboarding.continue".localized)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 12)
                        .background(Theme.accent)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            } else {
                // 登录按钮
                Button {
                    startOAuth()
                } label: {
                    HStack(spacing: 10) {
                        if isAuthorizing {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.9)
                        } else {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 18))
                        }
                        Text(isAuthorizing ? "onboarding.authorizing".localized : "onboarding.loginWithGitHub".localized)
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isAuthorizing)
                .padding(.horizontal, Theme.horizontalPadding)
            }
        }
    }

    private var repoStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("onboarding.basicConfig".localized)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("onboarding.basicConfig.subtitle".localized)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 12) {
                LabeledOnboardingField("onboarding.displayName".localized, text: $displayName, placeholder: "onboarding.displayName.placeholder".localized)
                LabeledOnboardingField("Owner", text: $owner)
                LabeledOnboardingField("Repo", text: $repo)
                LabeledOnboardingField("Branch", text: $branch)
                LabeledOnboardingField("Image Repo", text: $imageRepo)
                LabeledOnboardingField("Image Branch", text: $imageBranch)
            }
        }
        .padding(.horizontal, Theme.horizontalPadding)
    }

    // MARK: - 逻辑

    private var canAdvance: Bool {
        switch step {
        case 0: return true
        case 2: return !owner.isEmpty && !repo.isEmpty && !branch.isEmpty
        default: return false
        }
    }

    private func advanceStep() {
        switch step {
        case 0:
            withAnimation { step = 1 }

        case 2:
            // 保存配置
            AppConfig.saveDisplayName(displayName)
            AppConfig.saveRepoConfig(
                owner: owner.trimmingCharacters(in: .whitespacesAndNewlines),
                repo: repo.trimmingCharacters(in: .whitespacesAndNewlines),
                branch: branch.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            AppConfig.saveImageConfig(
                imageRepo: imageRepo.trimmingCharacters(in: .whitespacesAndNewlines),
                cdnType: "jsdelivr",
                imageBranch: imageBranch.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onboardingCompleted = true

        default:
            break
        }
    }

    private func startOAuth() {
        guard !isAuthorizing else { return }
        isAuthorizing = true
        Task {
            do {
                let result = try await OAuthService.shared.authorize()
                authorizedUser = result.username
                // 用 GitHub 用户名预填
                if displayName.isEmpty { displayName = result.username }
                if owner.isEmpty { owner = result.username }
            } catch let error as OAuthError where error == .userCancelled {
                // 用户取消，不显示错误
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isAuthorizing = false
        }
    }
}

// 让 OAuthError 可比较
extension OAuthError: Equatable {
    static func == (lhs: OAuthError, rhs: OAuthError) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}

// MARK: - Onboarding 输入框

private struct LabeledOnboardingField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    init(_ label: String, text: Binding<String>, placeholder: String? = nil) {
        self.label = label
        self.placeholder = placeholder ?? label
        self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(ThemeTextFieldStyle())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }
}
