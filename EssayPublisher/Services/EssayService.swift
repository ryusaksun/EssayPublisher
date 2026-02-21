//
//  EssayService.swift
//  EssayPublisher
//
//  移植自 Swift_MarkdownEditor，添加乐观插入支持

import Foundation

actor EssayService {

    static let shared = EssayService()

    private let essaysPath = "src/content/essays"

    // MARK: - 缓存

    private var cachedEssays: [Essay] = []
    private var cacheTimestamp: Date?
    private let cacheValidity: TimeInterval = AppConfig.essayCacheValidity
    private var isLoading = false

    private var localCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("essays_cache.json")
    }

    private init() {
        if let cache = Self.loadFromDisk() {
            self.cachedEssays = cache.essays
            self.cacheTimestamp = cache.timestamp
        }
    }

    // MARK: - Public API

    func fetchEssays(forceRefresh: Bool = false) async throws -> [Essay] {
        if !forceRefresh,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheValidity,
           !cachedEssays.isEmpty {
            return cachedEssays
        }

        if isLoading && !cachedEssays.isEmpty {
            return cachedEssays
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let files = try await fetchFileList()
            let mdFiles = files.filter { $0.name.hasSuffix(".md") }

            var essays: [Essay] = []
            let maxConcurrent = 6

            try await withThrowingTaskGroup(of: Essay?.self) { group in
                var submitted = 0
                for file in mdFiles {
                    if submitted >= maxConcurrent {
                        if let essay = try await group.next() ?? nil {
                            essays.append(essay)
                        }
                    }
                    group.addTask {
                        return try? await self.fetchEssayContent(fileName: file.name)
                    }
                    submitted += 1
                }
                for try await essay in group {
                    if let essay { essays.append(essay) }
                }
            }

            let sorted = essays.sorted { $0.pubDate > $1.pubDate }
            cachedEssays = sorted
            cacheTimestamp = Date()
            saveLocalCache(sorted)
            return sorted

        } catch {
            if !cachedEssays.isEmpty { return cachedEssays }
            throw error
        }
    }

    func getCachedEssays() -> [Essay] { cachedEssays }
    var hasCachedData: Bool { !cachedEssays.isEmpty }

    func fetchEssayContent(fileName: String) async throws -> Essay {
        let endpoint = "/repos/\(AppConfig.githubOwner)/\(AppConfig.githubRepo)/contents/\(essaysPath)/\(fileName)?ref=\(AppConfig.githubBranch)"
        let content = try await GitHubService.shared.fetchRawContent(endpoint: endpoint)
        guard let essay = EssayParser.parse(rawContent: content, fileName: fileName) else {
            throw EssayError.parseError("无法解析 Essay")
        }
        return essay
    }

    /// 发布成功后乐观插入到缓存顶部
    func insertLocally(_ essay: Essay) {
        cachedEssays.insert(essay, at: 0)
        cacheTimestamp = Date()
        saveLocalCache(cachedEssays)
    }

    func deleteEssay(fileName: String) async throws {
        let path = "\(essaysPath)/\(fileName)"
        try await GitHubService.shared.deleteFile(path: path)
        cachedEssays.removeAll { $0.fileName == fileName }
        saveLocalCache(cachedEssays)
    }

    func updateEssay(fileName: String, newContent: String) async throws {
        let path = "\(essaysPath)/\(fileName)"
        guard let file = try await GitHubService.shared.getFile(path: path, branch: AppConfig.githubBranch) else {
            throw EssayError.networkError("文件不存在")
        }
        _ = try await GitHubService.shared.createOrUpdateFile(
            path: path, content: newContent,
            message: "Update essay: \(fileName)",
            sha: file.sha, branch: AppConfig.githubBranch)
        // 更新缓存
        if let essay = EssayParser.parse(rawContent: newContent, fileName: fileName),
           let idx = cachedEssays.firstIndex(where: { $0.fileName == fileName }) {
            cachedEssays[idx] = essay
            saveLocalCache(cachedEssays)
        }
    }

    func clearCache() {
        cachedEssays = []
        cacheTimestamp = nil
        if let url = localCacheURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Local Cache

    private struct LocalCache: Codable {
        let essays: [CachedEssay]
        let timestamp: Date
    }

    private struct CachedEssay: Codable {
        let fileName: String
        let title: String?
        let pubDate: Date
        let content: String
        let rawContent: String

        init(from essay: Essay) {
            self.fileName = essay.fileName
            self.title = essay.title
            self.pubDate = essay.pubDate
            self.content = essay.content
            self.rawContent = essay.rawContent
        }

        func toEssay() -> Essay? {
            EssayParser.parse(rawContent: rawContent, fileName: fileName)
        }
    }

    private static func loadFromDisk() -> (essays: [Essay], timestamp: Date)? {
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("essays_cache.json"),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cache = try decoder.decode(LocalCache.self, from: data)
            if Date().timeIntervalSince(cache.timestamp) < AppConfig.essayLocalCacheValidity {
                return (cache.essays.compactMap { $0.toEssay() }, cache.timestamp)
            }
        } catch {}
        return nil
    }

    private func saveLocalCache(_ essays: [Essay]) {
        guard let url = localCacheURL else { return }
        do {
            let cached = essays.map { CachedEssay(from: $0) }
            let cache = LocalCache(essays: cached, timestamp: Date())
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(cache).write(to: url)
        } catch {}
    }

    private func fetchFileList() async throws -> [GitHubFileInfo] {
        let endpoint = "/repos/\(AppConfig.githubOwner)/\(AppConfig.githubRepo)/contents/\(essaysPath)?ref=\(AppConfig.githubBranch)"
        return try await GitHubService.shared.request(endpoint: endpoint)
    }
}

// MARK: - 错误

enum EssayError: LocalizedError {
    case networkError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "网络错误: \(msg)"
        case .parseError(let msg): return "解析错误: \(msg)"
        }
    }
}
