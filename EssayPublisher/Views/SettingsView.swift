//
//  SettingsView.swift
//  EssayPublisher
//
//  Claude 风格设置页：目录式导航 + 手动顶栏

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = SettingsViewModel()
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // 手动顶栏（避免 NavigationBar 液态玻璃包裹）
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                                .frame(width: 44, height: 44)
                        }
                        .glassButton()

                        Spacer()

                        Text("Settings")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)

                        Spacer()

                        // 占位保持居中
                        Color.clear.frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, Theme.horizontalPadding)
                    .padding(.vertical, 12)

                    ScrollView {
                        VStack(spacing: 24) {
                            // GitHub Token
                            settingsGroup {
                                NavigationLink {
                                    TokenSettingsView(vm: vm)
                                } label: {
                                    settingsRow(icon: "key", title: "GitHub Token") {
                                        if vm.verifiedUser != nil {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                                .font(.system(size: 16))
                                        }
                                    }
                                }
                            }

                            // 仓库配置
                            settingsGroup {
                                NavigationLink {
                                    RepoSettingsView(vm: vm)
                                } label: {
                                    settingsRow(icon: "book.closed", title: "内容仓库") {
                                        Text(vm.repo.isEmpty ? "" : vm.repo)
                                            .font(.system(size: 15))
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }

                                rowDivider()

                                NavigationLink {
                                    ImageRepoSettingsView(vm: vm)
                                } label: {
                                    settingsRow(icon: "photo.on.rectangle", title: "图床仓库") {
                                        Text(vm.imageRepo.isEmpty ? "" : vm.imageRepo)
                                            .font(.system(size: 15))
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                            }

                            // 重置
                            settingsGroup {
                                Button {
                                    showResetConfirm = true
                                } label: {
                                    settingsRow(icon: "arrow.counterclockwise", title: "重置所有配置", tintColor: Theme.destructive) {}
                                }
                            }
                        }
                        .padding(.horizontal, Theme.horizontalPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear { vm.load() }
            .alert("重置所有配置？", isPresented: $showResetConfirm) {
                Button("重置", role: .destructive) { vm.resetDefaults() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("Token 和所有仓库配置将被清除")
            }
        }
    }

    // MARK: - 组件

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func settingsRow(
        icon: String,
        title: String,
        tintColor: Color = Theme.textPrimary,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tintColor)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(tintColor)
            Spacer()
            trailing()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary.opacity(0.5))
        }
        .padding(.vertical, 15)
    }

    private func rowDivider() -> some View {
        Divider()
            .background(Theme.divider)
            .padding(.leading, 52)
    }
}

// MARK: - Token 配置页

struct TokenSettingsView: View {
    @ObservedObject var vm: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                settingsSubTopBar(title: "GitHub Token", dismiss: dismiss) {
                    let clean = vm.token.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty { AppConfig.saveGitHubToken(clean) }
                    dismiss()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("需要一个具有 repo 权限的 Personal Access Token")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)

                    SecureField("ghp_...", text: $vm.token)
                        .textFieldStyle(ThemeTextFieldStyle())
                        .textContentType(.password)
                        .autocorrectionDisabled()

                    HStack(spacing: 12) {
                        Button {
                            vm.verifyToken()
                        } label: {
                            HStack(spacing: 6) {
                                if vm.isVerifying {
                                    ProgressView().tint(.white).scaleEffect(0.8)
                                }
                                Text(vm.isVerifying ? "验证中..." : "验证 Token")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Theme.surfaceLight)
                            .clipShape(Capsule())
                        }
                        .disabled(vm.isVerifying)

                        if let user = vm.verifiedUser {
                            Label(user, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.top, 16)

                Spacer()
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - 内容仓库配置页

struct RepoSettingsView: View {
    @ObservedObject var vm: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                settingsSubTopBar(title: "内容仓库", dismiss: dismiss) {
                    vm.save()
                    dismiss()
                }

                VStack(spacing: 0) {
                    fieldRow(title: "Owner", text: $vm.owner)
                    rowDivider()
                    fieldRow(title: "Repo", text: $vm.repo)
                    rowDivider()
                    fieldRow(title: "Branch", text: $vm.branch)
                }
                .padding(.horizontal, 16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.top, 16)

                Spacer()
            }
        }
        .navigationBarHidden(true)
    }

    private func fieldRow(title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 70, alignment: .leading)
            TextField("", text: text)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .tint(.white)
        }
        .padding(.vertical, 14)
    }

    private func rowDivider() -> some View {
        Divider().background(Theme.divider)
    }
}

// MARK: - 图床仓库配置页

struct ImageRepoSettingsView: View {
    @ObservedObject var vm: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                settingsSubTopBar(title: "图床仓库", dismiss: dismiss) {
                    vm.save()
                    dismiss()
                }

                VStack(spacing: 0) {
                    HStack {
                        Text("Image Repo")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        TextField("", text: $vm.imageRepo)
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .tint(.white)
                    }
                    .padding(.vertical, 14)

                    Divider().background(Theme.divider)

                    HStack {
                        Text("CDN")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Picker("", selection: $vm.cdnType) {
                            Text("jsDelivr").tag("jsdelivr")
                            Text("Statically").tag("statically")
                            Text("Raw").tag("raw")
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.textSecondary)
                    }
                    .padding(.vertical, 10)
                }
                .padding(.horizontal, 16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.top, 16)

                Spacer()
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - 子页面顶栏

private func settingsSubTopBar(title: String, dismiss: DismissAction, onSave: @escaping () -> Void) -> some View {
    HStack {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .frame(width: 44, height: 44)
        }
        .glassButton()

        Text(title)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)

        Button(action: onSave) {
            Text("保存")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 44)
        }
        .glassCapsule()
    }
    .padding(.horizontal, Theme.horizontalPadding)
    .padding(.vertical, 12)
}

// MARK: - 自定义 TextField 样式

struct ThemeTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 15))
            .foregroundStyle(Theme.textPrimary)
            .padding(10)
            .background(Theme.surfaceLight)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .tint(.white)
    }
}
