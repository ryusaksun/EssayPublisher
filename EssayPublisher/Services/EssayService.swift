//
//  EssayService.swift
//  EssayPublisher
//
//  移植自 Swift_MarkdownEditor，添加乐观插入支持

import Foundation
import OSLog

actor EssayService {

    static let shared = EssayService()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ryuichi.essaypublisher",
        category: "EssayService"
    )
    private static let fileNameDateRegex = try! NSRegularExpression(
        pattern: #"^(\d{4})-(\d{2})-(\d{2})(?:-.*?)?-?(\d{6})?"#
    )
    private static let cstTimeZone = TimeZone(secondsFromGMT: 8 * 3600)!

    private let essaysPath = "src/content/essays"
    private let maxConcurrentFetch = 8
    private let recentCacheCount = 10

    // MARK: - 缓存

    private var cachedEssays: [Essay] = []
    private var cachedEssaySHAs: [String: String] = [:]
    private var fileListETag: String?
    private var recentCommitsETag: String?
    private var cacheTimestamp: Date?
    private let cacheValidity: TimeInterval = AppConfig.essayCacheValidity
    private var hasCompleteCache = false
    private var didAttemptHydrateFullCache = false
    private var isLoading = false

    private var localCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("essays_cache.json")
    }

    private var recentCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("essays_recent_cache.json")
    }

    private init() {
        if let cache = Self.loadRecentFromDisk(limit: recentCacheCount) {
            self.cachedEssays = cache.essays
            self.cacheTimestamp = cache.timestamp
            self.cachedEssaySHAs = cache.shaByFileName
            self.fileListETag = cache.fileListETag
            self.recentCommitsETag = cache.recentCommitsETag
            self.hasCompleteCache = false
        } else if let cache = Self.loadFromDisk() {
            self.cachedEssays = cache.essays
            self.cacheTimestamp = cache.timestamp
            self.cachedEssaySHAs = cache.shaByFileName
            self.fileListETag = cache.fileListETag
            self.recentCommitsETag = cache.recentCommitsETag
            self.hasCompleteCache = true
            self.didAttemptHydrateFullCache = true
        }
    }

    // MARK: - Public API

    func fetchEssays(forceRefresh: Bool = false) async throws -> [Essay] {
        if !forceRefresh {
            hydrateFullCacheFromDiskIfNeeded()
        }

        if !forceRefresh,
           hasCompleteCache,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheValidity,
           !cachedEssays.isEmpty {
            return cachedEssays
        }

        if isLoading && hasCompleteCache && !cachedEssays.isEmpty {
            return cachedEssays
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let files: [GitHubFileInfo]
            switch try await fetchFileListState() {
            case .notModified:
                if !cachedEssays.isEmpty {
                    cacheTimestamp = Date()
                    return cachedEssays
                }
                files = try await fetchFileList()
            case .modified(let newFiles):
                files = newFiles
            }

            let mdFiles = files.filter { $0.name.hasSuffix(".md") }
            let cachedByName = Dictionary(uniqueKeysWithValues: cachedEssays.map { ($0.fileName, $0) })
            let batch = await fetchEssaysFromFiles(mdFiles, cachedByName: cachedByName)
            let essays = batch.essays
            let failedFiles = batch.failed

            if !failedFiles.isEmpty {
                let sampleFiles = failedFiles.prefix(3).joined(separator: ", ")
                Self.logger.warning(
                    "Partial fetch failure. success=\(essays.count, privacy: .public), failed=\(failedFiles.count, privacy: .public), sample=\(sampleFiles, privacy: .public)"
                )
            }
            if essays.isEmpty, !mdFiles.isEmpty {
                throw EssayError.networkError(String(format: "error.essay.fetchFailed".localized, mdFiles.count))
            }

            let sorted = essays.sorted { $0.pubDate > $1.pubDate }
            cachedEssays = sorted
            cachedEssaySHAs = Dictionary(uniqueKeysWithValues: mdFiles.map { ($0.name, $0.sha) })
            hasCompleteCache = true
            cacheTimestamp = Date()
            saveLocalCache(sorted)
            saveRecentLocalCache(sorted)
            return sorted

        } catch {
            if !cachedEssays.isEmpty { return cachedEssays }
            throw error
        }
    }

    /// 针对历史页优化：仅拉取“可能最近”的候选文件，减少网络请求数量
    func fetchRecentEssays(limit: Int = 10, forceRefresh: Bool = false) async throws -> [Essay] {
        let safeLimit = max(limit, 1)

        if !forceRefresh,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheValidity,
           cachedEssays.count >= safeLimit {
            return Array(cachedEssays.prefix(safeLimit))
        }

        if isLoading && cachedEssays.count >= safeLimit {
            return Array(cachedEssays.prefix(safeLimit))
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let desiredCandidates = min(max(safeLimit * 4, 20), 80)
            let candidateFileNames: [String]

            switch try await fetchRecentFileNamesState(limit: desiredCandidates) {
            case .notModified:
                if cachedEssays.count >= safeLimit {
                    cacheTimestamp = Date()
                    return Array(cachedEssays.prefix(safeLimit))
                }
                candidateFileNames = try await fallbackRecentFileNamesFromFileList(limit: desiredCandidates)
            case .modified(let names):
                if names.isEmpty {
                    candidateFileNames = try await fallbackRecentFileNamesFromFileList(limit: desiredCandidates)
                } else {
                    candidateFileNames = names
                }
            }

            var mergedCandidateFileNames = candidateFileNames
            if mergedCandidateFileNames.count < safeLimit {
                let fallbackNames = try await fallbackRecentFileNamesFromFileList(limit: desiredCandidates)
                var seen = Set(mergedCandidateFileNames)
                for fileName in fallbackNames where seen.insert(fileName).inserted {
                    mergedCandidateFileNames.append(fileName)
                    if mergedCandidateFileNames.count >= desiredCandidates {
                        break
                    }
                }
            }

            guard !mergedCandidateFileNames.isEmpty else {
                cachedEssays = []
                cacheTimestamp = Date()
                saveRecentLocalCache([])
                if hasCompleteCache {
                    saveLocalCache([])
                }
                return []
            }

            let candidateFiles = mergedCandidateFileNames.map {
                GitHubFileInfo(
                    name: $0,
                    path: "\(essaysPath)/\($0)",
                    sha: "",
                    size: 0,
                    type: "file",
                    downloadUrl: nil
                )
            }
            let initialWindow = min(max(safeLimit + 2, 12), candidateFiles.count)

            var start = 0
            var windowSize = initialWindow
            var collected: [Essay] = []
            var collectedNames: Set<String> = []
            var failedFiles: [String] = []
            var resolvedSHAs: [String: String] = [:]
            let cachedByName = Dictionary(uniqueKeysWithValues: cachedEssays.map { ($0.fileName, $0) })

            while start < candidateFiles.count && collected.count < safeLimit {
                let end = min(start + windowSize, candidateFiles.count)
                let batch = Array(candidateFiles[start..<end])
                let batchResult = await fetchEssaysFromFiles(batch, cachedByName: cachedByName)
                let batchEssays = batchResult.essays
                let batchFailed = batchResult.failed

                for essay in batchEssays where collectedNames.insert(essay.fileName).inserted {
                    collected.append(essay)
                }
                for (fileName, sha) in batchResult.shaByFileName {
                    resolvedSHAs[fileName] = sha
                }
                failedFiles.append(contentsOf: batchFailed)
                start = end

                if collected.count < safeLimit, start < candidateFiles.count {
                    let remaining = candidateFiles.count - start
                    let expandedWindow = max(windowSize * 2, safeLimit)
                    windowSize = min(expandedWindow, remaining)
                }
            }

            let sorted = collected.sorted { $0.pubDate > $1.pubDate }
            var limited = Array(sorted.prefix(safeLimit))

            if limited.count < safeLimit, !cachedEssays.isEmpty {
                var seen = Set(limited.map { $0.fileName })
                for essay in cachedEssays where seen.insert(essay.fileName).inserted {
                    limited.append(essay)
                    if limited.count >= safeLimit { break }
                }
                limited.sort { $0.pubDate > $1.pubDate }
                if limited.count > safeLimit {
                    limited = Array(limited.prefix(safeLimit))
                }
            }

            if !failedFiles.isEmpty {
                let sampleFiles = failedFiles.prefix(3).joined(separator: ", ")
                Self.logger.warning(
                    "Recent fetch partial failure. success=\(limited.count, privacy: .public), failed=\(failedFiles.count, privacy: .public), sample=\(sampleFiles, privacy: .public)"
                )
            }

            if limited.isEmpty {
                throw EssayError.networkError(String(format: "error.essay.recentFetchFailed".localized, safeLimit))
            }

            updateCacheWithRecent(limited, shaByFileName: resolvedSHAs)
            return limited

        } catch {
            if !cachedEssays.isEmpty { return Array(cachedEssays.prefix(safeLimit)) }
            throw error
        }
    }

    func getCachedEssays() -> [Essay] { cachedEssays }
    func getCachedRecentEssays(limit: Int = 10) -> [Essay] {
        let safeLimit = max(limit, 1)
        return Array(cachedEssays.prefix(safeLimit))
    }
    var hasCachedData: Bool { !cachedEssays.isEmpty }

    func fetchEssayContent(fileName: String) async throws -> Essay {
        let endpoint = "/repos/\(AppConfig.githubOwner)/\(AppConfig.githubRepo)/contents/\(essaysPath)/\(fileName)?ref=\(AppConfig.githubBranch)"
        let content = try await GitHubService.shared.fetchRawContent(endpoint: endpoint)
        guard let essay = EssayParser.parse(rawContent: content, fileName: fileName) else {
            throw EssayError.parseError("error.essay.parseFailed".localized)
        }
        return essay
    }

    /// 发布成功后乐观插入到缓存顶部
    func insertLocally(_ essay: Essay) {
        cachedEssays.insert(essay, at: 0)
        cachedEssaySHAs.removeValue(forKey: essay.fileName)
        cacheTimestamp = Date()
        saveRecentLocalCache(cachedEssays)
        if hasCompleteCache {
            saveLocalCache(cachedEssays)
        }
    }

    func deleteEssay(fileName: String) async throws {
        let path = "\(essaysPath)/\(fileName)"
        try await GitHubService.shared.deleteFile(path: path)
        cachedEssays.removeAll { $0.fileName == fileName }
        cachedEssaySHAs.removeValue(forKey: fileName)
        saveRecentLocalCache(cachedEssays)
        if hasCompleteCache {
            saveLocalCache(cachedEssays)
        }
    }

    func updateEssay(fileName: String, newContent: String) async throws {
        let path = "\(essaysPath)/\(fileName)"
        guard let file = try await GitHubService.shared.getFile(path: path, branch: AppConfig.githubBranch) else {
            throw EssayError.networkError("error.essay.fileNotFound".localized)
        }
        let updateResult = try await GitHubService.shared.createOrUpdateFile(
            path: path, content: newContent,
            message: "Update essay: \(fileName)",
            sha: file.sha, branch: AppConfig.githubBranch)
        cachedEssaySHAs[fileName] = updateResult.content.sha
        // 更新缓存
        if let essay = EssayParser.parse(rawContent: newContent, fileName: fileName) {
            if let idx = cachedEssays.firstIndex(where: { $0.fileName == fileName }) {
                cachedEssays[idx] = essay
            } else {
                cachedEssays.append(essay)
            }
            cachedEssays.sort { $0.pubDate > $1.pubDate }
            saveRecentLocalCache(cachedEssays)
            if hasCompleteCache {
                saveLocalCache(cachedEssays)
            }
        }
    }

    func clearCache() {
        cachedEssays = []
        cachedEssaySHAs = [:]
        fileListETag = nil
        recentCommitsETag = nil
        cacheTimestamp = nil
        hasCompleteCache = false
        didAttemptHydrateFullCache = false
        if let url = localCacheURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let url = recentCacheURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Local Cache

    private struct LocalCache: Codable {
        let essays: [CachedEssay]
        let timestamp: Date
        let shaByFileName: [String: String]?
        let fileListETag: String?
        let recentCommitsETag: String?
    }

    private struct RecentLocalCache: Codable {
        let essays: [CachedEssay]
        let timestamp: Date
        let shaByFileName: [String: String]?
        let fileListETag: String?
        let recentCommitsETag: String?
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

        func toEssay() -> Essay {
            Essay(
                fileName: fileName,
                title: title,
                pubDate: pubDate,
                content: content,
                rawContent: rawContent
            )
        }
    }

    private func hydrateFullCacheFromDiskIfNeeded() {
        guard !hasCompleteCache, !didAttemptHydrateFullCache else { return }
        didAttemptHydrateFullCache = true

        guard let cache = Self.loadFromDisk() else { return }
        cachedEssays = cache.essays
        cacheTimestamp = cache.timestamp
        cachedEssaySHAs = cache.shaByFileName
        if let eTag = cache.fileListETag {
            fileListETag = eTag
        }
        if let eTag = cache.recentCommitsETag {
            recentCommitsETag = eTag
        }
        hasCompleteCache = true
    }

    private static func loadFromDisk() -> (
        essays: [Essay],
        timestamp: Date,
        shaByFileName: [String: String],
        fileListETag: String?,
        recentCommitsETag: String?
    )? {
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
                return (
                    cache.essays.map { $0.toEssay() },
                    cache.timestamp,
                    cache.shaByFileName ?? [:],
                    cache.fileListETag,
                    cache.recentCommitsETag
                )
            }
        } catch {
            Self.logger.error("Load local cache failed: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    private static func loadRecentFromDisk(limit: Int) -> (
        essays: [Essay],
        timestamp: Date,
        shaByFileName: [String: String],
        fileListETag: String?,
        recentCommitsETag: String?
    )? {
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("essays_recent_cache.json"),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cache = try decoder.decode(RecentLocalCache.self, from: data)
            if Date().timeIntervalSince(cache.timestamp) < AppConfig.essayLocalCacheValidity {
                let safeLimit = max(limit, 1)
                return (
                    Array(cache.essays.prefix(safeLimit)).map { $0.toEssay() },
                    cache.timestamp,
                    cache.shaByFileName ?? [:],
                    cache.fileListETag,
                    cache.recentCommitsETag
                )
            }
        } catch {
            Self.logger.error("Load recent cache failed: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    private func saveLocalCache(_ essays: [Essay]) {
        guard let url = localCacheURL else { return }
        do {
            let cached = essays.map { CachedEssay(from: $0) }
            let cache = LocalCache(
                essays: cached,
                timestamp: Date(),
                shaByFileName: cachedEssaySHAs,
                fileListETag: fileListETag,
                recentCommitsETag: recentCommitsETag
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(cache).write(to: url)
        } catch {
            Self.logger.error("Save local cache failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveRecentLocalCache(_ essays: [Essay]) {
        guard let url = recentCacheURL else { return }
        do {
            let cached = Array(essays.prefix(recentCacheCount)).map { CachedEssay(from: $0) }
            let cache = RecentLocalCache(
                essays: cached,
                timestamp: Date(),
                shaByFileName: cachedEssaySHAs,
                fileListETag: fileListETag,
                recentCommitsETag: recentCommitsETag
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(cache).write(to: url)
        } catch {
            Self.logger.error("Save recent cache failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private enum RemoteFileListState {
        case notModified
        case modified([GitHubFileInfo])
    }

    private enum RemoteRecentFileNamesState {
        case notModified
        case modified([String])
    }

    private func fetchFileListState() async throws -> RemoteFileListState {
        let endpoint = "/repos/\(AppConfig.githubOwner)/\(AppConfig.githubRepo)/contents/\(essaysPath)?ref=\(AppConfig.githubBranch)"
        let result: (value: [GitHubFileInfo]?, isNotModified: Bool, eTag: String?) =
            try await GitHubService.shared.requestIfModified(endpoint: endpoint, ifNoneMatch: fileListETag)

        if let eTag = result.eTag {
            fileListETag = eTag
        }

        if result.isNotModified {
            return .notModified
        }
        return .modified(result.value ?? [])
    }

    private func fetchFileList() async throws -> [GitHubFileInfo] {
        let endpoint = "/repos/\(AppConfig.githubOwner)/\(AppConfig.githubRepo)/contents/\(essaysPath)?ref=\(AppConfig.githubBranch)"
        return try await GitHubService.shared.request(endpoint: endpoint)
    }

    private func fetchRecentFileNamesState(limit: Int) async throws -> RemoteRecentFileNamesState {
        let desired = max(limit, 1)
        let perPage = min(max(desired * 3, 30), 100)
        let encodedPath = essaysPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? essaysPath
        let endpoint = "/repos/\(AppConfig.githubOwner)/\(AppConfig.githubRepo)/commits?path=\(encodedPath)&sha=\(AppConfig.githubBranch)&per_page=\(perPage)"
        let result: (value: [GHCommitSummary]?, isNotModified: Bool, eTag: String?) =
            try await GitHubService.shared.requestIfModified(endpoint: endpoint, ifNoneMatch: recentCommitsETag)

        if let eTag = result.eTag {
            recentCommitsETag = eTag
        }

        if result.isNotModified {
            return .notModified
        }

        guard let commits = result.value, !commits.isEmpty else {
            return .modified([])
        }

        let names = await fetchRecentFileNamesFromCommits(commits, desiredCount: desired)
        return .modified(names)
    }

    private func fallbackRecentFileNamesFromFileList(limit: Int) async throws -> [String] {
        let files = try await fetchFileList()
        let mdFiles = files.filter { $0.name.hasSuffix(".md") }
        let prioritized = prioritizeRecentFiles(mdFiles)
        return Array(prioritized.prefix(limit).map { $0.name })
    }

    private func fetchRecentFileNamesFromCommits(
        _ commits: [GHCommitSummary],
        desiredCount: Int
    ) async -> [String] {
        guard desiredCount > 0, !commits.isEmpty else { return [] }

        let inspectCount = min(max(desiredCount * 2, 20), commits.count)
        let selected = Array(commits.prefix(inspectCount))
        var filesByIndex = Array(repeating: [String](), count: selected.count)

        await withTaskGroup(of: (Int, [String]).self) { group in
            var submitted = 0
            for (index, commit) in selected.enumerated() {
                if submitted >= maxConcurrentFetch, let (doneIndex, fileNames) = await group.next() {
                    filesByIndex[doneIndex] = fileNames
                }

                group.addTask {
                    do {
                        return (index, try await self.fetchChangedEssayFileNames(commitSHA: commit.sha))
                    } catch {
                        Self.logger.error(
                            "Failed to fetch commit detail \(commit.sha, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                        return (index, [])
                    }
                }
                submitted += 1
            }

            for await (index, fileNames) in group {
                filesByIndex[index] = fileNames
            }
        }

        var uniqueNames: Set<String> = []
        var orderedNames: [String] = []
        orderedNames.reserveCapacity(desiredCount)

        for names in filesByIndex {
            for fileName in names where uniqueNames.insert(fileName).inserted {
                orderedNames.append(fileName)
                if orderedNames.count >= desiredCount {
                    return orderedNames
                }
            }
        }

        return orderedNames
    }

    private func fetchChangedEssayFileNames(commitSHA: String) async throws -> [String] {
        let endpoint = "/repos/\(AppConfig.githubOwner)/\(AppConfig.githubRepo)/commits/\(commitSHA)"
        let detail: GHCommitDetailResponse = try await GitHubService.shared.request(endpoint: endpoint)
        guard let files = detail.files, !files.isEmpty else { return [] }

        var result: [String] = []
        result.reserveCapacity(files.count)

        for file in files {
            guard file.filename.hasPrefix("\(essaysPath)/"),
                  file.filename.hasSuffix(".md"),
                  file.status != "removed" else {
                continue
            }

            if let name = file.filename.split(separator: "/").last, !name.isEmpty {
                result.append(String(name))
            }
        }

        return result
    }

    private func fetchEssaysFromFiles(
        _ files: [GitHubFileInfo],
        cachedByName: [String: Essay]
    ) async -> (essays: [Essay], failed: [String], shaByFileName: [String: String]) {
        guard !files.isEmpty else { return ([], [], [:]) }

        var essays: [Essay] = []
        var failedFiles: [String] = []
        var shaByFileName: [String: String] = [:]
        var pendingFiles: [GitHubFileInfo] = []

        for file in files {
            if !file.sha.isEmpty,
               let cachedSHA = cachedEssaySHAs[file.name],
               cachedSHA == file.sha,
               let cachedEssay = cachedByName[file.name] {
                essays.append(cachedEssay)
                shaByFileName[file.name] = file.sha
            } else {
                pendingFiles.append(file)
            }
        }

        await withTaskGroup(of: (String, String, Essay?).self) { group in
            var submitted = 0
            for file in pendingFiles {
                if submitted >= maxConcurrentFetch {
                    if let (fileName, sha, essay) = await group.next() {
                        if let essay {
                            essays.append(essay)
                            if !sha.isEmpty {
                                shaByFileName[fileName] = sha
                            }
                        } else {
                            failedFiles.append(fileName)
                        }
                    }
                }

                let fileName = file.name
                let fileSHA = file.sha
                group.addTask {
                    do {
                        return (fileName, fileSHA, try await self.fetchEssayContent(fileName: fileName))
                    } catch {
                        Self.logger.error(
                            "Failed to fetch essay \(fileName, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                        return (fileName, fileSHA, nil)
                    }
                }
                submitted += 1
            }

            for await (fileName, sha, essay) in group {
                if let essay {
                    essays.append(essay)
                    if !sha.isEmpty {
                        shaByFileName[fileName] = sha
                    }
                } else {
                    failedFiles.append(fileName)
                }
            }
        }

        return (essays, failedFiles, shaByFileName)
    }

    private func prioritizeRecentFiles(_ files: [GitHubFileInfo]) -> [GitHubFileInfo] {
        files.sorted { lhs, rhs in
            let lhsDate = Self.extractDateFromFileName(lhs.name)
            let rhsDate = Self.extractDateFromFileName(rhs.name)

            switch (lhsDate, rhsDate) {
            case let (l?, r?) where l != r:
                return l > r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.name > rhs.name
            }
        }
    }

    private func updateCacheWithRecent(_ recent: [Essay], shaByFileName: [String: String]) {
        var byFileName: [String: Essay] = [:]
        byFileName.reserveCapacity(cachedEssays.count + recent.count)

        for essay in cachedEssays {
            byFileName[essay.fileName] = essay
        }
        for essay in recent {
            byFileName[essay.fileName] = essay
        }

        cachedEssays = byFileName.values.sorted { $0.pubDate > $1.pubDate }
        if cachedEssays.count > 200 {
            cachedEssays = Array(cachedEssays.prefix(200))
        }
        for (fileName, sha) in shaByFileName {
            if !sha.isEmpty {
                cachedEssaySHAs[fileName] = sha
            }
        }
        if cachedEssaySHAs.count > 500 {
            let keepNames = Set(cachedEssays.prefix(500).map { $0.fileName })
            cachedEssaySHAs = cachedEssaySHAs.filter { keepNames.contains($0.key) }
        }
        cacheTimestamp = Date()
        saveRecentLocalCache(cachedEssays)
        if hasCompleteCache {
            saveLocalCache(cachedEssays)
        }
    }

    private static func extractDateFromFileName(_ fileName: String) -> Date? {
        let range = NSRange(fileName.startIndex..., in: fileName)
        guard let match = fileNameDateRegex.firstMatch(in: fileName, range: range),
              let yRange = Range(match.range(at: 1), in: fileName),
              let mRange = Range(match.range(at: 2), in: fileName),
              let dRange = Range(match.range(at: 3), in: fileName),
              let year = Int(String(fileName[yRange])),
              let month = Int(String(fileName[mRange])),
              let day = Int(String(fileName[dRange])) else {
            return nil
        }

        var hour = 0
        var minute = 0
        var second = 0
        if let tsRange = Range(match.range(at: 4), in: fileName) {
            let ts = String(fileName[tsRange])
            if ts.count == 6 {
                hour = Int(ts.prefix(2)) ?? 0
                minute = Int(ts.dropFirst(2).prefix(2)) ?? 0
                second = Int(ts.suffix(2)) ?? 0
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = cstTimeZone
        let components = DateComponents(
            timeZone: cstTimeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
        return calendar.date(from: components)
    }
}

// MARK: - 错误

enum EssayError: LocalizedError {
    case networkError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return String(format: "error.essay.networkError".localized, msg)
        case .parseError(let msg): return String(format: "error.essay.parseError".localized, msg)
        }
    }
}
