//
//  ComposeViewModel.swift
//  EssayPublisher
//
//  发布逻辑：即时显示气泡 + 后台异步发布 + 成功回复
//  历史记录：纯本地存储，不从 GitHub 拉取

import SwiftUI
import PhotosUI

// MARK: - 聊天项模型

enum ChatItem: Identifiable {
    case essay(EssayItem)
    case reply(PublishReply)

    var id: String {
        switch self {
        case .essay(let e): return "essay-\(e.essay.id)"
        case .reply(let r): return "reply-\(r.id)"
        }
    }
}

struct EssayItem {
    let essay: Essay
    var isPending: Bool
    var localImages: [UIImage]  // 本地缩略图（发送时保留，持久化后为空）
}

struct PublishReply: Codable {
    let id: String
    let filePath: String
    let date: Date
    let linkedEssayId: String
}

// MARK: - ViewModel

@MainActor
final class ComposeViewModel: ObservableObject {

    // MARK: - 输入状态

    @Published var text = ""
    @Published var selectedItems: [PhotosPickerItem] = []
    @Published var attachedImages: [AttachedImage] = []

    // MARK: - 发布状态

    @Published var isPublishing = false
    @Published var errorMessage: String?
    @Published var showError = false

    // MARK: - 聊天列表

    @Published var items: [ChatItem] = []

    // MARK: - 本地持久化

    private static let localHistoryURL: URL? = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("local_history_v2.json")
    }()

    init() {
        items = []
    }

    // MARK: - 图片选取

    func loadSelectedImages() {
        Task {
            var images: [AttachedImage] = []
            for item in selectedItems {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    images.append(AttachedImage(data: data, image: UIImage(data: data)))
                }
            }
            attachedImages = images
        }
    }

    func addCameraImage(_ uiImage: UIImage) {
        guard let data = uiImage.jpegData(compressionQuality: 0.9) else { return }
        attachedImages.append(AttachedImage(data: data, image: uiImage))
    }

    func removeImage(at index: Int) {
        guard attachedImages.indices.contains(index) else { return }
        attachedImages.remove(at: index)
        if selectedItems.indices.contains(index) {
            selectedItems.remove(at: index)
        }
    }

    // MARK: - 发布

    var canPublish: Bool {
        !isPublishing && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedImages.isEmpty)
    }

    func publish() {
        guard canPublish else { return }

        // 1. 捕获当前输入
        let currentText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentImages = attachedImages

        // 2. 收集本地图片
        let localImages = currentImages.compactMap { $0.image }

        // 3. 构造临时 Essay 并立即插入气泡
        let now = Date()
        let tempFileName = "pending-\(UUID().uuidString).md"
        let tempEssay = Essay(
            fileName: tempFileName,
            title: nil,
            pubDate: now,
            content: currentText,
            rawContent: currentText
        )
        let essayItem = EssayItem(essay: tempEssay, isPending: true, localImages: localImages)
        items.append(.essay(essayItem))

        // 4. 立即清空输入
        text = ""
        selectedItems = []
        attachedImages = []
        isPublishing = true

        // 5. 后台异步发布
        Task {
            await doPublish(text: currentText, images: currentImages, tempFileName: tempFileName)
        }
    }

    private func doPublish(text: String, images: [AttachedImage], tempFileName: String) async {
        do {
            var markdownBody = text

            // 上传图片
            if !images.isEmpty {
                var imageURLs: [String] = []
                for img in images {
                    let result = try await ImageService.shared.uploadImage(img.data)
                    imageURLs.append(result.url)
                }
                let imageMarkdown = imageURLs.map { "![](\($0))" }.joined(separator: "\n\n")
                if markdownBody.isEmpty {
                    markdownBody = imageMarkdown
                } else {
                    markdownBody += "\n\n" + imageMarkdown
                }
            }

            // 组装 frontmatter
            var metadata = Metadata()
            metadata.reset(for: .essay)
            let fullContent = metadata.toFrontmatter(for: .essay) + markdownBody

            // 发布到 GitHub
            let result = try await GitHubService.shared.publishContent(
                type: .essay, metadata: metadata, content: fullContent)

            // 用真实数据替换临时 essay（保留本地缩略图）
            let fileName = result.filePath.components(separatedBy: "/").last ?? ""
            if let realEssay = EssayParser.parse(rawContent: fullContent, fileName: fileName) {
                if let idx = items.firstIndex(where: {
                    if case .essay(let e) = $0 { return e.essay.fileName == tempFileName }
                    return false
                }) {
                    // 保留缩略图，标记为非 pending
                    if case .essay(let oldItem) = items[idx] {
                        items[idx] = .essay(EssayItem(
                            essay: realEssay,
                            isPending: false,
                            localImages: oldItem.localImages
                        ))
                    }
                }

                // 追加"已发布"回复
                let reply = PublishReply(
                    id: UUID().uuidString,
                    filePath: result.filePath,
                    date: Date(),
                    linkedEssayId: fileName
                )
                items.append(.reply(reply))
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)

        } catch {
            errorMessage = error.localizedDescription
            showError = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }

        isPublishing = false
    }

    // MARK: - 清空历史

    func clearHistory() {
        items = []
        if let url = Self.localHistoryURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - 本地存储

    private struct LocalItem: Codable {
        let type: String
        let fileName: String?
        let rawContent: String?
        let replyId: String?
        let filePath: String?
        let date: Date?
        let linkedEssayId: String?
    }

    private static func loadLocalHistory() -> [ChatItem] {
        guard let url = localHistoryURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([LocalItem].self, from: data) else {
            return []
        }
        return entries.compactMap { entry in
            if entry.type == "essay",
               let fn = entry.fileName,
               let raw = entry.rawContent,
               let essay = EssayParser.parse(rawContent: raw, fileName: fn) {
                return .essay(EssayItem(essay: essay, isPending: false, localImages: []))
            } else if entry.type == "reply",
                      let id = entry.replyId,
                      let fp = entry.filePath,
                      let d = entry.date,
                      let lid = entry.linkedEssayId {
                return .reply(PublishReply(id: id, filePath: fp, date: d, linkedEssayId: lid))
            }
            return nil
        }
    }

    private static func saveLocalHistory(_ items: [ChatItem]) {
        guard let url = localHistoryURL else { return }
        let entries: [LocalItem] = items.compactMap { item in
            switch item {
            case .essay(let e):
                // 不保存 pending 状态（未完成发布的）的临时 essay
                if e.isPending { return nil }
                return LocalItem(type: "essay", fileName: e.essay.fileName, rawContent: e.essay.rawContent,
                                 replyId: nil, filePath: nil, date: nil, linkedEssayId: nil)
            case .reply(let r):
                return LocalItem(type: "reply", fileName: nil, rawContent: nil,
                                 replyId: r.id, filePath: r.filePath, date: r.date, linkedEssayId: r.linkedEssayId)
            }
        }
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url)
        }
    }
}

// MARK: - 附件图片

struct AttachedImage: Identifiable {
    let id = UUID()
    let data: Data
    let image: UIImage?
}
