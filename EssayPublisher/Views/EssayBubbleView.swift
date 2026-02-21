//
//  EssayBubbleView.swift
//  EssayPublisher
//
//  聊天气泡：用户消息（右对齐黑色）+ 系统回复（左对齐深灰）

import SwiftUI

// MARK: - 聊天项视图

struct ChatItemView: View {
    let item: ChatItem

    var body: some View {
        switch item {
        case .essay(let essayItem):
            EssayBubbleView(item: essayItem)
        case .reply(let reply):
            ReplyBubbleView(reply: reply)
        }
    }
}

// MARK: - 用户消息气泡（右对齐，纯黑）

struct EssayBubbleView: View {
    let item: EssayItem
    @State private var selectedImage: UIImage?

    private var hasText: Bool {
        !item.essay.preview.isEmpty && item.essay.preview != "（图片）"
    }

    private var hasImages: Bool {
        !item.localImages.isEmpty || !item.essay.allImageURLs.isEmpty
    }

    var body: some View {
        HStack {
            Spacer(minLength: 60)

            VStack(alignment: .leading, spacing: 0) {
                // 文字
                if hasText {
                    Text(item.essay.preview)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, hasImages ? 8 : 12)
                }

                // 图片
                if hasImages {
                    VStack(spacing: 6) {
                        if !item.localImages.isEmpty {
                            ForEach(Array(item.localImages.enumerated()), id: \.offset) { _, img in
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .onTapGesture { selectedImage = img }
                            }
                        } else {
                            ForEach(item.essay.allImageURLs, id: \.absoluteString) { url in
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    case .failure:
                                        imagePlaceholder(systemName: "exclamationmark.triangle")
                                    case .empty:
                                        imagePlaceholder(systemName: "photo")
                                            .overlay { ProgressView().tint(Theme.textSecondary) }
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                    .padding(.top, hasText ? 0 : 6)
                }
            }
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .fullScreenCover(item: $selectedImage) { img in
            ImageViewerOverlay(image: img)
        }
    }

    private func imagePlaceholder(systemName: String) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Theme.surfaceLight)
            .frame(width: 200, height: 120)
            .overlay {
                Image(systemName: systemName)
                    .foregroundStyle(Theme.textSecondary)
            }
    }
}

// MARK: - 系统回复气泡（左对齐，深灰）

struct ReplyBubbleView: View {
    let reply: PublishReply

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("已发布 ✓")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textPrimary)

                Text("路径: \(reply.filePath)")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Spacer(minLength: 60)
        }
    }
}

// MARK: - UIImage Identifiable（用于 fullScreenCover(item:)）

extension UIImage: @retroactive Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

// MARK: - 全屏图片查看器

struct ImageViewerOverlay: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnifyGesture()
                        .onChanged { scale = $0.magnification }
                        .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.2)) {
                                if scale < 1 { scale = 1 }
                            }
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { offset = $0.translation }
                        .onEnded { value in
                            if abs(value.translation.height) > 150 {
                                dismiss()
                            } else {
                                withAnimation(.easeOut(duration: 0.2)) { offset = .zero }
                            }
                        }
                )
                .onTapGesture { dismiss() }
        }
    }
}
