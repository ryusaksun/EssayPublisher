//
//  Metadata.swift
//  EssayPublisher
//

import Foundation

struct Metadata {
    var title: String = ""
    var categories: String = "Daily"
    var pubDate: String = ""

    /// UTC+8 时区（固定，不依赖设备时区）
    private static let cstTimeZone = TimeZone(secondsFromGMT: 8 * 3600)!

    mutating func reset(for contentType: ContentType) {
        let now = Date()
        let formatter = DateFormatter()
        formatter.timeZone = Self.cstTimeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")

        switch contentType {
        case .essay:
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            title = ""
            categories = ""
            pubDate = formatter.string(from: now)

        case .blog:
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            title = ""
            categories = "Daily"
            pubDate = formatter.string(from: now)
        }
    }

    func toFrontmatter(for contentType: ContentType) -> String {
        var lines: [String] = []

        switch contentType {
        case .essay:
            if !pubDate.isEmpty {
                lines.append("pubDate: \"\(pubDate)\"")
            }

        case .blog:
            if !title.isEmpty {
                let escaped = title
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                lines.append("title: \"\(escaped)\"")
            }
            if !categories.isEmpty {
                let cats = categories.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if !cats.isEmpty {
                    lines.append("categories: [\(cats.map { "\"\($0)\"" }.joined(separator: ", "))]")
                }
            }
            if !pubDate.isEmpty {
                lines.append("pubDate: \"\(pubDate)\"")
            }
        }

        guard !lines.isEmpty else { return "" }
        return "---\n\(lines.joined(separator: "\n"))\n---\n\n"
    }
}
