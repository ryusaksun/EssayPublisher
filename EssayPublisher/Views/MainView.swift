//
//  MainView.swift
//  EssayPublisher
//
//  主界面：顶栏 + 历史气泡列表 + 底部输入栏

import SwiftUI

struct MainView: View {
    @EnvironmentObject private var languageManager: LanguageManager
    @StateObject private var vm = ComposeViewModel()
    @State private var showSettings = false
    @State private var showEssayList = false
    @State private var hasInitialAutoScroll = false
    @State private var scrollWorkItem: DispatchWorkItem?
    @FocusState private var inputFocused: Bool

    var body: some View {
        Group {
            if vm.items.isEmpty {
                emptyState
            } else {
                chatList
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposeBarView(vm: vm, isFocused: $inputFocused)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                inputFocused = true
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showEssayList) {
            EssayListView()
        }
        .alert("main.publishFailed".localized, isPresented: $vm.showError) {
            Button("common.ok".localized) {}
        } message: {
            Text(vm.errorMessage ?? "common.unknownError".localized)
        }
        .onDisappear {
            scrollWorkItem?.cancel()
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .frame(width: 44, height: 44)
            }
            .glassButton()

            Spacer()

            Button {
                showEssayList = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .frame(width: 44, height: 44)
            }
            .glassButton()
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.vertical, 6)
    }

    // MARK: - 空状态（招呼语）

    private var greeting: String {
        let hour = Calendar.current.dateComponents(
            in: TimeZone(identifier: "Asia/Shanghai")!,
            from: Date()
        ).hour ?? 12
        switch hour {
        case 5..<12:  return "main.greeting.morning".localized
        case 12..<18: return "main.greeting.afternoon".localized
        case 18..<22: return "main.greeting.evening".localized
        default:      return "main.greeting.evening".localized
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            let name = AppConfig.displayName
            if name.isEmpty {
                Text(greeting)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
            } else {
                Text("\(greeting),")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
                Text(name)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 聊天列表

    private var chatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.items) { item in
                        ChatItemView(item: item)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                guard !hasInitialAutoScroll, !vm.items.isEmpty else { return }
                hasInitialAutoScroll = true
                scheduleScrollToBottom(proxy, animated: false)
            }
            .onChange(of: vm.items.count) {
                guard !vm.items.isEmpty else { return }
                let animated = hasInitialAutoScroll
                hasInitialAutoScroll = true
                scheduleScrollToBottom(proxy, animated: animated)
            }
        }
    }

    private func scheduleScrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        scrollWorkItem?.cancel()
        let targetID = vm.items.last?.id
        let workItem = DispatchWorkItem {
            guard let targetID else { return }
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(targetID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(targetID, anchor: .bottom)
            }
        }
        scrollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: workItem)
    }
}

// MARK: - Liquid Glass 按钮修饰器

extension View {
    @ViewBuilder
    func glassButton() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: .circle)
        } else {
            self.background(.ultraThinMaterial, in: Circle())
        }
    }

    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }
}
