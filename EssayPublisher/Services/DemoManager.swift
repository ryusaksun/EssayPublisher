//
//  DemoManager.swift
//  EssayPublisher
//
//  Demo 模式管理：供 App Store 审核员体验完整功能

import SwiftUI

@MainActor
final class DemoManager: ObservableObject {

    static let shared = DemoManager()

    @Published var isDemoMode: Bool {
        didSet {
            UserDefaults.standard.set(isDemoMode, forKey: "demo_mode")
        }
    }

    private init() {
        self.isDemoMode = UserDefaults.standard.bool(forKey: "demo_mode")
    }

    func enterDemo() {
        isDemoMode = true
    }

    func exitDemo() {
        isDemoMode = false
    }

    // MARK: - Demo 预置数据

    static let demoDisplayName = "Demo User"
    static let demoUsername = "demo-user"
    static let demoOwner = "demo-user"
    static let demoRepo = "my-blog"
    static let demoBranch = "main"
    static let demoImageRepo = "blog-images"

    static let demoEssays: [Essay] = {
        let calendar = Calendar.current
        let now = Date()

        return [
            Essay(
                fileName: makeFileName(daysAgo: 0, time: "103025", slug: "coff"),
                title: nil,
                pubDate: calendar.date(byAdding: .hour, value: -2, to: now)!,
                content: "今天阳光很好，在咖啡馆写了一下午的代码。窗外的树叶被风吹得沙沙响，偶尔有几只麻雀飞过来停在窗台上。生活就是这些平凡又美好的瞬间组成的吧。",
                rawContent: "---\npubDate: \"\(formatDate(calendar.date(byAdding: .hour, value: -2, to: now)!))\"\n---\n\n今天阳光很好，在咖啡馆写了一下午的代码。窗外的树叶被风吹得沙沙响，偶尔有几只麻雀飞过来停在窗台上。生活就是这些平凡又美好的瞬间组成的吧。"
            ),
            Essay(
                fileName: makeFileName(daysAgo: 1, time: "201500", slug: "read"),
                title: nil,
                pubDate: calendar.date(byAdding: .day, value: -1, to: now)!,
                content: "读完了《百年孤独》，马尔克斯的魔幻现实主义真的让人着迷。布恩迪亚家族七代人的故事，像一面镜子映照着拉丁美洲的历史。最让我印象深刻的是那句——多年以后，面对行刑队，奥雷里亚诺·布恩迪亚上校将会回想起父亲带他去见识冰块的那个遥远的下午。\n\n这种时间的折叠感，在整本书里反复出现，让人分不清过去和未来的边界。",
                rawContent: "---\npubDate: \"\(formatDate(calendar.date(byAdding: .day, value: -1, to: now)!))\"\n---\n\n读完了《百年孤独》，马尔克斯的魔幻现实主义真的让人着迷。布恩迪亚家族七代人的故事，像一面镜子映照着拉丁美洲的历史。最让我印象深刻的是那句——多年以后，面对行刑队，奥雷里亚诺·布恩迪亚上校将会回想起父亲带他去见识冰块的那个遥远的下午。\n\n这种时间的折叠感，在整本书里反复出现，让人分不清过去和未来的边界。"
            ),
            Essay(
                fileName: makeFileName(daysAgo: 3, time: "143000", slug: "swif"),
                title: nil,
                pubDate: calendar.date(byAdding: .day, value: -3, to: now)!,
                content: "Swift 的 **async/await** 真的改变了 iOS 开发的体验。以前用 completion handler 写的回调地狱，现在变成了清晰的线性代码。配合 `actor` 做并发安全，整个架构优雅了很多。\n\n```swift\nfunc fetchData() async throws -> [Item] {\n    let response = try await api.request()\n    return response.items\n}\n```\n\n下一步准备研究 Swift 6 的严格并发检查。",
                rawContent: "---\npubDate: \"\(formatDate(calendar.date(byAdding: .day, value: -3, to: now)!))\"\n---\n\nSwift 的 **async/await** 真的改变了 iOS 开发的体验。以前用 completion handler 写的回调地狱，现在变成了清晰的线性代码。配合 `actor` 做并发安全，整个架构优雅了很多。\n\n```swift\nfunc fetchData() async throws -> [Item] {\n    let response = try await api.request()\n    return response.items\n}\n```\n\n下一步准备研究 Swift 6 的严格并发检查。"
            ),
            Essay(
                fileName: makeFileName(daysAgo: 5, time: "091200", slug: "walk"),
                title: nil,
                pubDate: calendar.date(byAdding: .day, value: -5, to: now)!,
                content: "Took a long walk along the river this morning. The mist was still hanging over the water, and everything felt so quiet and peaceful. Sometimes you need to step away from the screen to remember what matters.\n\nThe best ideas often come when you're not trying to have them.",
                rawContent: "---\npubDate: \"\(formatDate(calendar.date(byAdding: .day, value: -5, to: now)!))\"\n---\n\nTook a long walk along the river this morning. The mist was still hanging over the water, and everything felt so quiet and peaceful. Sometimes you need to step away from the screen to remember what matters.\n\nThe best ideas often come when you're not trying to have them."
            ),
            Essay(
                fileName: makeFileName(daysAgo: 7, time: "160000", slug: "tool"),
                title: "我的写作工具链",
                pubDate: calendar.date(byAdding: .day, value: -7, to: now)!,
                content: "# 我的写作工具链\n\n分享一下我目前的写作工作流：\n\n1. **构思**: 用 Apple Notes 随手记录灵感\n2. **写作**: Markdown 编辑器，专注内容本身\n3. **发布**: 通过这个 App 直接推送到 GitHub\n4. **展示**: Astro 静态站点自动构建部署\n\n整个流程从想法到发布，不超过五分钟。简单的工具链让写作的阻力降到最低。",
                rawContent: "---\ntitle: \"我的写作工具链\"\npubDate: \"\(formatDate(calendar.date(byAdding: .day, value: -7, to: now)!))\"\n---\n\n# 我的写作工具链\n\n分享一下我目前的写作工作流：\n\n1. **构思**: 用 Apple Notes 随手记录灵感\n2. **写作**: Markdown 编辑器，专注内容本身\n3. **发布**: 通过这个 App 直接推送到 GitHub\n4. **展示**: Astro 静态站点自动构建部署\n\n整个流程从想法到发布，不超过五分钟。简单的工具链让写作的阻力降到最低。"
            ),
        ]
    }()

    // MARK: - Helpers

    private static func makeFileName(daysAgo: Int, time: String, slug: String) -> String {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        let dateStr = formatter.string(from: date)
        return "\(dateStr)-\(slug)-\(time)-000.md"
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        return formatter.string(from: date)
    }
}
