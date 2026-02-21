//
//  GitHubService.swift
//  EssayPublisher
//
//  修复自 Swift_MarkdownEditor:
//  1. generateFilePath 添加随机 3 位后缀
//  2. generateFilePath 使用固定 UTC+8 时区
//  3. getFile/createOrUpdateFile 添加 branch 参数
//  4. uploadImage 使用 UTC+8 时区

import Foundation

actor GitHubService {

    static let shared = GitHubService()

    private let baseURL = "https://api.github.com"

    /// UTC+8 固定时区
    private static let cstTimeZone = TimeZone(secondsFromGMT: 8 * 3600)!

    // 文件路径生成用正则
    private static let frontmatterRegex = try! NSRegularExpression(pattern: #"^---[\s\S]*?---\n*"#)
    private static let mdImageRegex = try! NSRegularExpression(pattern: #"!\[.*?\]\(.*?\)"#)
    private static let mdLinkRegex = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\([^\)]+\)"#)
    private static let mdSymbolRegex = try! NSRegularExpression(pattern: #"[#*`_~\->|/]"#)
    private static let whitespaceRegex = try! NSRegularExpression(pattern: #"\s+"#)
    private static let titleCleanRegex = try! NSRegularExpression(pattern: #"[^\w\s\u4e00-\u9fa5-]"#)
    private static let titleSpaceRegex = try! NSRegularExpression(pattern: #"\s+"#)
    private static let cjkAlphaRegex = try! NSRegularExpression(pattern: #"[\u4e00-\u9fa5a-zA-Z]"#)

    private init() {}

    // MARK: - 通用请求

    func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        acceptRaw: Bool = false
    ) async throws -> T {
        let token = AppConfig.githubToken
        guard AppConfig.isGitHubConfigured else { throw GitHubError.notConfigured }
        guard let url = URL(string: "\(baseURL)\(endpoint)") else { throw GitHubError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(acceptRaw ? "application/vnd.github.v3.raw" : "application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            if let err = try? JSONDecoder().decode(GHErrorResponse.self, from: data) {
                throw GitHubError.apiError(code: http.statusCode, message: err.message)
            }
            throw GitHubError.apiError(code: http.statusCode, message: "Unknown error")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func fetchRawContent(endpoint: String) async throws -> String {
        let token = AppConfig.githubToken
        guard AppConfig.isGitHubConfigured else { throw GitHubError.notConfigured }
        guard let url = URL(string: "\(baseURL)\(endpoint)") else { throw GitHubError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitHubError.apiError(code: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "获取内容失败")
        }
        guard let content = String(data: data, encoding: .utf8) else { throw GitHubError.invalidContent }
        return content
    }

    func verifyToken(_ token: String) async throws -> String {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "\(baseURL)/user") else { throw GitHubError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("token \(clean)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitHubError.apiError(code: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "Token 无效或已过期")
        }
        struct User: Decodable { let login: String }
        return try JSONDecoder().decode(User.self, from: data).login
    }

    // MARK: - 文件操作（修复 #3: 添加 branch 参数）

    func getFile(path: String, branch: String? = nil) async throws -> FileContent? {
        let br = branch ?? AppConfig.githubBranch
        do {
            let resp: GHFileResponse = try await request(
                endpoint: "/repos/\(AppConfig.githubOwner)/\(AppConfig.githubRepo)/contents/\(path)?ref=\(br)")
            guard let data = Data(base64Encoded: resp.content.replacingOccurrences(of: "\n", with: "")),
                  let content = String(data: data, encoding: .utf8) else {
                throw GitHubError.invalidContent
            }
            return FileContent(content: content, sha: resp.sha)
        } catch GitHubError.apiError(let code, _) where code == 404 {
            return nil
        }
    }

    func createOrUpdateFile(
        path: String,
        content: String,
        message: String,
        sha: String? = nil,
        branch: String? = nil
    ) async throws -> GHCreateFileResponse {
        guard let contentData = content.data(using: .utf8) else { throw GitHubError.invalidContent }

        var body: [String: Any] = [
            "message": message,
            "content": contentData.base64EncodedString()
        ]
        if let sha { body["sha"] = sha }
        if let branch { body["branch"] = branch } else { body["branch"] = AppConfig.githubBranch }

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        return try await request(
            endpoint: "/repos/\(AppConfig.githubOwner)/\(AppConfig.githubRepo)/contents/\(path)",
            method: "PUT",
            body: bodyData)
    }

    func deleteFile(path: String, branch: String? = nil) async throws {
        let br = branch ?? AppConfig.githubBranch
        guard let file = try await getFile(path: path, branch: br) else {
            throw GitHubError.apiError(code: 404, message: "文件不存在: \(path)")
        }
        let body: [String: Any] = [
            "message": "Delete: \(path.split(separator: "/").last ?? "")",
            "sha": file.sha,
            "branch": br
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let _: GHDeleteResponse = try await request(
            endpoint: "/repos/\(AppConfig.githubOwner)/\(AppConfig.githubRepo)/contents/\(path)",
            method: "DELETE",
            body: bodyData)
    }

    // MARK: - 发布

    func publishContent(
        type: ContentType,
        metadata: Metadata,
        content: String
    ) async throws -> PublishResult {
        let filePath = generateFilePath(type: type, metadata: metadata, content: content)
        let existing = try await getFile(path: filePath, branch: AppConfig.githubBranch)
        let action = existing != nil ? "Update" : "Add"
        let title = metadata.title.isEmpty ? "Untitled" : metadata.title
        let message = "\(action) \(type.rawValue): \(title)"

        let result = try await createOrUpdateFile(
            path: filePath, content: content, message: message,
            sha: existing?.sha, branch: AppConfig.githubBranch)

        return PublishResult(success: true, filePath: filePath, url: result.content.htmlUrl, action: action.lowercased())
    }

    // MARK: - 文件路径生成（修复 #1 + #2）

    func generateFilePath(type: ContentType, metadata: Metadata, content: String) -> String {
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.cstTimeZone

        let year = calendar.component(.year, from: now)
        let month = String(format: "%02d", calendar.component(.month, from: now))
        let day = String(format: "%02d", calendar.component(.day, from: now))
        let hour = String(format: "%02d", calendar.component(.hour, from: now))
        let minute = String(format: "%02d", calendar.component(.minute, from: now))
        let second = String(format: "%02d", calendar.component(.second, from: now))

        let datePrefix = "\(year)-\(month)-\(day)"
        // 修复 #1: 添加随机 3 位后缀
        let random = Int.random(in: 100...999)
        let timestamp = "\(hour)\(minute)\(second)-\(random)"

        switch type {
        case .blog:
            let raw = metadata.title.isEmpty ? "untitled" : metadata.title
            let range = NSRange(raw.startIndex..., in: raw)
            let cleaned = Self.titleCleanRegex.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
            let cr = NSRange(cleaned.startIndex..., in: cleaned)
            let safe = Self.titleSpaceRegex.stringByReplacingMatches(in: cleaned, range: cr, withTemplate: "-").lowercased()
            return "\(type.pathPrefix)/\(safe)-\(timestamp).md"

        case .essay:
            var plain = content
            let r1 = NSRange(plain.startIndex..., in: plain)
            plain = Self.frontmatterRegex.stringByReplacingMatches(in: plain, range: r1, withTemplate: "")
            let r2 = NSRange(plain.startIndex..., in: plain)
            plain = Self.mdImageRegex.stringByReplacingMatches(in: plain, range: r2, withTemplate: "")
            let r3 = NSRange(plain.startIndex..., in: plain)
            plain = Self.mdLinkRegex.stringByReplacingMatches(in: plain, range: r3, withTemplate: "$1")
            let r4 = NSRange(plain.startIndex..., in: plain)
            plain = Self.mdSymbolRegex.stringByReplacingMatches(in: plain, range: r4, withTemplate: "")
            let r5 = NSRange(plain.startIndex..., in: plain)
            plain = Self.whitespaceRegex.stringByReplacingMatches(in: plain, range: r5, withTemplate: "")

            var first4 = ""
            var count = 0
            for ch in plain {
                if count >= 4 { break }
                let s = String(ch)
                let sr = NSRange(s.startIndex..., in: s)
                if Self.cjkAlphaRegex.firstMatch(in: s, range: sr) != nil {
                    first4 += s
                    count += 1
                }
            }

            if first4.isEmpty {
                return "\(type.pathPrefix)/\(datePrefix)-\(timestamp).md"
            } else {
                return "\(type.pathPrefix)/\(datePrefix)-\(first4)-\(timestamp).md"
            }
        }
    }

    // MARK: - 图片上传（修复 #2: UTC+8 时区）

    func uploadImage(imageData: Data, fileName: String) async throws -> ImageUploadResult {
        let base64 = imageData.base64EncodedString()

        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.cstTimeZone
        let year = calendar.component(.year, from: now)
        let month = String(format: "%02d", calendar.component(.month, from: now))

        let filePath = "\(AppConfig.imagePath)/\(year)/\(month)/\(fileName)"

        let body: [String: Any] = [
            "message": "Upload image: \(fileName)",
            "content": base64,
            "branch": AppConfig.imageBranch
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let response: GHCreateFileResponse = try await request(
            endpoint: "/repos/\(AppConfig.githubOwner)/\(AppConfig.imageRepo)/contents/\(filePath)",
            method: "PUT",
            body: bodyData)

        let cdnUrl = AppConfig.generateImageCDNUrl(path: filePath)
        return ImageUploadResult(success: true, path: filePath, url: cdnUrl, sha: response.content.sha)
    }
}

// MARK: - 错误类型

enum GitHubError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case invalidContent
    case apiError(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "GitHub 配置缺失"
        case .invalidURL: return "无效的 URL"
        case .invalidResponse: return "无效的响应"
        case .invalidContent: return "无效的内容"
        case .apiError(let code, let message): return "GitHub API 错误 (\(code)): \(message)"
        }
    }
}
