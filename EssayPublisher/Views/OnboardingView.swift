//
//  OnboardingView.swift
//  EssayPublisher
//
//  首次启动引导：欢迎 → Token → 仓库配置

import SwiftUI

struct OnboardingView: View {
    @AppStorage("onboarding_completed") private var onboardingCompleted = false

    @State private var step = 0
    @State private var token = ""
    @State private var owner = "ryusaksun"
    @State private var repo = "astro_blog"
    @State private var branch = "main"
    @State private var imageRepo = "picx-images-hosting"

    @State private var isVerifying = false
    @State private var verifiedUser: String?
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                switch step {
                case 0: welcomeStep
                case 1: tokenStep
                case 2: repoStep
                default: EmptyView()
                }

                Spacer()

                // 导航按钮
                HStack(spacing: 16) {
                    if step > 0 {
                        Button("上一步") {
                            withAnimation { step -= 1 }
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer()

                    Button {
                        advanceStep()
                    } label: {
                        Text(step == 2 ? "完成" : "下一步")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(canAdvance ? Theme.accent : Theme.surfaceLight)
                            .clipShape(Capsule())
                    }
                    .disabled(!canAdvance)
                }
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.bottom, 32)
            }
        }
        .alert("错误", isPresented: $showError) {
            Button("好的") {}
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

            Text("将想法发布到你的 Astro 博客")
                .font(.system(size: 17))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var tokenStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GitHub Token")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("需要一个具有 repo 权限的 Personal Access Token")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)

            SecureField("ghp_...", text: $token)
                .textFieldStyle(ThemeTextFieldStyle())
                .textContentType(.password)
                .autocorrectionDisabled()

            if let user = verifiedUser {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("已验证: \(user)")
                        .foregroundStyle(.green)
                }
                .font(.system(size: 14))
            }
        }
        .padding(.horizontal, Theme.horizontalPadding)
    }

    private var repoStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("仓库配置")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("配置博客内容仓库和图床仓库")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 12) {
                LabeledOnboardingField("Owner", text: $owner)
                LabeledOnboardingField("Repo", text: $repo)
                LabeledOnboardingField("Branch", text: $branch)
                LabeledOnboardingField("Image Repo", text: $imageRepo)
            }
        }
        .padding(.horizontal, Theme.horizontalPadding)
    }

    // MARK: - 逻辑

    private var canAdvance: Bool {
        switch step {
        case 0: return true
        case 1: return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 2: return !owner.isEmpty && !repo.isEmpty && !branch.isEmpty
        default: return false
        }
    }

    private func advanceStep() {
        switch step {
        case 0:
            withAnimation { step = 1 }

        case 1:
            // 验证 Token
            let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
            isVerifying = true
            Task {
                do {
                    let user = try await GitHubService.shared.verifyToken(clean)
                    verifiedUser = user
                    AppConfig.saveGitHubToken(clean)
                    withAnimation { step = 2 }
                } catch {
                    errorMessage = "Token 验证失败: \(error.localizedDescription)"
                    showError = true
                }
                isVerifying = false
            }

        case 2:
            // 保存配置
            AppConfig.saveRepoConfig(
                owner: owner.trimmingCharacters(in: .whitespacesAndNewlines),
                repo: repo.trimmingCharacters(in: .whitespacesAndNewlines),
                branch: branch.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            AppConfig.saveImageConfig(
                imageRepo: imageRepo.trimmingCharacters(in: .whitespacesAndNewlines),
                cdnType: "jsdelivr"
            )
            onboardingCompleted = true

        default:
            break
        }
    }
}

// MARK: - Onboarding 输入框

private struct LabeledOnboardingField: View {
    let label: String
    @Binding var text: String

    init(_ label: String, text: Binding<String>) {
        self.label = label
        self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            TextField(label, text: $text)
                .textFieldStyle(ThemeTextFieldStyle())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }
}
