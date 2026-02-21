//
//  EssayListView.swift
//  EssayPublisher
//
//  最近 Essay 列表：拉取、查看、编辑、删除

import SwiftUI

struct EssayListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var essays: [Essay] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var deleteTarget: Essay?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar

                    ZStack {
                        if isLoading {
                            ProgressView()
                                .tint(Theme.textSecondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if essays.isEmpty {
                            Text("暂无 Essay")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            essayList
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: isLoading)
                    .animation(.easeInOut(duration: 0.3), value: essays.count)
                }
            }
            .navigationBarHidden(true)
            .task { await loadEssays() }
            .alert("确定删除？", isPresented: .init(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )) {
                Button("删除", role: .destructive) {
                    if let essay = deleteTarget {
                        Task { await deleteEssay(essay) }
                    }
                }
                Button("取消", role: .cancel) { deleteTarget = nil }
            } message: {
                if let essay = deleteTarget {
                    Text(essay.fileName)
                }
            }
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .frame(width: 44, height: 44)
            }
            .glassButton()

            Spacer()

            Text("Essays")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.vertical, 12)
    }

    // MARK: - 列表

    private var essayList: some View {
        List {
            ForEach(essays) { essay in
                NavigationLink {
                    EssayEditView(essay: essay) { updatedEssay in
                        if let idx = essays.firstIndex(where: { $0.fileName == updatedEssay.fileName }) {
                            essays[idx] = updatedEssay
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(essay.preview)
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)

                        Text(essay.formattedDate)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.background)
                .listRowSeparatorTint(Theme.divider)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTarget = essay
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await refreshEssays() }
    }

    // MARK: - 数据操作

    private func loadEssays() async {
        // 先显示缓存数据
        let cached = await EssayService.shared.getCachedEssays()
        if !cached.isEmpty {
            withAnimation {
                essays = Array(cached.prefix(10))
                isLoading = false
            }
        }

        // 后台静默刷新
        do {
            let all = try await EssayService.shared.fetchEssays(forceRefresh: true)
            withAnimation {
                essays = Array(all.prefix(10))
                isLoading = false
            }
        } catch {
            // 仅在无缓存时显示错误
            if essays.isEmpty {
                withAnimation {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func refreshEssays() async {
        do {
            let all = try await EssayService.shared.fetchEssays(forceRefresh: true)
            withAnimation {
                essays = Array(all.prefix(10))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteEssay(_ essay: Essay) async {
        do {
            try await EssayService.shared.deleteEssay(fileName: essay.fileName)
            withAnimation {
                essays.removeAll { $0.fileName == essay.fileName }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
