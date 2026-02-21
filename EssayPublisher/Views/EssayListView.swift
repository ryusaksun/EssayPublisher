//
//  EssayListView.swift
//  EssayPublisher
//
//  最近 Essay 列表：拉取、查看、编辑、删除

import SwiftUI

struct EssayListView: View {
    @Environment(\.dismiss) private var dismiss

    private struct EssayListRow: Identifiable, Equatable {
        let essay: Essay
        let preview: String
        let formattedDate: String

        var id: String { essay.fileName }
        var fileName: String { essay.fileName }

        init(essay: Essay) {
            self.essay = essay
            self.preview = essay.preview
            self.formattedDate = essay.formattedDate
        }
    }

    private struct OperationError: Identifiable {
        let id = UUID()
        let message: String
    }

    private struct RefreshRequest {
        var forceRefresh: Bool
        var showLoadingIfNeeded: Bool
        var showFailureAlertWhenHasRows: Bool
    }

    private enum ViewState: Equatable {
        case loading
        case content
        case empty
        case error(String)
    }

    @State private var rows: [EssayListRow] = []
    @State private var viewState: ViewState = .loading
    @State private var deleteTarget: Essay?
    @State private var deletingFileNames: Set<String> = []
    @State private var operationError: OperationError?
    @State private var didLoad = false
    @State private var isSyncing = false
    @State private var queuedRefreshRequest: RefreshRequest?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar

                    ZStack {
                        if viewState == .loading {
                            ProgressView()
                                .tint(Theme.textSecondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if case .error(let error) = viewState {
                            Text(error)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if viewState == .empty {
                            Text("essayList.empty".localized)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            essayList
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .task {
                guard !didLoad else { return }
                didLoad = true
                await loadEssays()
            }
            .onDisappear {
                queuedRefreshRequest = nil
            }
            .alert("essayList.deleteConfirm".localized, isPresented: .init(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )) {
                Button("common.delete".localized, role: .destructive) {
                    if let essay = deleteTarget {
                        Task { await deleteEssay(essay) }
                    }
                }
                .disabled(deleteTarget.map { deletingFileNames.contains($0.fileName) } ?? false)
                Button("common.cancel".localized, role: .cancel) { deleteTarget = nil }
            } message: {
                if let essay = deleteTarget {
                    Text(essay.fileName)
                }
            }
            .alert("essayList.operationFailed".localized, isPresented: .init(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            ), presenting: operationError) { _ in
                Button("common.ok".localized, role: .cancel) {}
            } message: { err in
                Text(err.message)
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

            Text("essayList.title".localized)
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
            ForEach(rows) { row in
                NavigationLink {
                    EssayEditView(essay: row.essay) { updatedEssay in
                        if let idx = rows.firstIndex(where: { $0.fileName == updatedEssay.fileName }) {
                            rows[idx] = EssayListRow(essay: updatedEssay)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.preview)
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)

                            Text(row.formattedDate)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                        }

                        Spacer(minLength: 8)

                        if deletingFileNames.contains(row.fileName) {
                            ProgressView()
                                .tint(Theme.textSecondary)
                                .scaleEffect(0.9)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .disabled(deletingFileNames.contains(row.fileName))
                .listRowBackground(Theme.background)
                .listRowSeparatorTint(Theme.divider)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        deleteTarget = row.essay
                    } label: {
                        Label("common.delete".localized, systemImage: "trash")
                    }
                    .tint(Theme.destructive)
                    .disabled(deletingFileNames.contains(row.fileName))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await refreshEssays(forceRefresh: true) }
    }

    // MARK: - 数据操作

    private func loadEssays() async {
        let cached = await EssayService.shared.getCachedRecentEssays(limit: 10)
        if !cached.isEmpty {
            applyEssays(Array(cached.prefix(10)), animated: false)
        }

        await refreshEssays(
            forceRefresh: false,
            showLoadingIfNeeded: cached.isEmpty,
            showFailureAlertWhenHasRows: false
        )
    }

    private func refreshEssays(
        forceRefresh: Bool = true,
        showLoadingIfNeeded: Bool = false,
        showFailureAlertWhenHasRows: Bool = true
    ) async {
        if Task.isCancelled { return }
        if isSyncing {
            mergeQueuedRefresh(
                forceRefresh: forceRefresh,
                showLoadingIfNeeded: showLoadingIfNeeded,
                showFailureAlertWhenHasRows: showFailureAlertWhenHasRows
            )
            return
        }
        if showLoadingIfNeeded && rows.isEmpty {
            viewState = .loading
        }

        isSyncing = true
        defer {
            isSyncing = false
        }

        if Task.isCancelled { return }
        do {
            let recent = try await EssayService.shared.fetchRecentEssays(limit: 10, forceRefresh: forceRefresh)
            if Task.isCancelled { return }
            applyEssays(recent, animated: !rows.isEmpty)
        } catch {
            if Task.isCancelled { return }
            if rows.isEmpty {
                viewState = .error(error.localizedDescription)
            } else if showFailureAlertWhenHasRows {
                operationError = OperationError(message: error.localizedDescription)
            }
        }

        if let queued = queuedRefreshRequest {
            queuedRefreshRequest = nil
            await refreshEssays(
                forceRefresh: queued.forceRefresh,
                showLoadingIfNeeded: queued.showLoadingIfNeeded,
                showFailureAlertWhenHasRows: queued.showFailureAlertWhenHasRows
            )
        }
    }

    private func deleteEssay(_ essay: Essay) async {
        guard !deletingFileNames.contains(essay.fileName) else { return }
        deleteTarget = nil

        deletingFileNames.insert(essay.fileName)

        do {
            try await EssayService.shared.deleteEssay(fileName: essay.fileName)
            withAnimation(.easeOut(duration: 0.2)) {
                rows.removeAll { $0.fileName == essay.fileName }
                viewState = rows.isEmpty ? .empty : .content
            }
        } catch {
            if rows.isEmpty {
                viewState = .error(error.localizedDescription)
            } else {
                operationError = OperationError(message: error.localizedDescription)
            }
        }

        deletingFileNames.remove(essay.fileName)
    }

    private func applyEssays(_ newValue: [Essay], animated: Bool) {
        let newRows = newValue.map { EssayListRow(essay: $0) }
        let shouldUpdate = rows != newRows
        guard shouldUpdate else {
            viewState = rows.isEmpty ? .empty : .content
            return
        }

        let apply = {
            rows = newRows
            viewState = newRows.isEmpty ? .empty : .content
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.2)) { apply() }
        } else {
            apply()
        }
    }

    private func mergeQueuedRefresh(
        forceRefresh: Bool,
        showLoadingIfNeeded: Bool,
        showFailureAlertWhenHasRows: Bool
    ) {
        if var queued = queuedRefreshRequest {
            queued.forceRefresh = queued.forceRefresh || forceRefresh
            queued.showLoadingIfNeeded = queued.showLoadingIfNeeded || showLoadingIfNeeded
            queued.showFailureAlertWhenHasRows = queued.showFailureAlertWhenHasRows || showFailureAlertWhenHasRows
            queuedRefreshRequest = queued
        } else {
            queuedRefreshRequest = RefreshRequest(
                forceRefresh: forceRefresh,
                showLoadingIfNeeded: showLoadingIfNeeded,
                showFailureAlertWhenHasRows: showFailureAlertWhenHasRows
            )
        }
    }
}
