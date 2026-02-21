//
//  EssayEditView.swift
//  EssayPublisher
//
//  Essay 编辑页：显示 rawContent，保存到 GitHub

import SwiftUI

struct EssayEditView: View {
    let essay: Essay
    var onSave: (Essay) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var content: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    init(essay: Essay, onSave: @escaping (Essay) -> Void) {
        self.essay = essay
        self.onSave = onSave
        _content = State(initialValue: essay.rawContent)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                TextEditor(text: $content)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, Theme.horizontalPadding)
                    .padding(.top, 8)
            }
        }
        .navigationBarHidden(true)
        .alert("保存失败", isPresented: $showError) {
            Button("好的") {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .frame(width: 44, height: 44)
            }
            .glassButton()

            Text(essay.title ?? essay.fileName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    ProgressView()
                        .tint(Theme.textSecondary)
                        .frame(width: 56, height: 44)
                } else {
                    Text("保存")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(content == essay.rawContent ? Theme.textSecondary : Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                }
            }
            .glassCapsule()
            .disabled(isSaving || content == essay.rawContent)
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.vertical, 12)
    }

    // MARK: - 保存

    private func save() async {
        isSaving = true
        do {
            try await EssayService.shared.updateEssay(fileName: essay.fileName, newContent: content)
            if let updated = EssayParser.parse(rawContent: content, fileName: essay.fileName) {
                onSave(updated)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isSaving = false
    }
}
