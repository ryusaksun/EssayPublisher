//
//  EssayEditView.swift
//  EssayPublisher
//
//  Essay 编辑页：显示 rawContent，保存到 GitHub

import SwiftUI
import Foundation

struct EssayEditView: View {
    private enum EditorMode: String, CaseIterable, Identifiable {
        case raw = "编辑"
        case preview = "预览"

        var id: String { rawValue }
    }

    let essay: Essay
    var onSave: (Essay) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var content: String
    @State private var mode: EditorMode = .raw
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

                modePicker

                if mode == .raw {
                    TextEditor(text: $content)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, Theme.horizontalPadding)
                        .padding(.top, 8)
                } else {
                    MarkdownPreviewView(markdown: content)
                        .padding(.horizontal, Theme.horizontalPadding)
                        .padding(.top, 8)
                }
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
                        .padding(.horizontal, 16)
                        .frame(minWidth: 74)
                        .frame(height: 44)
                }
            }
            .glassCapsule()
            .disabled(isSaving || content == essay.rawContent)
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.vertical, 12)
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(EditorMode.allCases) { item in
                Button {
                    mode = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(mode == item ? Theme.textPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(mode == item ? Theme.surfaceLight : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(4)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.bottom, 8)
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

// MARK: - Markdown 预览

private struct MarkdownPreviewView: View {
    private enum Block: Equatable {
        case text(String)
        case image(URL)
    }

    private static let frontmatterRegex = try! NSRegularExpression(pattern: #"^---[\s\S]*?---\n*"#)
    private static let imageRegex = try! NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)]+)\)"#)

    let markdown: String

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(parsedBlocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let text):
                        renderedText(text)
                    case .image(let url):
                        renderedImage(url)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 16)
        }
    }

    private var parsedBlocks: [Block] {
        let bodyText = removeFrontmatter(from: markdown)
        guard !bodyText.isEmpty else { return [.text("（空内容）")] }

        let nsText = bodyText as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = Self.imageRegex.matches(in: bodyText, range: fullRange)

        if matches.isEmpty {
            return [.text(bodyText)]
        }

        var blocks: [Block] = []
        var current = 0

        for match in matches {
            let range = match.range
            if range.location > current {
                let prefix = nsText.substring(with: NSRange(location: current, length: range.location - current))
                if !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.text(prefix))
                }
            }

            if let urlRange = Range(match.range(at: 1), in: bodyText) {
                let urlString = String(bodyText[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: urlString) {
                    blocks.append(.image(url))
                }
            }

            current = range.location + range.length
        }

        if current < nsText.length {
            let suffix = nsText.substring(from: current)
            if !suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.text(suffix))
            }
        }

        return blocks.isEmpty ? [.text(bodyText)] : blocks
    }

    private func removeFrontmatter(from text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return Self.frontmatterRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    @ViewBuilder
    private func renderedText(_ text: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            Text(attributed)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
        }
    }

    private func renderedImage(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.surfaceLight)
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .overlay { ProgressView().tint(Theme.textSecondary) }
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            case .failure:
                VStack(alignment: .leading, spacing: 6) {
                    Text("图片加载失败")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text(url.absoluteString)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceLight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            @unknown default:
                EmptyView()
            }
        }
    }
}
