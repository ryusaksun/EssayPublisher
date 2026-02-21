//
//  SettingsView.swift
//  EssayPublisher
//
//  Claude 风格设置页：目录式导航 + 手动顶栏

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarding_completed") private var onboardingCompleted = true
    @StateObject private var vm = SettingsViewModel()
    @State private var showSignOutConfirm = false

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
                            // 昵称
                            settingsGroup {
                                NavigationLink {
                                    DisplayNameSettingsView(vm: vm)
                                } label: {
                                    settingsRow(icon: "person", title: "昵称") {
                                        Text(vm.displayName.isEmpty ? "未设置" : vm.displayName)
                                            .font(.system(size: 15))
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                            }

                            // GitHub 账号
                            settingsGroup {
                                NavigationLink {
                                    AccountSettingsView(vm: vm)
                                } label: {
                                    settingsRow(icon: "person.circle", title: "GitHub 账号") {
                                        if !vm.githubUsername.isEmpty {
                                            Text(vm.githubUsername)
                                                .font(.system(size: 15))
                                                .foregroundStyle(Theme.textSecondary)
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

                            // 隐私政策
                            settingsGroup {
                                Link(destination: URL(string: "https://github.com/ryusaksun/astro_blog/blob/main/PRIVACY.md")!) {
                                    settingsRow(icon: "hand.raised", title: "隐私政策") {
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Theme.textSecondary.opacity(0.5))
                                    }
                                }
                            }

                            // 退出登录
                            settingsGroup {
                                Button {
                                    showSignOutConfirm = true
                                } label: {
                                    settingsRow(icon: "rectangle.portrait.and.arrow.right", title: "退出登录", tintColor: Theme.destructive) {}
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
            .alert("退出登录？", isPresented: $showSignOutConfirm) {
                Button("退出", role: .destructive) {
                    vm.signOut()
                    onboardingCompleted = false
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清除 GitHub 授权和所有配置")
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

// MARK: - 昵称配置页

struct DisplayNameSettingsView: View {
    @ObservedObject var vm: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                settingsSubTopBar(title: "昵称", dismiss: dismiss) {
                    vm.save()
                    dismiss()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("用于主页打招呼和发布成功的提示语")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)

                    TextField("你的名字", text: $vm.displayName)
                        .textFieldStyle(ThemeTextFieldStyle())
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.top, 16)

                Spacer()
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - GitHub 账号页

struct AccountSettingsView: View {
    @ObservedObject var vm: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                settingsSubTopBar(title: "GitHub 账号", dismiss: dismiss) {
                    dismiss()
                }

                VStack(spacing: 20) {
                    // 当前账号信息
                    if !vm.githubUsername.isEmpty {
                        HStack(spacing: 14) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(Theme.textSecondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(vm.githubUsername)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("已通过 OAuth 授权")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // 重新授权按钮
                    Button {
                        vm.authorizeGitHub()
                    } label: {
                        HStack(spacing: 8) {
                            if vm.isAuthorizing {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 15))
                            }
                            Text(vm.isAuthorizing ? "授权中..." : "重新授权")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.surfaceLight)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(vm.isAuthorizing)
                }
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.top, 16)

                Spacer()
            }
        }
        .navigationBarHidden(true)
        .alert("错误", isPresented: $vm.showError) {
            Button("好的") {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
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
                        Text("Image Branch")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        TextField("", text: $vm.imageBranch)
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
