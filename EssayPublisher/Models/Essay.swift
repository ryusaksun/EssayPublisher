//
//  Essay.swift
//  EssayPublisher
//

import Foundation

// MARK: - 静态正则缓存

private enum EssayRegex {
    static let image = try! NSRegularExpression(pattern: #"!\[.*?\]\(.*?\)"#)
    static let link = try! NSRegularExpression(pattern: #"\[(.*?)\]\(.*?\)"#)
    static let imageURL = try! NSRegularExpression(pattern: #"!\[.*?\]\((.*?)\)"#)
}

private enum EssayFormatter {
    static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f
    }()
}

// MARK: - Essay 模型

struct Essay: Identifiable, Codable, Hashable {
    var id: String { fileName }
    let fileName: String
    let title: String?
    let pubDate: Date
    let content: String
    let rawContent: String

    var preview: String {
        var clean = content
        clean = EssayRegex.image.stringByReplacingMatches(
            in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "")
        clean = EssayRegex.link.stringByReplacingMatches(
            in: clean, range: NSRange(clean.startIndex..., in: clean), withTemplate: "$1")
        clean = clean
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if clean.isEmpty { return "（图片）" }
        if clean.count > 100 {
            return String(clean.prefix(100)) + "..."
        }
        return clean
    }

    var firstImageURL: URL? {
        guard let match = EssayRegex.imageURL.firstMatch(
            in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else { return nil }
        return URL(string: String(content[range]))
    }

    var allImageURLs: [URL] {
        let range = NSRange(content.startIndex..., in: content)
        return EssayRegex.imageURL.matches(in: content, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: content) else { return nil }
            return URL(string: String(content[r]))
        }
    }

    var hasImage: Bool { firstImageURL != nil }
    var formattedDate: String { EssayFormatter.date.string(from: pubDate) }
    var relativeDate: String { EssayFormatter.relative.localizedString(for: pubDate, relativeTo: Date()) }
}

// MARK: - GitHub 文件列表模型

struct GitHubFileInfo: Codable {
    let name: String
    let path: String
    let sha: String
    let size: Int
    let type: String
    let downloadUrl: String?

    enum CodingKeys: String, CodingKey {
        case name, path, sha, size, type
        case downloadUrl = "download_url"
    }
}

// MARK: - Essay 解析器

nonisolated enum EssayParser {

    static func parse(rawContent: String, fileName: String) -> Essay? {
        let (frontmatter, content) = separateFrontmatter(rawContent)
        let pubDate = parsePubDate(from: frontmatter, fileName: fileName) ?? Date()
        let title = parseTitle(from: frontmatter, content: content)
        return Essay(fileName: fileName, title: title, pubDate: pubDate, content: content, rawContent: rawContent)
    }

    private static func separateFrontmatter(_ content: String) -> (String, String) {
        let pattern = #"^---\s*\n([\s\S]*?)\n---\s*\n?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let fmRange = Range(match.range(at: 1), in: content),
              let fullRange = Range(match.range, in: content) else {
            return ("", content)
        }
        return (String(content[fmRange]),
                String(content[fullRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parsePubDate(from frontmatter: String, fileName: String) -> Date? {
        let pattern = #"pubDate:\s*["\']?(\d{4}-\d{2}-\d{2}(?:\s+\d{2}:\d{2}(?::\d{2})?)?)["\']?"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: frontmatter, range: NSRange(frontmatter.startIndex..., in: frontmatter)),
           let range = Range(match.range(at: 1), in: frontmatter) {
            let dateStr = String(frontmatter[range])
            for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
                let f = DateFormatter()
                f.dateFormat = fmt
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
                if let date = f.date(from: dateStr) { return date }
            }
        }

        // 回退：从文件名提取
        let fnPattern = #"^(\d{4})-(\d{2})-(\d{2})(?:-.*?)?-?(\d{6})?"#
        if let regex = try? NSRegularExpression(pattern: fnPattern),
           let match = regex.firstMatch(in: fileName, range: NSRange(fileName.startIndex..., in: fileName)) {
            let y = Range(match.range(at: 1), in: fileName).map { String(fileName[$0]) } ?? "2025"
            let m = Range(match.range(at: 2), in: fileName).map { String(fileName[$0]) } ?? "01"
            let d = Range(match.range(at: 3), in: fileName).map { String(fileName[$0]) } ?? "01"
            var h = "00", mi = "00", s = "00"
            if let tr = Range(match.range(at: 4), in: fileName) {
                let ts = String(fileName[tr])
                if ts.count == 6 { h = String(ts.prefix(2)); mi = String(ts.dropFirst(2).prefix(2)); s = String(ts.suffix(2)) }
            }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
            return f.date(from: "\(y)-\(m)-\(d) \(h):\(mi):\(s)")
        }
        return nil
    }

    private static func parseTitle(from frontmatter: String, content: String) -> String? {
        let titlePattern = #"title:\s*["\']?(.+?)["\']?\s*$"#
        if let regex = try? NSRegularExpression(pattern: titlePattern, options: .anchorsMatchLines),
           let match = regex.firstMatch(in: frontmatter, range: NSRange(frontmatter.startIndex..., in: frontmatter)),
           let range = Range(match.range(at: 1), in: frontmatter) {
            let title = String(frontmatter[range]).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return title }
        }
        let headingPattern = #"^#\s+(.+)$"#
        if let regex = try? NSRegularExpression(pattern: headingPattern, options: .anchorsMatchLines),
           let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
           let range = Range(match.range(at: 1), in: content) {
            return String(content[range]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
